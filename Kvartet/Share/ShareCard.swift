import SwiftUI
import UIKit

/// Карточка для сторис (1080×1920): изображение, название, автор и тема дня.
struct ShareCardView: View {
    let item: Item
    let image: UIImage?
    let theme: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(AppConfig.appName.uppercased())
                    .tracking(3)
                Spacer()
                Text(item.kind.title.uppercased())
                    .tracking(2)
                    .foregroundStyle(item.kind.color)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color(white: 0.35))

            Spacer(minLength: 20)

            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: item.kind == .painting ? 4 : 10, style: .continuous))
                        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                } else {
                    PlaceholderArt(item: item, showsTitle: true)
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 380)

            Spacer(minLength: 20)

            Text(item.title)
                .font(.system(size: 30, weight: .semibold, design: .serif))
                .foregroundStyle(Color(white: 0.1))
                .lineLimit(3)
                .minimumScaleFactor(0.6)
            Text(item.metaLine)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color(white: 0.35))
                .padding(.top, 6)

            if let theme {
                Rectangle()
                    .fill(Color(white: 0.85))
                    .frame(width: 40, height: 1)
                    .padding(.vertical, 16)
                Text("Тема дня — «\(theme)»")
                    .font(.system(size: 15, design: .serif))
                    .italic()
                    .foregroundStyle(Color(white: 0.3))
            }
        }
        .padding(28)
        .frame(width: 360, height: 640)
        .background(Color(red: 0.98, green: 0.973, blue: 0.957))
        .environment(\.colorScheme, .light)
    }
}

enum ShareCardRenderer {
    /// Рисует карточку и сохраняет PNG во временную папку (так её можно отправить в сторис или сохранить в Фото).
    @MainActor
    static func render(item: Item, theme: String?) async -> URL? {
        var image: UIImage?
        if item.kind != .article {
            image = await ArtworkLoader.image(for: item, maxPixel: 1200)
        }
        let renderer = ImageRenderer(content: ShareCardView(item: item, image: image, theme: theme))
        renderer.scale = 3
        guard let uiImage = renderer.uiImage, let data = uiImage.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kvartet-\(item.id).png")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
