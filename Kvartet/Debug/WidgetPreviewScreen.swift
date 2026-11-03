import SwiftUI
import UIKit
import WidgetKit

/// Отладочный предпросмотр виджета «Рекомендация дня» во всех размерах — тот же код, что и в самом виджете,
/// поэтому вёрстку можно проверить скриншотом из симулятора. Открывается ссылкой
/// kvartet://debug/widgets?item=<id> и только в отладочной сборке.
struct WidgetPreviewModifier: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        #if DEBUG
        content.fullScreenCover(isPresented: isPresented) {
            if let id = model.debugWidgetItemID, let item = model.item(id: id) {
                WidgetPreviewScreen(
                    item: item,
                    theme: model.issue(containing: item)?.theme ?? "",
                    isDone: model.isDone(item),
                    onClose: { model.debugWidgetItemID = nil }
                )
            }
        }
        #else
        content
        #endif
    }

    #if DEBUG
    private var isPresented: Binding<Bool> {
        Binding(
            get: { model.debugWidgetItemID != nil },
            set: { if !$0 { model.debugWidgetItemID = nil } }
        )
    }
    #endif
}

#if DEBUG
struct WidgetPreviewScreen: View {
    let item: Item
    let theme: String
    let isDone: Bool
    let onClose: () -> Void

    @State private var contents: [WidgetFamily: PickContent] = [:]

    private let families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]

    var body: some View {
        let sizes = Self.sizes(forScreenWidth: UIScreen.main.bounds.width)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    widget(.systemSmall, size: sizes[.systemSmall]!)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.headline)
                        ForEach(families, id: \.self) { family in
                            if let layout = contents[family]?.layout {
                                Text("\(Self.name(family)): \(String(describing: layout.style))")
                                    .font(.caption.monospaced())
                            }
                        }
                    }
                    .foregroundStyle(.white)
                    Spacer(minLength: 0)
                }
                widget(.systemMedium, size: sizes[.systemMedium]!)
                widget(.systemLarge, size: sizes[.systemLarge]!)
            }
            .padding(.horizontal, (UIScreen.main.bounds.width - sizes[.systemMedium]!.width) / 2)
            .padding(.vertical, 12)
        }
        .background(
            LinearGradient(colors: [Color(white: 0.30), Color(red: 0.12, green: 0.15, blue: 0.22)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .overlay(alignment: .topTrailing) {
            Button("Закрыть", action: onClose)
                .buttonStyle(.borderedProminent)
                .padding()
        }
        .task {
            for family in families {
                guard let size = sizes[family] else { continue }
                contents[family] = await PickContent.load(
                    item: item,
                    theme: theme,
                    isDone: isDone,
                    family: family,
                    size: size,
                    scale: WidgetScale.current,
                    allowNetwork: true
                )
            }
        }
    }

    private func widget(_ family: WidgetFamily, size: CGSize) -> some View {
        Group {
            if let content = contents[family] {
                PickWidgetContent(content: content, family: family)
            } else {
                ProgressView()
            }
        }
        .frame(width: size.width, height: size.height)
        .background(Theme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private static func name(_ family: WidgetFamily) -> String {
        switch family {
        case .systemSmall: "small"
        case .systemMedium: "medium"
        case .systemLarge: "large"
        default: "other"
        }
    }

    /// Размеры виджетов на экране «Домой» для ширины экрана iPhone (в точках).
    static func sizes(forScreenWidth width: CGFloat) -> [WidgetFamily: CGSize] {
        let metrics: (small: CGFloat, wide: CGFloat, large: CGFloat)
        if width >= 428 {
            metrics = (170, 364, 382)
        } else if width >= 414 {
            metrics = (169, 360, 379)
        } else if width >= 390 {
            metrics = (158, 338, 354)
        } else {
            metrics = (155, 329, 345)
        }
        let (small, wide, large) = metrics
        return [
            .systemSmall: CGSize(width: small, height: small),
            .systemMedium: CGSize(width: wide, height: small),
            .systemLarge: CGSize(width: wide, height: large)
        ]
    }
}
#endif
