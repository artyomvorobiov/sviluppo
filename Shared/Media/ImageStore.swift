import CryptoKit
import Foundation
import ImageIO
import UIKit

/// Загрузка и кэширование изображений.
/// Файлы лежат в общем контейнере (виджет берёт их оттуда), в память попадают
/// уже уменьшенные копии — это важно для виджетов с их лимитом памяти.
final class ImageStore {
    static let shared = ImageStore()

    /// Размер, до которого уменьшаются картинки для виджетов.
    static let widgetMaxPixel: CGFloat = 1000

    private let memory = NSCache<NSString, UIImage>()
    private let directory: URL
    private let session: URLSession
    private let lock = NSLock()
    private var inFlight: [URL: Task<Data?, Never>] = [:]

    init() {
        directory = AppGroup.directory("Library/Caches/Images")
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.urlCache = nil
        configuration.httpAdditionalHeaders = ["User-Agent": AppConfig.userAgent]
        session = URLSession(configuration: configuration)
        memory.totalCostLimit = 80 * 1024 * 1024
    }

    // MARK: - Публичный интерфейс

    /// Только из памяти — мгновенно, без обращения к диску.
    func memoryImage(for url: URL, maxPixel: CGFloat) -> UIImage? {
        memory.object(forKey: cacheKey(url, maxPixel))
    }

    /// Из памяти или с диска, без сети.
    func cachedImage(for url: URL, maxPixel: CGFloat) -> UIImage? {
        if let image = memoryImage(for: url, maxPixel: maxPixel) { return image }
        guard let data = try? Data(contentsOf: fileURL(for: url)),
              let image = Self.downsample(data, maxPixel: maxPixel)
        else { return nil }
        remember(image, url: url, maxPixel: maxPixel)
        return image
    }

    /// Из кэша или из сети.
    func image(for url: URL, maxPixel: CGFloat) async -> UIImage? {
        if let image = cachedImage(for: url, maxPixel: maxPixel) { return image }
        guard let data = await data(for: url), let image = Self.downsample(data, maxPixel: maxPixel) else { return nil }
        remember(image, url: url, maxPixel: maxPixel)
        return image
    }

    /// Есть ли файл в дисковом кэше.
    func isCached(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: url).path)
    }

    /// Скачать заранее (например, завтрашние картинки для виджета).
    func prefetch(_ url: URL) async {
        guard !isCached(url) else { return }
        _ = await data(for: url)
    }

    func clearAll() {
        memory.removeAllObjects()
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Удаляет самые старые файлы, если кэш больше лимита.
    func trimDiskCache(limit: Int = 250 * 1024 * 1024) {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)) else { return }
        var entries: [(url: URL, date: Date, size: Int)] = files.map { url in
            let values = try? url.resourceValues(forKeys: keys)
            return (url, values?.contentModificationDate ?? .distantPast, values?.fileSize ?? 0)
        }
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > limit else { return }
        entries.sort { $0.date < $1.date }
        for entry in entries where total > limit {
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }

    // MARK: - Внутреннее

    private func fileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name)
    }

    private func cacheKey(_ url: URL, _ maxPixel: CGFloat) -> NSString {
        "\(url.absoluteString)#\(Int(maxPixel))" as NSString
    }

    private func remember(_ image: UIImage, url: URL, maxPixel: CGFloat) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        memory.setObject(image, forKey: cacheKey(url, maxPixel), cost: cost)
    }

    private func data(for url: URL) async -> Data? {
        let file = fileURL(for: url)
        if let data = try? Data(contentsOf: file) { return data }

        let session = self.session
        let task: Task<Data?, Never> = lock.withLock {
            if let existing = inFlight[url] { return existing }
            let newTask = Task<Data?, Never> {
                do {
                    let (data, response) = try await session.data(from: url)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), !data.isEmpty else { return nil }
                    try? data.write(to: file, options: .atomic)
                    return data
                } catch {
                    return nil
                }
            }
            inFlight[url] = newTask
            return newTask
        }

        let data = await task.value
        lock.withLock { inFlight[url] = nil }
        return data
    }

    /// Уменьшение без распаковки полного изображения в память (ImageIO).
    static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxPixel))
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: image)
    }
}
