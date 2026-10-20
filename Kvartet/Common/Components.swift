import SafariServices
import SwiftUI
import UIKit

// MARK: - Изображения

/// Обложка, постер или картина: ищет ссылку, загружает, показывает заглушку пока нет.
/// Заполняет предложенный размер, лишнее обрезается — задавайте размер через `.frame`.
struct ArtworkView: View {
    let item: Item
    var maxPixel: CGFloat = 1000
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .transition(.opacity)
                } else {
                    PlaceholderArt(item: item, showsTitle: didFail)
                }
            }
            .clipped()
            .task(id: item.id) { await load() }
            .accessibilityElement()
            .accessibilityLabel(Text("\(item.kind.title): \(item.title)"))
    }

    private func load() async {
        if let url = await MediaResolver.shared.cachedArtworkURL(for: item),
           let cached = ImageStore.shared.memoryImage(for: url, maxPixel: maxPixel) {
            image = cached
            return
        }
        guard let url = await MediaResolver.shared.artworkURL(for: item),
              let loaded = await ImageStore.shared.image(for: url, maxPixel: maxPixel)
        else {
            didFail = true
            return
        }
        withAnimation(.easeOut(duration: 0.25)) {
            image = loaded
        }
    }
}

/// Загружает изображение рекомендации (для героя, зума, карточки «поделиться»).
enum ArtworkLoader {
    static func image(for item: Item, maxPixel: CGFloat) async -> UIImage? {
        guard let url = await MediaResolver.shared.artworkURL(for: item) else { return nil }
        return await ImageStore.shared.image(for: url, maxPixel: maxPixel)
    }
}

// MARK: - Подписи

/// «КАРТИНА · 3 МИН»
struct KindLabel: View {
    let item: Item

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: item.kind.symbol)
            Text(text)
        }
        .font(.caption2.weight(.bold))
        .tracking(1)
        .foregroundStyle(item.kind.color)
        .accessibilityElement(children: .combine)
    }

    private var text: String {
        var parts = [item.kind.title.uppercased()]
        if let minutes = item.minutes {
            parts.append(Format.duration(minutes: minutes).uppercased())
        }
        return parts.joined(separator: " · ")
    }
}

/// Подпись карточки: тип, название, автор и значки «готово»/«отложено».
struct CardCaption: View {
    let item: Item
    let isDone: Bool
    let isSaved: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                KindLabel(item: item)
                Spacer(minLength: 4)
                if isSaved && !isDone {
                    Image(systemName: "bookmark.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Отложено")
                }
                if isDone {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(item.kind.color)
                        .accessibilityLabel(item.kind.doneTitle)
                }
            }
            Text(item.title)
                .font(Theme.serif(.title3))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(item.metaLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Пять звёзд (только просмотр).
struct StarsView: View {
    let rating: Int
    var color: Color = .primary

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { index in
                Image(systemName: index <= rating ? "star.fill" : "star")
            }
        }
        .font(.caption)
        .foregroundStyle(color)
        .accessibilityElement()
        .accessibilityLabel("Оценка \(rating) из 5")
    }
}

// MARK: - Кнопки

/// Главная кнопка: «чернильная» плашка во всю ширину.
struct FilledButtonStyle: ButtonStyle {
    var background: Color = Theme.ink
    var foreground: Color = Theme.paper

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .padding(.horizontal, 12)
            .foregroundStyle(foreground)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(background))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Второстепенная кнопка: тонкая рамка.
struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        OutlineLabel { configuration.label }
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}

/// Оформление «рамки» — отдельно, чтобы им же оформлять подпись `Menu`.
struct OutlineLabel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .padding(.horizontal, 10)
            .foregroundStyle(.primary)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Круглая кнопка закрытия для полноэкранных режимов.
struct CloseButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(.black.opacity(0.45)))
        }
        .accessibilityLabel("Закрыть")
    }
}

// MARK: - Тексты

/// Раздел с заголовком и текстом.
struct DetailSection: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title)
            Text(text)
                .font(.body)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Раздел-список.
struct BulletSection: View {
    let title: String
    let items: [String]
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title)
            ForEach(Array(items.enumerated()), id: \.offset) { _, text in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle()
                        .fill(color)
                        .frame(width: 5, height: 5)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 1 }
                    Text(text)
                        .font(.body)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct SectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(.secondary)
    }
}

// MARK: - UIKit-обёртки

/// Встроенный Safari (поддерживает только http/https).
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        configuration.barCollapsingEnabled = true
        return SFSafariViewController(url: url, configuration: configuration)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}

    static func canOpen(_ url: URL) -> Bool {
        url.scheme == "http" || url.scheme == "https"
    }
}
