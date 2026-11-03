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

    /// Исходные байты картинки: из дискового кэша или (если можно) из сети.
    func imageData(for url: URL, allowNetwork: Bool) async -> Data? {
        if let data = try? Data(contentsOf: fileURL(for: url)) { return data }
        guard allowNetwork else { return nil }
        return await data(for: url)
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

    /// Размер картинки в пикселях (с учётом поворота из EXIF) — без распаковки изображения.
    static func pixelSize(of data: Data) -> CGSize? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0
        else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return (5...8).contains(orientation) ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    /// Картинка ровно под рамку `size` (в точках): обрезана по центру до её пропорций
    /// и уменьшена до `size × scale` пикселей. Для виджетов это важно: WidgetKit не показывает виджет,
    /// если изображение по площади больше него, а лишние пиксели только тратят память.
    static func render(_ data: Data, filling size: CGSize, scale: CGFloat) -> UIImage? {
        guard size.width >= 1, size.height >= 1, let pixels = pixelSize(of: data) else { return nil }
        // Сколько пикселей нужно по длинной стороне исходника, чтобы закрыть рамку без растягивания.
        let cover = max(size.width * scale / pixels.width, size.height * scale / pixels.height)
        let needed = min(max(pixels.width, pixels.height), max(pixels.width, pixels.height) * cover)
        guard let image = downsample(data, maxPixel: ceil(needed)) else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let ratio = max(size.width / image.size.width, size.height / image.size.height)
        let drawn = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let origin = CGPoint(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2)
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: origin, size: drawn))
        }
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
