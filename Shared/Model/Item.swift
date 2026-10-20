import Foundation

/// Одна рекомендация: фильм, альбом, картина или статья.
/// Формат JSON описан в content/README.md — он же пригодится для версии под Android.
struct Item: Codable, Identifiable, Hashable {
    /// Уникальный идентификатор: латиница, цифры и дефис ("painting-hunters-in-the-snow").
    var id: String
    var kind: ItemKind
    /// Название по-русски.
    var title: String
    /// Оригинальное название (для поиска обложек и в стриминговых сервисах).
    var originalTitle: String?
    /// Режиссёр, исполнитель, художник или автор.
    var creator: String
    /// Имя автора латиницей, если `creator` по-русски.
    var originalCreator: String?
    /// Год или период: "1979", "1665–1667", "ок. 1665".
    var year: String?
    /// Сколько минут нужно на знакомство.
    var minutes: Int?
    /// Короткие факты: страна, техника, музей, жанр.
    var details: [String]?
    /// О чём это.
    var summary: String
    /// Почему стоит.
    var why: String?
    /// На что обратить внимание (для картин — подсказки «медленного просмотра»).
    var lookFor: [String]?
    /// Любопытный факт.
    var fact: String?
    /// Что посмотреть/послушать/прочитать дальше.
    var more: [String]?
    /// Для альбомов: трек, с которого стоит начать (по нему ищется 30-секундный фрагмент).
    var keyTrack: String?
    /// Для статей — адрес статьи; для остальных — необязательная ссылка.
    var url: String?
    /// Для статей — издание: «Arzamas», «Википедия».
    var source: String?
    /// Статья Википедии "en:The_Hunters_in_the_Snow": оттуда берутся изображение и ссылка «Подробнее».
    var wiki: String?
    /// Прямая ссылка на изображение (если не хочется искать автоматически).
    var image: String?
    /// Поисковый запрос для стриминговых сервисов, если «автор + название» не подходит.
    var search: String?
}

extension Item {
    /// Год числом (первая четырёхзначная группа цифр).
    var yearValue: Int? {
        guard let year else { return nil }
        return year
            .split(whereSeparator: { !$0.isNumber })
            .first(where: { $0.count == 4 })
            .flatMap { Int($0) }
    }

    /// Строка под заголовком: «Питер Брейгель Старший, 1565».
    var metaLine: String {
        switch kind {
        case .article:
            let source = self.source ?? ""
            if source.isEmpty || source == creator { return creator }
            return "\(source) · \(creator)"
        case .painting:
            return [creator, year].compactMap { $0 }.joined(separator: ", ")
        case .album, .film:
            return [creator, year].compactMap { $0 }.joined(separator: " · ")
        }
    }

    var articleURL: URL? {
        url.flatMap { URL(string: $0) }
    }

    /// Страница Википедии из поля `wiki`.
    var wikipediaURL: URL? {
        guard let wiki else { return nil }
        let parts = wiki.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let path = parts[1].replacingOccurrences(of: " ", with: "_")
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return URL(string: "https://\(parts[0]).wikipedia.org/wiki/\(path)")
    }

    var deepLink: URL {
        URL(string: "\(AppConfig.urlScheme)://item/\(id)") ?? URL(string: "\(AppConfig.urlScheme)://today")!
    }

    /// Похоже ли на русскоязычное произведение (влияет на поиск обложек).
    var isRussianWork: Bool {
        let text = (originalTitle ?? title) + " " + (originalCreator ?? creator)
        return text.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
    }

    /// Стабильное число 0…1 для оформления заглушек (одно и то же на всех устройствах).
    var stableSeed: Double {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return Double(hash % 10_000) / 10_000
    }
}
