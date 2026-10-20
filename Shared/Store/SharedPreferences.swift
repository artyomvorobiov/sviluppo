import Foundation

/// Настройки, которые нужны и приложению, и виджету.
enum SharedPreferences {
    static let enabledKindsKey = "enabledKinds"

    /// Какие типы рекомендаций показывать (по умолчанию — все).
    static func enabledKinds(_ defaults: UserDefaults = AppGroup.defaults) -> Set<ItemKind> {
        guard let raw = defaults.string(forKey: enabledKindsKey) else { return Set(ItemKind.allCases) }
        let kinds = Set(raw.split(separator: ",").compactMap { ItemKind(rawValue: String($0)) })
        return kinds.isEmpty ? Set(ItemKind.allCases) : kinds
    }

    static func setEnabledKinds(_ kinds: Set<ItemKind>, _ defaults: UserDefaults = AppGroup.defaults) {
        let raw = ItemKind.displayOrder.filter { kinds.contains($0) }.map(\.rawValue).joined(separator: ",")
        defaults.set(raw, forKey: enabledKindsKey)
    }
}

/// Серии дней подряд с хотя бы одной отметкой.
enum Streaks {
    /// Текущая серия: если сегодня ещё ничего не отмечено, серия считается живой до конца дня.
    static func current(dates: [Date], today: Date = Date()) -> Int {
        let keys = Set(dates.map { Days.key(for: $0) })
        var day = Days.startOfDay(today)
        if !keys.contains(Days.key(for: day)) {
            day = Days.adding(days: -1, to: day)
        }
        var count = 0
        while keys.contains(Days.key(for: day)) {
            count += 1
            day = Days.adding(days: -1, to: day)
        }
        return count
    }

    static func best(dates: [Date]) -> Int {
        let days = Set(dates.map { Days.key(for: $0) }).compactMap(Days.date(fromKey:)).sorted()
        var best = 0
        var run = 0
        var previous: Date?
        for day in days {
            if let previous, Days.between(previous, day) == 1 {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        return best
    }
}
