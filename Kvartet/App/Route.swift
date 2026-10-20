import SwiftUI

enum AppTab: Hashable {
    case today
    case archive
    case journal
}

/// Экраны, на которые можно перейти внутри вкладки.
enum Route: Hashable {
    /// Рекомендация по id.
    case item(String)
    /// Выпуск за день ("2026-10-20").
    case day(String)
}

/// Экран для маршрута — общий для всех вкладок.
struct RouteDestination: View {
    let route: Route
    @Environment(AppModel.self) private var model

    var body: some View {
        switch route {
        case .item(let id):
            if let item = model.item(id: id) {
                ItemDetailView(item: item)
            } else {
                ContentUnavailableView("Рекомендация не найдена", systemImage: "questionmark.circle")
            }
        case .day(let key):
            if let date = Days.date(fromKey: key) {
                IssueView(date: date, isToday: Days.isSameDay(date, model.today))
            } else {
                ContentUnavailableView("День не найден", systemImage: "calendar.badge.exclamationmark")
            }
        }
    }
}

/// Ссылка, которую можно показать в `.sheet(item:)`.
struct IdentifiedURL: Identifiable, Hashable {
    let url: URL
    var id: String { url.absoluteString }

    init(_ url: URL) {
        self.url = url
    }
}
