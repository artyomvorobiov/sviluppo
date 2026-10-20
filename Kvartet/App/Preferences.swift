import Observation
import SwiftUI
import WidgetKit

/// Музыкальный сервис для кнопки «Слушать».
enum MusicService: String, CaseIterable, Identifiable {
    case appleMusic
    case yandexMusic
    case spotify
    case youTubeMusic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleMusic: "Apple Music"
        case .yandexMusic: "Яндекс Музыка"
        case .spotify: "Spotify"
        case .youTubeMusic: "YouTube Music"
        }
    }

    func url(for item: Item) -> URL? {
        let query = item.search ?? "\(item.originalCreator ?? item.creator) \(item.originalTitle ?? item.title)"
        let encoded = query.urlQueryEncoded
        switch self {
        case .appleMusic: return URL(string: "https://music.apple.com/search?term=\(encoded)")
        case .yandexMusic: return URL(string: "https://music.yandex.ru/search?text=\(encoded)")
        case .spotify: return URL(string: "https://open.spotify.com/search/\(encoded)")
        case .youTubeMusic: return URL(string: "https://music.youtube.com/search?q=\(encoded)")
        }
    }
}

/// Сервис для кнопки «Где смотреть».
enum FilmService: String, CaseIterable, Identifiable {
    case kinopoisk
    case appleTV
    case imdb
    case letterboxd

    var id: String { rawValue }

    var title: String {
        switch self {
        case .kinopoisk: "Кинопоиск"
        case .appleTV: "Apple TV"
        case .imdb: "IMDb"
        case .letterboxd: "Letterboxd"
        }
    }

    func url(for item: Item) -> URL? {
        let year = item.yearValue.map { " \($0)" } ?? ""
        switch self {
        case .kinopoisk:
            return URL(string: "https://www.kinopoisk.ru/index.php?kp_query=\((item.title + year).urlQueryEncoded)")
        case .appleTV:
            return URL(string: "https://tv.apple.com/search?term=\((item.originalTitle ?? item.title).urlQueryEncoded)")
        case .imdb:
            return URL(string: "https://www.imdb.com/find/?q=\(((item.originalTitle ?? item.title) + year).urlQueryEncoded)")
        case .letterboxd:
            return URL(string: "https://letterboxd.com/search/films/\((item.originalTitle ?? item.title).urlQueryEncoded)/")
        }
    }

    /// Поиск трейлера на YouTube — запасной вариант, если в iTunes трейлера нет.
    static func youTubeTrailerURL(for item: Item) -> URL? {
        let year = item.yearValue.map { " \($0)" } ?? ""
        let query = "\(item.title)\(year) трейлер"
        return URL(string: "https://www.youtube.com/results?search_query=\(query.urlQueryEncoded)")
    }
}

/// Оформление читалки.
enum ReaderTheme: String, CaseIterable, Identifiable {
    case auto
    case light
    case sepia
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Как в системе"
        case .light: "Светлая"
        case .sepia: "Сепия"
        case .dark: "Тёмная"
        }
    }
}

extension String {
    /// Кодирование для параметра URL (строже, чем .urlQueryAllowed: «&», «+», «=» тоже кодируются).
    var urlQueryEncoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}

/// Настройки пользователя. Хранятся в общих UserDefaults (виджет тоже их читает).
@MainActor
@Observable
final class Preferences {
    private enum Keys {
        static let reminderEnabled = "reminderEnabled"
        static let reminderHour = "reminderHour"
        static let reminderMinute = "reminderMinute"
        static let musicService = "musicService"
        static let filmService = "filmService"
        static let readerTheme = "readerTheme"
        static let readerTextScale = "readerTextScale"
        static let didOnboard = "didOnboard"
    }

    private let defaults = AppGroup.defaults

    private var storedKinds: Set<ItemKind>
    private var storedReminderEnabled: Bool
    private var storedReminderHour: Int
    private var storedReminderMinute: Int
    private var storedMusicService: MusicService
    private var storedFilmService: FilmService
    private var storedReaderTheme: ReaderTheme
    private var storedReaderTextScale: Double
    private var storedDidOnboard: Bool

    init() {
        let defaults = AppGroup.defaults
        storedKinds = SharedPreferences.enabledKinds(defaults)
        storedReminderEnabled = defaults.bool(forKey: Keys.reminderEnabled)
        storedReminderHour = defaults.object(forKey: Keys.reminderHour) as? Int ?? 9
        storedReminderMinute = defaults.object(forKey: Keys.reminderMinute) as? Int ?? 0
        storedMusicService = defaults.string(forKey: Keys.musicService).flatMap(MusicService.init(rawValue:)) ?? .appleMusic
        storedFilmService = defaults.string(forKey: Keys.filmService).flatMap(FilmService.init(rawValue:)) ?? .kinopoisk
        storedReaderTheme = defaults.string(forKey: Keys.readerTheme).flatMap(ReaderTheme.init(rawValue:)) ?? .auto
        storedReaderTextScale = defaults.object(forKey: Keys.readerTextScale) as? Double ?? 1.0
        storedDidOnboard = defaults.bool(forKey: Keys.didOnboard)
    }

    /// Какие типы показывать. Хотя бы один всегда остаётся включённым.
    var enabledKinds: Set<ItemKind> {
        get { storedKinds }
        set {
            guard !newValue.isEmpty else { return }
            storedKinds = newValue
            SharedPreferences.setEnabledKinds(newValue, defaults)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func isEnabled(_ kind: ItemKind) -> Bool { storedKinds.contains(kind) }

    func setKind(_ kind: ItemKind, enabled: Bool) {
        var kinds = storedKinds
        if enabled { kinds.insert(kind) } else { kinds.remove(kind) }
        enabledKinds = kinds
    }

    var reminderEnabled: Bool {
        get { storedReminderEnabled }
        set { storedReminderEnabled = newValue; defaults.set(newValue, forKey: Keys.reminderEnabled) }
    }

    var reminderHour: Int {
        get { storedReminderHour }
        set { storedReminderHour = newValue; defaults.set(newValue, forKey: Keys.reminderHour) }
    }

    var reminderMinute: Int {
        get { storedReminderMinute }
        set { storedReminderMinute = newValue; defaults.set(newValue, forKey: Keys.reminderMinute) }
    }

    /// Время напоминания как Date (для DatePicker).
    var reminderTime: Date {
        get {
            Calendar.current.date(bySettingHour: storedReminderHour, minute: storedReminderMinute, second: 0, of: Date()) ?? Date()
        }
        set {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            reminderHour = parts.hour ?? 9
            reminderMinute = parts.minute ?? 0
        }
    }

    var musicService: MusicService {
        get { storedMusicService }
        set { storedMusicService = newValue; defaults.set(newValue.rawValue, forKey: Keys.musicService) }
    }

    var filmService: FilmService {
        get { storedFilmService }
        set { storedFilmService = newValue; defaults.set(newValue.rawValue, forKey: Keys.filmService) }
    }

    var readerTheme: ReaderTheme {
        get { storedReaderTheme }
        set { storedReaderTheme = newValue; defaults.set(newValue.rawValue, forKey: Keys.readerTheme) }
    }

    /// Масштаб текста в читалке: 0.8…1.6.
    var readerTextScale: Double {
        get { storedReaderTextScale }
        set {
            let clamped = min(1.6, max(0.8, newValue))
            storedReaderTextScale = clamped
            defaults.set(clamped, forKey: Keys.readerTextScale)
        }
    }

    var didOnboard: Bool {
        get { storedDidOnboard }
        set { storedDidOnboard = newValue; defaults.set(newValue, forKey: Keys.didOnboard) }
    }
}
