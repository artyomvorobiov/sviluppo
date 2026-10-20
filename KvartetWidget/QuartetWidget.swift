import AppIntents
import SwiftUI
import UIKit
import WidgetKit

// MARK: - Данные

struct QuartetEntry: TimelineEntry {
    let date: Date
    let snapshot: DaySnapshot
    var thumbnails: [String: UIImage] = [:]
}

struct QuartetProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuartetEntry {
        QuartetEntry(date: Date(), snapshot: DaySnapshot.load(for: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (QuartetEntry) -> Void) {
        let family = context.family
        Task {
            let snapshot = DaySnapshot.load(for: Date())
            let thumbnails = await Self.thumbnails(for: snapshot, family: family, allowNetwork: false)
            completion(QuartetEntry(date: Date(), snapshot: snapshot, thumbnails: thumbnails))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuartetEntry>) -> Void) {
        let family = context.family
        Task {
            let now = Date()
            let midnight = Days.nextMidnight(after: now)
            let library = ContentLibrary.load()
            var entries: [QuartetEntry] = []
            for date in [now, midnight] {
                let snapshot = DaySnapshot.load(for: date, library: library)
                let thumbnails = await Self.thumbnails(for: snapshot, family: family, allowNetwork: true)
                entries.append(QuartetEntry(date: date, snapshot: snapshot, thumbnails: thumbnails))
            }
            // Сразу после полуночи — новый выпуск.
            completion(Timeline(entries: entries, policy: .after(midnight.addingTimeInterval(60))))
        }
    }

    /// Миниатюры нужны только большому виджету.
    private static func thumbnails(for snapshot: DaySnapshot, family: WidgetFamily, allowNetwork: Bool) async -> [String: UIImage] {
        guard family == .systemLarge else { return [:] }
        var result: [String: UIImage] = [:]
        for item in snapshot.items where item.kind != .article {
            let image: UIImage?
            if allowNetwork {
                image = await WidgetArtwork.image(for: item, maxPixel: 160)
            } else {
                image = await WidgetArtwork.cachedImage(for: item, maxPixel: 160)
            }
            if let image {
                result[item.id] = image
            }
        }
        return result
    }
}

// MARK: - Виджет

struct QuartetWidget: Widget {
    let kind = "QuartetWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuartetProvider()) { entry in
            QuartetWidgetView(entry: entry)
        }
        .configurationDisplayName("Квартет дня")
        .description("Тема дня и четыре рекомендации. Отмечайте изученное прямо на экране.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline
        ])
    }
}

struct QuartetWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QuartetEntry

    var body: some View {
        content
            .widgetBackground(for: family)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall:
            QuartetSmallView(snapshot: entry.snapshot)
        case .systemMedium:
            QuartetMediumView(snapshot: entry.snapshot)
        case .systemLarge:
            QuartetLargeView(snapshot: entry.snapshot, thumbnails: entry.thumbnails)
        case .accessoryCircular:
            QuartetCircularView(snapshot: entry.snapshot)
        case .accessoryRectangular:
            QuartetRectangularView(snapshot: entry.snapshot)
        case .accessoryInline:
            QuartetInlineView(snapshot: entry.snapshot)
        default:
            QuartetSmallView(snapshot: entry.snapshot)
        }
    }
}

// MARK: - Общие части

private let todayURL = URL(string: "\(AppConfig.urlScheme)://today")

/// Точки прогресса цветов типов.
struct ProgressDots: View {
    let snapshot: DaySnapshot
    var size: CGFloat = 9

    var body: some View {
        HStack(spacing: size * 0.55) {
            ForEach(snapshot.items) { item in
                Circle()
                    .fill(snapshot.isDone(item) ? item.kind.color : Color.clear)
                    .overlay(Circle().strokeBorder(item.kind.color, lineWidth: 1.2))
                    .frame(width: size, height: size)
            }
        }
    }
}

/// Кнопка-отметка (интерактивный виджет, iOS 17+).
struct DoneToggle: View {
    let item: Item
    let isDone: Bool
    var size: Font = .body

    var body: some View {
        Button(intent: ToggleDoneIntent(itemID: item.id)) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(size)
                .foregroundStyle(isDone ? item.kind.color : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isDone ? "Снять отметку" : item.kind.markActionTitle)
    }
}

// MARK: - Маленький

struct QuartetSmallView: View {
    let snapshot: DaySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Format.shortDay(snapshot.date).uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(snapshot.issue.theme)
                .font(.system(.title3, design: .serif).weight(.semibold))
                .lineLimit(3)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                ProgressDots(snapshot: snapshot)
                Spacer(minLength: 0)
                Text("\(snapshot.doneCount)/\(snapshot.items.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(todayURL)
    }
}

// MARK: - Средний

struct QuartetMediumView: View {
    let snapshot: DaySnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Format.shortDay(snapshot.date).uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(snapshot.issue.theme)
                    .font(.system(.headline, design: .serif))
                    .lineLimit(4)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                ProgressDots(snapshot: snapshot, size: 8)
            }
            .frame(width: 96, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(snapshot.items) { item in
                    HStack(spacing: 8) {
                        Link(destination: item.deepLink) {
                            HStack(spacing: 7) {
                                Image(systemName: item.kind.symbol)
                                    .font(.caption2)
                                    .foregroundStyle(item.kind.color)
                                    .frame(width: 14)
                                Text(item.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                    .foregroundStyle(snapshot.isDone(item) ? Color.secondary : Color.primary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        DoneToggle(item: item, isDone: snapshot.isDone(item))
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .widgetURL(todayURL)
    }
}

// MARK: - Большой

struct QuartetLargeView: View {
    let snapshot: DaySnapshot
    let thumbnails: [String: UIImage]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Format.weekdayDayMonth(snapshot.date).uppercased())
                Spacer()
                Text("\(snapshot.doneCount) из \(snapshot.items.count)")
                    .monospacedDigit()
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

            Text(snapshot.issue.theme)
                .font(.system(.title2, design: .serif).weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            Text(snapshot.issue.intro)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer(minLength: 4)

            VStack(spacing: 10) {
                ForEach(snapshot.items) { item in
                    HStack(spacing: 10) {
                        Link(destination: item.deepLink) {
                            HStack(spacing: 10) {
                                thumbnail(for: item)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.kind.title.uppercased())
                                        .font(.system(size: 9, weight: .bold))
                                        .tracking(0.8)
                                        .foregroundStyle(item.kind.color)
                                    Text(item.title)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    Text(item.creator)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        DoneToggle(item: item, isDone: snapshot.isDone(item), size: .title3)
                    }
                }
            }
        }
        .widgetURL(todayURL)
    }

    @ViewBuilder
    private func thumbnail(for item: Item) -> some View {
        Group {
            if let image = thumbnails[item.id] {
                WidgetPhoto(image: image)
            } else {
                ZStack {
                    item.kind.color.opacity(0.15)
                    Image(systemName: item.kind.symbol)
                        .font(.caption)
                        .foregroundStyle(item.kind.color)
                }
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

// MARK: - Экран блокировки

struct QuartetCircularView: View {
    let snapshot: DaySnapshot

    var body: some View {
        Gauge(value: Double(snapshot.doneCount), in: 0...Double(max(snapshot.items.count, 1))) {
            Image(systemName: "square.grid.2x2")
        } currentValueLabel: {
            Text("\(snapshot.doneCount)")
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetURL(todayURL)
    }
}

struct QuartetRectangularView: View {
    let snapshot: DaySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: "square.grid.2x2.fill")
                Text("\(AppConfig.appName) · \(snapshot.doneCount)/\(snapshot.items.count)")
            }
            .font(.caption2.weight(.semibold))
            .widgetAccentable()

            Text(snapshot.issue.theme)
                .font(.headline)
                .lineLimit(1)

            if let next = snapshot.nextItem {
                Text("\(next.kind.title): \(next.title)")
                    .font(.caption)
                    .lineLimit(1)
            } else {
                Text("Всё изучено — до завтра")
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(todayURL)
    }
}

struct QuartetInlineView: View {
    let snapshot: DaySnapshot

    var body: some View {
        Label("«\(snapshot.issue.theme)» · \(snapshot.doneCount)/\(snapshot.items.count)", systemImage: "square.grid.2x2")
            .widgetURL(todayURL)
    }
}
