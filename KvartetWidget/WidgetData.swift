import SwiftUI
import UIKit
import WidgetKit

/// Всё, что нужно виджету о конкретном дне.
struct DaySnapshot {
    let date: Date
    let issue: Issue
    let items: [Item]
    let done: Set<String>

    var doneCount: Int { items.filter { done.contains($0.id) }.count }

    /// Первая ещё не изученная рекомендация.
    var nextItem: Item? { items.first { !done.contains($0.id) } }

    func isDone(_ item: Item) -> Bool { done.contains(item.id) }

    /// Загружает выпуск дня из каталога и отметки из общего контейнера.
    static func load(for date: Date, kinds: Set<ItemKind>? = nil, library: ContentLibrary = ContentLibrary.load()) -> DaySnapshot {
        let state = UserStateStore.shared.ensureStartDay()
        let planner = DayPlanner(library: library, startDay: DayPlanner.startDay(from: state))
        let issue = planner.issue(for: date)
        let items = issue.items(for: kinds ?? SharedPreferences.enabledKinds())
        return DaySnapshot(date: date, issue: issue, items: items, done: Set(state.completions.keys))
    }
}

extension View {
    /// Фон виджета; для экрана блокировки — системная подложка.
    @ViewBuilder
    func widgetBackground(for family: WidgetFamily) -> some View {
        switch family {
        case .accessoryCircular:
            containerBackground(for: .widget) { AccessoryWidgetBackground() }
        case .accessoryRectangular, .accessoryInline:
            containerBackground(for: .widget) { Color.clear }
        default:
            containerBackground(for: .widget) { Theme.paper }
        }
    }
}
