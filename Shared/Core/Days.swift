import Foundation

/// Работа с календарными днями. Всегда григорианский календарь в текущем часовом поясе,
/// чтобы «день» не зависел от выбранного на телефоне календаря.
enum Days {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.locale = Locale(identifier: "ru_RU")
        return calendar
    }

    /// Ключ дня в формате "2026-10-20".
    static func key(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(fromKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    static func adding(days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: startOfDay(date)) ?? date.addingTimeInterval(Double(days) * 86_400)
    }

    /// Количество календарных дней от `from` до `to` (может быть отрицательным).
    static func between(_ from: Date, _ to: Date) -> Int {
        calendar.dateComponents([.day], from: startOfDay(from), to: startOfDay(to)).day ?? 0
    }

    static func isSameDay(_ a: Date, _ b: Date) -> Bool {
        calendar.isDate(a, inSameDayAs: b)
    }

    /// Начало следующего дня — момент, когда меняется выпуск.
    static func nextMidnight(after date: Date) -> Date {
        adding(days: 1, to: date)
    }
}
