import SwiftUI
import UIKit

/// Цвета и шрифты «Квартета»: тёплая бумага, чёрные чернила, по одному акценту на тип.
enum Theme {
    /// Фон экранов.
    static let paper = Color(light: 0xFAF8F4, dark: 0x111113)
    /// Фон карточек.
    static let card = Color(light: 0xFFFFFF, dark: 0x1C1C1F)
    /// Основной цвет «чернил» (кнопки, акценты интерфейса).
    static let ink = Color(light: 0x1C1B1A, dark: 0xF2EFEA)
    /// Тонкие линии.
    static let hairline = Color(light: 0xE6E1D8, dark: 0x2C2C30)
    /// Цвет интерфейса (вкладки, ссылки).
    static let accent = Color(light: 0x1C1B1A, dark: 0xF2EFEA)

    static func serif(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .serif).weight(weight)
    }
}

extension ItemKind {
    /// Акцентный цвет типа.
    var color: Color {
        switch self {
        case .painting: Color(light: 0xA8741A, dark: 0xE3B35A)
        case .article: Color(light: 0x2F7A5A, dark: 0x6CC79A)
        case .album: Color(light: 0x3B5BA9, dark: 0x8FA8F0)
        case .film: Color(light: 0xB23B32, dark: 0xEE7B70)
        }
    }

    /// Базовый оттенок для заглушек.
    fileprivate var hue: Double {
        switch self {
        case .painting: 0.10
        case .article: 0.43
        case .album: 0.62
        case .film: 0.01
        }
    }
}

extension Item {
    /// Два цвета градиента для заглушки — у каждой рекомендации свои, но в тоне её типа.
    var placeholderColors: [Color] {
        let shift = (stableSeed - 0.5) * 0.12
        let hue = (kind.hue + shift + 1).truncatingRemainder(dividingBy: 1)
        return [
            Color(hue: hue, saturation: 0.50, brightness: 0.62),
            Color(hue: (hue + 0.04).truncatingRemainder(dividingBy: 1), saturation: 0.62, brightness: 0.34)
        ]
    }
}

extension Color {
    /// Цвет, меняющийся вместе со светлой/тёмной темой.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// Типографская заглушка, пока изображение грузится или если его нет.
struct PlaceholderArt: View {
    let item: Item
    var showsTitle: Bool = true

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: item.placeholderColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: item.kind.symbol)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
            if showsTitle {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(.headline, design: .serif))
                        .lineLimit(4)
                        .minimumScaleFactor(0.6)
                    Text(item.creator)
                        .font(.caption)
                        .lineLimit(2)
                        .opacity(0.85)
                }
                .foregroundStyle(.white)
                .padding(12)
            }
        }
    }
}
