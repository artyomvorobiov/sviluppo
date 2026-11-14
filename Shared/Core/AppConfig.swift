import Foundation

/// Глобальные настройки «Квартета». Всё, что может понадобиться поменять, собрано здесь.
enum AppConfig {
    /// Название приложения в интерфейсе.
    static let appName = "Квартет"

    /// URL-схема для переходов из виджетов и уведомлений (kvartet://item/<id>, kvartet://today).
    /// Зарегистрирована в Config/App-Info.plist.
    static let urlScheme = "kvartet"

    /// Адрес, откуда приложение подтягивает обновлённый каталог (тот же формат, что и
    /// Shared/Resources/catalog.json): файл в публичном репозитории kvartet-catalog.
    /// Пока файла там нет или он с ошибкой, используется каталог, встроенный в приложение.
    /// nil — только встроенный каталог.
    static let remoteCatalogURL: URL? = URL(string: "https://raw.githubusercontent.com/artyomvorobiov/kvartet-catalog/main/catalog.json")

    /// Как часто проверять удалённый каталог.
    static let remoteCatalogRefreshInterval: TimeInterval = 6 * 3600

    /// User-Agent для запросов к Википедии и iTunes: правила Wikimedia просят представляться.
    static let userAgent = "Kvartet/1.0 (iOS app; https://github.com/artyomvorobiov/sviluppo)"

    /// Ширина картинки, которую просим у Википедии (стандартный размер Wikimedia).
    static let wikipediaImageWidth = 2560

    /// За сколько дней вперёд планировать напоминания (лимит iOS — 64 локальных уведомления).
    static let reminderDaysAhead = 30
}
