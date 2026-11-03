import SwiftUI
import UIKit
import WidgetKit

/// Содержимое виджета «Рекомендация дня». Общее для виджета и экрана предпросмотра в приложении
/// (отладочная сборка), поэтому размеры приходят снаружи, а не из окружения WidgetKit.
struct PickWidgetContent: View {
    let content: PickContent
    let family: WidgetFamily

    var body: some View {
        switch content.layout.style {
        case .text:
            PickArticleView(item: content.item, theme: content.theme, isDone: content.isDone, family: family)
        case .fullBleed:
            PickFullBleedView(content: content, family: family)
        case .sideBySide:
            PickSideBySideView(content: content)
        case .framed:
            PickFramedView(content: content)
        case .poster:
            if family == .systemSmall {
                PickPosterSmallView(content: content)
            } else {
                PickPosterLargeView(content: content)
            }
        }
    }
}

// MARK: - Общие детали

/// Картинка в рамке точного размера (картинка уже подогнана под неё) или заглушка.
struct PickArtwork: View {
    let item: Item
    let image: UIImage?
    let size: CGSize
    var cornerRadius: CGFloat = 0

    var body: some View {
        Group {
            if let image {
                WidgetPhoto(image: image)
            } else {
                PlaceholderArt(item: item, showsTitle: false)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Цветная подпись типа: «ФИЛЬМ», «КАРТИНА».
struct PickKindLabel: View {
    let item: Item
    var color: Color?

    var body: some View {
        Text(item.kind.title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(1)
            .foregroundStyle(color ?? item.kind.color)
            .lineLimit(1)
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

// MARK: - Варианты оформления

/// Изображение на весь виджет и подпись поверх.
struct PickFullBleedView: View {
    let content: PickContent
    let family: WidgetFamily

    var body: some View {
        let item = content.item
        // Color.clear занимает ровно размер виджета; картинка лежит поверх и обрезается по нему,
        // поэтому никогда не раздувает вёрстку.
        Color.clear
            .overlay {
                if let image = content.image {
                    WidgetPhoto(image: image)
                } else {
                    PlaceholderArt(item: item, showsTitle: false)
                }
            }
            .clipped()
            .overlay {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.15), .black.opacity(0.72)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    PickKindLabel(item: item, color: Color.white.opacity(0.85))
                    Text(item.title)
                        .font(.system(family == .systemSmall ? .subheadline : .headline, design: .serif).weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text(item.creator)
                        .font(.caption2)
                        .lineLimit(1)
                        .opacity(0.85)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 4)
                .padding(PickLayout.padding(for: family))
            }
            .overlay(alignment: .topTrailing) {
                if content.isDone {
                    DoneBadge().padding(10)
                }
            }
    }
}

/// Изображение слева, текст справа (средний виджет).
struct PickSideBySideView: View {
    let content: PickContent

    var body: some View {
        let item = content.item
        HStack(spacing: 14) {
            if let size = content.layout.imageSize {
                PickArtwork(item: item, image: content.image, size: size, cornerRadius: cornerRadius(for: item.kind))
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    PickKindLabel(item: item)
                    Spacer(minLength: 0)
                    if content.isDone {
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
                Text("Тема: \(content.theme)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(PickLayout.padding(for: .systemMedium))
    }

    private func cornerRadius(for kind: ItemKind) -> CGFloat {
        switch kind {
        case .film: 8
        case .album: 6
        case .painting, .article: 3
        }
    }
}

/// Картина целиком на светлом поле, подпись под ней — как этикетка в музее (большой виджет).
struct PickFramedView: View {
    let content: PickContent

    var body: some View {
        let item = content.item
        VStack(spacing: 12) {
            if let size = content.layout.imageSize {
                PickArtwork(item: item, image: content.image, size: size, cornerRadius: 3)
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    PickKindLabel(item: item)
                    Spacer(minLength: 0)
                    if content.isDone {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(item.kind.color)
                    }
                }
                Text(item.title)
                    .font(.system(.headline, design: .serif))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(item.metaLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: PickLayout.framedCaptionHeight, alignment: .bottomLeading)
        }
        .padding(PickLayout.padding(for: .systemLarge))
    }
}

/// Маленький виджет фильма: постер целиком, год и длительность, название под ними.
struct PickPosterSmallView: View {
    let content: PickContent

    var body: some View {
        let item = content.item
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                if let size = content.layout.imageSize {
                    PickArtwork(item: item, image: content.image, size: size, cornerRadius: 6)
                }
                VStack(alignment: .leading, spacing: 3) {
                    PickKindLabel(item: item)
                    if let year = item.year {
                        Text(year)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let minutes = item.minutes {
                        Text(Format.duration(minutes: minutes))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                    if content.isDone {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(item.kind.color)
                    }
                }
                .frame(height: content.layout.imageSize?.height, alignment: .topLeading)
            }
            Spacer(minLength: 0)
            Text(item.title)
                .font(.system(.subheadline, design: .serif).weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(PickLayout.padding(for: .systemSmall))
    }
}

/// Большой виджет фильма: постер, название, режиссёр, о чём фильм.
struct PickPosterLargeView: View {
    let content: PickContent

    var body: some View {
        let item = content.item
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                if let size = content.layout.imageSize {
                    PickArtwork(item: item, image: content.image, size: size, cornerRadius: 8)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        PickKindLabel(item: item)
                        Spacer(minLength: 0)
                        if content.isDone {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(item.kind.color)
                        }
                    }
                    Text(item.title)
                        .font(.system(.title3, design: .serif).weight(.semibold))
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                    if let original = item.originalTitle, original != item.title {
                        Text(original)
                            .font(.system(.footnote, design: .serif))
                            .italic()
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Text(item.metaLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if let details = item.details, !details.isEmpty {
                        Text(details.prefix(2).joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    if let minutes = item.minutes {
                        Label(Format.duration(minutes: minutes), systemImage: "clock")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(height: content.layout.imageSize?.height, alignment: .topLeading)
            }
            Text(item.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
            Spacer(minLength: 0)
            Text("Тема дня — «\(content.theme)»")
                .font(.system(.caption, design: .serif))
                .italic()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(PickLayout.padding(for: .systemLarge))
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
