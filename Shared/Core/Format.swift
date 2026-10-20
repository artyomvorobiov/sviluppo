import Foundation

/// Русские форматы дат, длительностей и склонения.
enum Format {
    static let russian = Locale(identifier: "ru_RU")

    private static func formatter(_ template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = russian
        formatter.calendar = Days.calendar
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    private static let weekdayDayMonthFormatter = formatter("EEEEdMMMM")
    private static let dayMonthFormatter = formatter("dMMMM")
    private static let shortWeekdayDayMonthFormatter = formatter("EEdMMM")
    private static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = russian
        formatter.calendar = Days.calendar
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()

    /// «вторник, 20 октября»
    static func weekdayDayMonth(_ date: Date) -> String {
        weekdayDayMonthFormatter.timeZone = .current
        return weekdayDayMonthFormatter.string(from: date)
    }

    /// «20 октября»
    static func dayMonth(_ date: Date) -> String {
        dayMonthFormatter.timeZone = .current
        return dayMonthFormatter.string(from: date)
    }

    /// «вт, 20 окт.»
    static func shortDay(_ date: Date) -> String {
        shortWeekdayDayMonthFormatter.timeZone = .current
        return shortWeekdayDayMonthFormatter.string(from: date)
    }

    /// «Октябрь 2026»
    static func monthYear(_ date: Date) -> String {
        monthYearFormatter.timeZone = .current
        return monthYearFormatter.string(from: date).capitalized(with: russian)
    }

    /// «3 мин», «45 мин», «1 ч 52 мин», «2 ч»
    static func duration(minutes: Int) -> String {
        guard minutes >= 60 else { return "\(max(minutes, 1)) мин" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) ч" : "\(hours) ч \(rest) мин"
    }

    /// Русское склонение: plural(5, "день", "дня", "дней") → "дней".
    static func plural(_ number: Int, _ one: String, _ few: String, _ many: String) -> String {
        let n = abs(number)
        let lastTwo = n % 100
        let last = n % 10
        if last == 1 && lastTwo != 11 { return one }
        if (2...4).contains(last) && !(12...14).contains(lastTwo) { return few }
        return many
    }

    /// «5 дней»
    static func count(_ number: Int, _ one: String, _ few: String, _ many: String) -> String {
        "\(number) \(plural(number, one, few, many))"
    }
}
