import Foundation

/// Отметка «изучено» с необязательной оценкой и заметкой.
struct Completion: Codable, Hashable {
    var date: Date
    /// 1…5
    var rating: Int?
    var note: String?

    init(date: Date, rating: Int? = nil, note: String? = nil) {
        self.date = date
        self.rating = rating
        self.note = note
    }
}

/// Всё, что пользователь сделал: когда начал, что отметил, что отложил.
/// Хранится в общем контейнере, чтобы виджет видел те же данные.
struct UserState: Codable {
    /// День первого запуска ("2026-10-20"): от него отсчитываются выпуски.
    var startDay: String?
    /// id рекомендации → отметка.
    var completions: [String: Completion]
    /// id рекомендации → когда отложена.
    var bookmarks: [String: Date]

    init() {
        startDay = nil
        completions = [:]
        bookmarks = [:]
    }

    enum CodingKeys: String, CodingKey {
        case startDay, completions, bookmarks
    }

    // Терпимое чтение: новые версии приложения могут добавлять поля.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startDay = try container.decodeIfPresent(String.self, forKey: .startDay)
        completions = try container.decodeIfPresent([String: Completion].self, forKey: .completions) ?? [:]
        bookmarks = try container.decodeIfPresent([String: Date].self, forKey: .bookmarks) ?? [:]
    }
}
