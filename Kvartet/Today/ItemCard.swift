import SwiftUI

/// Карточка рекомендации в выпуске. У каждого типа своя раскладка:
/// картина — большая, фильм и альбом — с обложкой слева, статья — типографская.
struct ItemCard: View {
    let item: Item
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch item.kind {
            case .painting:
                paintingCard
            case .article:
                articleCard
            case .album, .film:
                mediaCard
            }
        }
        .contentShape(Rectangle())
    }

    private var caption: CardCaption {
        CardCaption(item: item, isDone: model.isDone(item), isSaved: model.isBookmarked(item))
    }

    private var paintingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            ArtworkView(item: item, maxPixel: 1400)
                .frame(height: 260)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            caption
        }
    }

    private var mediaCard: some View {
        let isFilm = item.kind == .film
        return HStack(alignment: .top, spacing: 16) {
            ArtworkView(item: item, maxPixel: 600)
                .frame(width: isFilm ? 96 : 124, height: isFilm ? 144 : 124)
                .clipShape(RoundedRectangle(cornerRadius: isFilm ? 10 : 6, style: .continuous))
                .shadow(color: .black.opacity(0.14), radius: 10, y: 5)
            caption
            Spacer(minLength: 0)
        }
    }

    private var articleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            caption
            Text(item.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(alignment: .leading) {
            Capsule()
                .fill(item.kind.color)
                .frame(width: 3)
                .padding(.vertical, 18)
        }
    }
}
