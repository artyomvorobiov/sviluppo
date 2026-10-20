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

/// Изображения для виджетов: сначала из общего кэша (его наполняет приложение), потом из сети.
enum WidgetArtwork {
    static func cachedImage(for item: Item, maxPixel: CGFloat) async -> UIImage? {
        guard let url = await MediaResolver.shared.cachedArtworkURL(for: item) else { return nil }
        return ImageStore.shared.cachedImage(for: url, maxPixel: maxPixel)
    }

    static func image(for item: Item, maxPixel: CGFloat) async -> UIImage? {
        if let cached = await cachedImage(for: item, maxPixel: maxPixel) { return cached }
        guard let url = await MediaResolver.shared.artworkURL(for: item) else { return nil }
        return await ImageStore.shared.image(for: url, maxPixel: maxPixel)
    }
}

/// Картинка в виджете: в тонированном режиме iOS 18+ окрашивается в цвет экрана «Домой».
struct WidgetPhoto: View {
    let image: UIImage

    var body: some View {
        if #available(iOS 18.0, *) {
            Image(uiImage: image)
                .resizable()
                .widgetAccentedRenderingMode(.accentedDesaturated)
                .scaledToFill()
        } else {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        }
    }
}

/// Значок «готово» поверх изображения.
struct DoneBadge: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 18, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(Color.white, Color.black.opacity(0.35))
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
