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
    let item: Item?
    let theme: String
    var image: UIImage?
    let isDone: Bool
}

struct PickProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PickEntry {
        makeEntry(date: Date(), kind: .painting, image: nil)
    }

    func snapshot(for configuration: PickWidgetIntent, in context: Context) async -> PickEntry {
        var entry = makeEntry(date: Date(), kind: configuration.kind.itemKind, image: nil)
        if let item = entry.item, item.kind != .article {
            entry.image = await WidgetArtwork.cachedImage(for: item, maxPixel: maxPixel(for: context))
        }
        return entry
    }

    func timeline(for configuration: PickWidgetIntent, in context: Context) async -> Timeline<PickEntry> {
        let kind = configuration.kind.itemKind
        let pixels = maxPixel(for: context)
        let now = Date()
        let midnight = Days.nextMidnight(after: now)
        var entries: [PickEntry] = []
        for date in [now, midnight] {
            var entry = makeEntry(date: date, kind: kind, image: nil)
            if let item = entry.item, item.kind != .article {
                entry.image = await WidgetArtwork.image(for: item, maxPixel: pixels)
            }
            entries.append(entry)
        }
        return Timeline(entries: entries, policy: .after(midnight.addingTimeInterval(60)))
    }

    private func makeEntry(date: Date, kind: ItemKind, image: UIImage?) -> PickEntry {
        let snapshot = DaySnapshot.load(for: date, kinds: Set(ItemKind.allCases))
        let item = snapshot.issue.item(kind)
        return PickEntry(
            date: date,
            item: item,
            theme: snapshot.issue.theme,
            image: image,
            isDone: item.map { snapshot.isDone($0) } ?? false
        )
    }

    /// Размер картинки под виджет (в пикселях, с запасом на Retina).
    private func maxPixel(for context: Context) -> CGFloat {
        let size = context.displaySize
        return min(1100, max(400, max(size.width, size.height) * 3))
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
            if let item = entry.item {
                content(for: item)
                    .widgetURL(item.deepLink)
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

    @ViewBuilder
    private func content(for item: Item) -> some View {
        if item.kind == .article {
            PickArticleView(item: item, theme: entry.theme, isDone: entry.isDone, family: family)
        } else if family == .systemMedium && item.kind != .painting {
            PickSideBySideView(item: item, image: entry.image, theme: entry.theme, isDone: entry.isDone)
        } else {
            PickFullBleedView(item: item, image: entry.image, isDone: entry.isDone, family: family)
        }
    }
}

// MARK: - Варианты оформления

/// Изображение на весь виджет и подпись поверх.
struct PickFullBleedView: View {
    let item: Item
    let image: UIImage?
    let isDone: Bool
    let family: WidgetFamily

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let image {
                    WidgetPhoto(image: image)
                } else {
                    PlaceholderArt(item: item, showsTitle: false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.15), .black.opacity(0.7)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.kind.title.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .opacity(0.85)
                Text(item.title)
                    .font(.system(family == .systemSmall ? .subheadline : .headline, design: .serif).weight(.semibold))
                    .lineLimit(2)
                Text(item.creator)
                    .font(.caption2)
                    .lineLimit(1)
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.4), radius: 4)
            .padding(family == .systemSmall ? 12 : 16)
        }
        .overlay(alignment: .topTrailing) {
            if isDone {
                DoneBadge().padding(10)
            }
        }
    }
}

/// Обложка слева, текст справа (средний виджет для альбома и фильма).
struct PickSideBySideView: View {
    let item: Item
    let image: UIImage?
    let theme: String
    let isDone: Bool

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let image {
                    WidgetPhoto(image: image)
                } else {
                    PlaceholderArt(item: item, showsTitle: false)
                }
            }
            .frame(width: item.kind == .film ? 88 : 126, height: 126)
            .clipShape(RoundedRectangle(cornerRadius: item.kind == .film ? 10 : 6, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.kind.title.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(item.kind.color)
                    Spacer(minLength: 0)
                    if isDone {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(item.kind.color)
                    }
                }
                Text(item.title)
                    .font(.system(.headline, design: .serif))
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                Text(item.metaLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Text("Тема: \(theme)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(16)
    }
}

/// Типографская карточка статьи.
struct PickArticleView: View {
    let item: Item
    let theme: String
    let isDone: Bool
    let family: WidgetFamily

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: item.kind.symbol)
                Text(item.kind.title.uppercased())
                if let minutes = item.minutes {
                    Text("· \(Format.duration(minutes: minutes).uppercased())")
                }
                Spacer(minLength: 0)
                if isDone {
                    Image(systemName: "checkmark.circle.fill")
                }
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(item.kind.color)

            Text(item.title)
                .font(.system(family == .systemSmall ? .headline : .title3, design: .serif).weight(.semibold))
                .lineLimit(family == .systemSmall ? 4 : 3)
                .minimumScaleFactor(0.8)

            if family != .systemSmall {
                Text(item.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(family == .systemLarge ? 8 : 2)
            }

            Spacer(minLength: 0)

            Text(item.source ?? item.creator)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if family == .systemLarge {
                Text("Тема дня — «\(theme)»")
                    .font(.system(.caption, design: .serif))
                    .italic()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(family == .systemSmall ? 14 : 16)
    }
}
