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
            migrateLocalFiles(to: url)
            return url
        }
        try? FileManager.default.createDirectory(at: localURL, withIntermediateDirectories: true)
        return localURL
    }()

    static let defaults: UserDefaults = {
        if isShared, let shared = UserDefaults(suiteName: identifier) {
            migrateLocalDefaults(to: shared)
            return shared
        }
        return .standard
    }()

    // MARK: - Переезд из локальной папки в общую

    /// Где лежат данные, пока App Group не настроена.
    private static let localURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Kvartet", isDirectory: true)

    /// Настройки, которые переезжают вместе с данными.
    private static let migratedDefaultsKeys = [
        "enabledKinds", "reminderEnabled", "reminderHour", "reminderMinute",
        "musicService", "filmService", "readerTheme", "readerTextScale", "didOnboard"
    ]

    /// Переезжать может только приложение: у виджета своя локальная папка без отметок пользователя.
    private static var isMainApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    /// Когда App Group заработала (например, после настройки подписи), отметки, сделанные
    /// без неё, переносятся в общую папку — иначе они пропали бы, а выпуски начались бы заново.
    private static func migrateLocalFiles(to group: URL) {
        let manager = FileManager.default
        guard isMainApp,
              let names = try? manager.contentsOfDirectory(atPath: localURL.path), !names.isEmpty
        else { return }
        for name in names {
            let source = localURL.appendingPathComponent(name)
            let destination = group.appendingPathComponent(name)
            if manager.fileExists(atPath: destination.path) {
                // Виджет мог успеть создать в группе пустое состояние — отметки из приложения важнее.
                guard name == "user-state.json", !hasUserProgress(destination), hasUserProgress(source) else { continue }
                try? manager.removeItem(at: destination)
            }
            try? manager.moveItem(at: source, to: destination)
        }
    }

    private static func migrateLocalDefaults(to shared: UserDefaults) {
        guard isMainApp else { return }
        let local = UserDefaults.standard
        for key in migratedDefaultsKeys {
            guard let value = local.object(forKey: key) else { continue }
            if shared.object(forKey: key) == nil {
                shared.set(value, forKey: key)
            }
            local.removeObject(forKey: key)
        }
    }

    /// Есть ли в файле состояния отметки или отложенное.
    private static func hasUserProgress(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        let completions = object["completions"] as? [String: Any] ?? [:]
        let bookmarks = object["bookmarks"] as? [String: Any] ?? [:]
        return !completions.isEmpty || !bookmarks.isEmpty
    }

    /// Папка внутри общего контейнера (создаётся при первом обращении).
    static func directory(_ relativePath: String) -> URL {
        let url = containerURL.appendingPathComponent(relativePath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
