import Foundation

/// Рубрика «В этот день»: одна короткая история, привязанная к календарной дате.
/// В отличие от выпусков, у всех пользователей в один день она одна и та же.
/// Хранится в catalog.json в массиве `days` (формат — в docs/catalog.md).
struct DayNote: Codable, Identifiable, Hashable {
    /// Месяц и день: "11-15".
    var date: String
    /// Повод: birthday, memory, premiere, event (от него зависит подпись).
    var kind: String?
    /// Год события: "1887".
    var year: String?
    /// Заголовок: имя человека или название события.
    var title: String
    /// Два-три предложения: что случилось и почему это интересно.
    var text: String
    /// Что можно сделать сегодня: посмотреть, послушать, прочитать.
    var tip: String?
    /// Статья Википедии ("ru:Моне,_Клод"): оттуда берутся картинка и ссылка «Подробнее».
    var wiki: String?
    /// Прямая ссылка на изображение.
    var image: String?
    /// id рекомендации из каталога, если она связана с этой датой.
    var item: String?

    var id: String { date }

    /// Подпись над заголовком: «Родился в этот день · 1887».
    var label: String {
        let base: String
        switch kind {
        case "birthday": base = "День рождения"
        case "memory": base = "День памяти"
        case "premiere": base = "Премьера"
        default: base = "В этот день"
        }
        guard let year, !year.isEmpty else { return base }
        return "\(base) · \(year)"
    }

    /// Ключ календарного дня для даты: "11-15".
    static func key(for date: Date) -> String {
        let parts = Days.calendar.dateComponents([.month, .day], from: date)
        return String(format: "%02d-%02d", parts.month ?? 0, parts.day ?? 0)
    }

    /// Рекомендация-«обёртка», чтобы показать картинку и найти русскую статью теми же средствами,
    /// что и у картин (свободное изображение из Википедии, общий кэш).
    var artworkItem: Item? {
        guard wiki != nil || image != nil else { return nil }
        return Item(id: "day-\(date)", kind: .painting, title: title, creator: "", summary: text, wiki: wiki, image: image)
    }
}
