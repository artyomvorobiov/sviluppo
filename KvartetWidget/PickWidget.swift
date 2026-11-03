import AppIntents
import SwiftUI
import UIKit
import WidgetKit

// MARK: - Настройка виджета

enum PickKind: String, AppEnum {
    case painting
    case article
    case album
    case film

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Тип рекомендации"

    static var caseDisplayRepresentations: [PickKind: DisplayRepresentation] = [
        .painting: "Картина",
        .article: "Статья",
        .album: "Альбом",
        .film: "Фильм"
    ]

    var itemKind: ItemKind {
        ItemKind(rawValue: rawValue) ?? .painting
    }
}

struct PickWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Рекомендация дня"
    static var description = IntentDescription("Одна рекомендация из сегодняшнего выпуска.")

    @Parameter(title: "Что показывать", default: .painting)
    var kind: PickKind

    init() {}
}

// MARK: - Данные

struct PickEntry: TimelineEntry {
    let date: Date
    let content: PickContent?
}

struct PickProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PickEntry {
        let snapshot = DaySnapshot.load(for: Date(), kinds: Set(ItemKind.allCases))
        let content = snapshot.issue.item(.painting).map { item in
            PickContent(
                item: item,
                theme: snapshot.issue.theme,
                isDone: false,
                layout: PickLayout(kind: item.kind, family: context.family, size: context.displaySize, imageAspect: nil),
                image: nil
            )
        }
        return PickEntry(date: Date(), content: content)
    }

    func snapshot(for configuration: PickWidgetIntent, in context: Context) async -> PickEntry {
        // В галерее виджетов — только то, что уже скачано: превью должно появиться сразу.
        await entry(for: Date(), kind: configuration.kind.itemKind, context: context, allowNetwork: !context.isPreview)
    }

    func timeline(for configuration: PickWidgetIntent, in context: Context) async -> Timeline<PickEntry> {
        let kind = configuration.kind.itemKind
        let now = Date()
        let midnight = Days.nextMidnight(after: now)
        var entries: [PickEntry] = []
        for date in [now, midnight] {
            entries.append(await entry(for: date, kind: kind, context: context, allowNetwork: true))
        }
        return Timeline(entries: entries, policy: .after(midnight.addingTimeInterval(60)))
    }

    private func entry(for date: Date, kind: ItemKind, context: Context, allowNetwork: Bool) async -> PickEntry {
        let snapshot = DaySnapshot.load(for: date, kinds: Set(ItemKind.allCases))
        guard let item = snapshot.issue.item(kind) else { return PickEntry(date: date, content: nil) }
        let content = await PickContent.load(
            item: item,
            theme: snapshot.issue.theme,
            isDone: snapshot.isDone(item),
            family: context.family,
            size: context.displaySize,
            scale: WidgetScale.current,
            allowNetwork: allowNetwork
        )
        return PickEntry(date: date, content: content)
    }
}

// MARK: - Виджет

struct PickWidget: Widget {
    let kind = "PickWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: PickWidgetIntent.self, provider: PickProvider()) { entry in
            PickWidgetView(entry: entry)
        }
        .configurationDisplayName("Рекомендация дня")
        .description("Картина, альбом, фильм или статья дня. Картина в режиме StandBy — как цифровая рамка.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}

struct PickWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PickEntry

    var body: some View {
        Group {
            if let content = entry.content {
                PickWidgetContent(content: content, family: family)
                    .widgetURL(content.item.deepLink)
            } else {
                Text("Выпуск пуст")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .containerBackground(for: .widget) {
            Theme.paper
        }
    }
}
