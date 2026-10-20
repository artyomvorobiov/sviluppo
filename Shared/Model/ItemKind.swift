import Foundation

/// Тип рекомендации. Порядок в выпуске — от самого быстрого к самому долгому:
/// картина (минуты) → статья → альбом → фильм (вечер).
enum ItemKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case painting
    case article
    case album
    case film

    var id: String { rawValue }

    static let displayOrder: [ItemKind] = [.painting, .article, .album, .film]

    /// «Картина»
    var title: String {
        switch self {
        case .painting: "Картина"
        case .article: "Статья"
        case .album: "Альбом"
        case .film: "Фильм"
        }
    }

    /// «Картины»
    var pluralTitle: String {
        switch self {
        case .painting: "Картины"
        case .article: "Статьи"
        case .album: "Альбомы"
        case .film: "Фильмы"
        }
    }

    /// Склонение для счётчиков: 1 картина, 2 картины, 5 картин.
    func counted(_ number: Int) -> String {
        switch self {
        case .painting: Format.count(number, "картина", "картины", "картин")
        case .article: Format.count(number, "статья", "статьи", "статей")
        case .album: Format.count(number, "альбом", "альбома", "альбомов")
        case .film: Format.count(number, "фильм", "фильма", "фильмов")
        }
    }

    var symbol: String {
        switch self {
        case .painting: "photo.artframe"
        case .article: "newspaper"
        case .album: "opticaldisc"
        case .film: "film"
        }
    }

    /// «Прочитано» — подпись к отметке.
    var doneTitle: String {
        switch self {
        case .painting: "Рассмотрено"
        case .article: "Прочитано"
        case .album: "Прослушано"
        case .film: "Просмотрено"
        }
    }

    /// Текст кнопки отметки.
    var markActionTitle: String {
        switch self {
        case .painting: "Отметить как рассмотренное"
        case .article: "Отметить как прочитанное"
        case .album: "Отметить как прослушанное"
        case .film: "Отметить как просмотренное"
        }
    }

    /// Заголовок блока подсказок.
    var lookForTitle: String {
        switch self {
        case .painting: "На что смотреть"
        case .article: "На что обратить внимание"
        case .album: "Как слушать"
        case .film: "На что обратить внимание"
        }
    }

    /// Строка для приветственного экрана.
    var onboardingLine: String {
        switch self {
        case .painting: "Рассмотреть не спеша — за пару минут"
        case .article: "Прочитать прямо в приложении"
        case .album: "Послушать целиком, от первого трека до последнего"
        case .film: "Оставить на вечер"
        }
    }
}
