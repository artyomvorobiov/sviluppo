import Foundation

/// Общее хранилище приложения и виджета (App Group).
///
/// Идентификатор группы берётся из Info.plist (ключ `KvartetAppGroup`), а туда попадает
/// из Config/Base.xcconfig. Если App Group не настроена (например, при подписи бесплатным
/// аккаунтом без этой возможности), всё продолжает работать в локальной папке процесса —
/// просто виджет не будет видеть отметки, сделанные в приложении.
enum AppGroup {
    static let identifier: String = {
        let value = Bundle.main.object(forInfoDictionaryKey: "KvartetAppGroup") as? String
        guard let value, !value.isEmpty, !value.contains("$(") else { return "group.com.example.kvartet" }
        return value
    }()

    /// true, если контейнер группы доступен и данные действительно общие.
    static var isShared: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) != nil
    }

    static let containerURL: URL = {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kvartet", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }()

    static let defaults: UserDefaults = {
        if isShared, let shared = UserDefaults(suiteName: identifier) {
            return shared
        }
        return .standard
    }()

    /// Папка внутри общего контейнера (создаётся при первом обращении).
    static func directory(_ relativePath: String) -> URL {
        let url = containerURL.appendingPathComponent(relativePath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
