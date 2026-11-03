import SwiftUI
import UIKit
import WidgetKit

/// Как разместить рекомендацию в виджете «Рекомендация дня».
///
/// Оформление выбирается по типу, размеру виджета и пропорциям картинки, а сама картинка
/// заранее обрезается и уменьшается ровно под свою рамку. Это важно по двум причинам:
/// WidgetKit не показывает виджет, если изображение по площади больше него, а растянутая
/// `scaledToFill` картинка раздувает вёрстку — подписи уезжают за край.
struct PickLayout: Equatable {
    enum Style: Equatable {
        /// Изображение на весь виджет, подпись поверх.
        case fullBleed
        /// Изображение слева, текст справа.
        case sideBySide
        /// Картина целиком на светлом поле, подпись под ней.
        case framed
        /// Постер и подробности о фильме.
        case poster
        /// Типографская карточка статьи.
        case text
    }

    let style: Style
    /// Рамка изображения в точках; nil — изображение не нужно.
    let imageSize: CGSize?

    /// Пропорции по умолчанию, пока картинка не загружена.
    static func defaultAspect(for kind: ItemKind) -> CGFloat {
        switch kind {
        case .painting: CGFloat(4.0 / 3.0)
        case .film: CGFloat(2.0 / 3.0)
        case .album, .article: CGFloat(1)
        }
    }

    static func padding(for family: WidgetFamily) -> CGFloat {
        family == .systemSmall ? 12 : 16
    }

    /// Высота подписи под картиной в «рамке».
    static let framedCaptionHeight: CGFloat = 58

    init(kind: ItemKind, family: WidgetFamily, size: CGSize, imageAspect: CGFloat?) {
        let aspect = max(0.2, min(5, imageAspect ?? Self.defaultAspect(for: kind)))
        let padding = Self.padding(for: family)
        let inner = CGSize(width: max(1, size.width - padding * 2), height: max(1, size.height - padding * 2))

        switch (kind, family) {
        case (.article, _):
            self.init(style: .text, imageSize: nil)

        case (.album, .systemMedium):
            self.init(style: .sideBySide, imageSize: CGSize(width: inner.height, height: inner.height))
        case (.album, _):
            self.init(style: .fullBleed, imageSize: size)

        case (.film, .systemMedium):
            self.init(style: .sideBySide, imageSize: CGSize(width: (inner.height * 2 / 3).rounded(), height: inner.height))
        case (.film, .systemSmall):
            let height = (size.height * 0.52).rounded()
            self.init(style: .poster, imageSize: CGSize(width: (height * 2 / 3).rounded(), height: height))
        case (.film, _):
            let width = (inner.width * 0.38).rounded()
            self.init(style: .poster, imageSize: CGSize(width: width, height: (width * 1.5).rounded()))

        case (.painting, .systemMedium):
            // Широкая картина хорошо смотрится на весь виджет, остальные — целиком рядом с подписью.
            if aspect >= 1.5 {
                self.init(style: .fullBleed, imageSize: size)
            } else {
                var height = inner.height
                var width = height * aspect
                let maxWidth = inner.width * 0.5
                if width > maxWidth {
                    width = maxWidth
                    height = width / aspect
                }
                self.init(style: .sideBySide, imageSize: CGSize(width: width.rounded(), height: height.rounded()))
            }
        case (.painting, .systemLarge), (.painting, .systemExtraLarge):
            // Если при обрезке под виджет теряется заметная часть картины — показываем её целиком.
            let widgetAspect = size.width / max(size.height, 1)
            let kept = min(aspect, widgetAspect) / max(aspect, widgetAspect)
            if kept >= 0.78 {
                self.init(style: .fullBleed, imageSize: size)
            } else {
                let box = CGSize(width: inner.width, height: max(1, inner.height - Self.framedCaptionHeight - 12))
                let fitted = aspect > box.width / box.height
                    ? CGSize(width: box.width, height: box.width / aspect)
                    : CGSize(width: box.height * aspect, height: box.height)
                self.init(style: .framed, imageSize: CGSize(width: fitted.width.rounded(), height: fitted.height.rounded()))
            }
        case (.painting, _):
            self.init(style: .fullBleed, imageSize: size)
        }
    }

    private init(style: Style, imageSize: CGSize?) {
        self.style = style
        self.imageSize = imageSize
    }
}

/// Всё, что нужно нарисовать в виджете «Рекомендация дня».
struct PickContent {
    let item: Item
    let theme: String
    let isDone: Bool
    let layout: PickLayout
    /// Картинка, уже подогнанная под `layout.imageSize`.
    var image: UIImage?

    /// Готовит содержимое: узнаёт пропорции картинки, выбирает оформление и подгоняет картинку под рамку.
    static func load(
        item: Item,
        theme: String,
        isDone: Bool,
        family: WidgetFamily,
        size: CGSize,
        scale: CGFloat,
        allowNetwork: Bool
    ) async -> PickContent {
        guard item.kind != .article,
              let data = await WidgetArtwork.data(for: item, allowNetwork: allowNetwork),
              let pixels = ImageStore.pixelSize(of: data)
        else {
            let layout = PickLayout(kind: item.kind, family: family, size: size, imageAspect: nil)
            return PickContent(item: item, theme: theme, isDone: isDone, layout: layout, image: nil)
        }
        let layout = PickLayout(kind: item.kind, family: family, size: size, imageAspect: pixels.width / pixels.height)
        let image = layout.imageSize.flatMap { ImageStore.render(data, filling: $0, scale: scale) }
        return PickContent(item: item, theme: theme, isDone: isDone, layout: layout, image: image)
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

    /// Исходные байты картинки (для точной подгонки под рамку виджета).
    static func data(for item: Item, allowNetwork: Bool) async -> Data? {
        if let url = await MediaResolver.shared.cachedArtworkURL(for: item),
           let data = await ImageStore.shared.imageData(for: url, allowNetwork: allowNetwork) {
            return data
        }
        guard allowNetwork, let url = await MediaResolver.shared.artworkURL(for: item) else { return nil }
        return await ImageStore.shared.imageData(for: url, allowNetwork: true)
    }
}

/// Плотность пикселей экрана для подготовки картинок виджета.
enum WidgetScale {
    static var current: CGFloat {
        min(3, max(1, UIScreen.main.scale))
    }
}
