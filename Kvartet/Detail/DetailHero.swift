import SwiftUI
import UIKit

/// Большое изображение вверху экрана рекомендации.
struct DetailHero: View {
    let item: Item
    var onZoom: () -> Void

    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        Group {
            switch item.kind {
            case .painting:
                painting
            case .album:
                cover(width: 260, aspect: 1, cornerRadius: 8)
            case .film:
                cover(width: 210, aspect: 2.0 / 3.0, cornerRadius: 12)
            case .article:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, item.kind == .article ? 0 : 8)
        .task(id: item.id) { await load() }
    }

    @ViewBuilder
    private var painting: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 480)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
                .onTapGesture(perform: onZoom)
                .accessibilityLabel(Text("Картина «\(item.title)». Нажмите, чтобы увеличить"))
                .accessibilityAddTraits(.isButton)
        } else {
            PlaceholderArt(item: item, showsTitle: didFail)
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    if !didFail { ProgressView().tint(.white) }
                }
        }
    }

    private func cover(width: CGFloat, aspect: CGFloat, cornerRadius: CGFloat) -> some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                PlaceholderArt(item: item, showsTitle: true)
            }
        }
        .frame(width: width, height: width / aspect)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 18, y: 10)
        .accessibilityElement()
        .accessibilityLabel(Text("\(item.kind.title) «\(item.title)»"))
    }

    private func load() async {
        guard item.kind != .article else { return }
        let maxPixel: CGFloat = item.kind == .painting ? 1800 : 900
        if let loaded = await ArtworkLoader.image(for: item, maxPixel: maxPixel) {
            withAnimation(.easeOut(duration: 0.25)) { image = loaded }
        } else {
            didFail = true
        }
    }
}

/// Полноэкранный просмотр с увеличением.
struct ZoomViewer: View {
    let item: Item
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let image {
                ZoomableImage(image: image)
                    .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            CloseButton { dismiss() }
                .padding()
        }
        .statusBarHidden()
        .task { image = await ArtworkLoader.image(for: item, maxPixel: 3000) }
    }
}
