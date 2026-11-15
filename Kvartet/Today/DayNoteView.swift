import SwiftUI

/// Карточка рубрики «В этот день» на экране выпуска.
struct DayNoteCard: View {
    let note: DayNote

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if let item = note.artworkItem {
                ArtworkView(item: item, maxPixel: 300)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                    Text(note.label.uppercased())
                }
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                Text(note.title)
                    .font(Theme.serif(.headline))
                    .fixedSize(horizontal: false, vertical: true)
                Text(note.text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Полный текст рубрики «В этот день».
struct DayNoteSheet: View {
    let note: DayNote
    let date: Date

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var moreURL: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let item = note.artworkItem {
                        ArtworkView(item: item, maxPixel: 1400, contentMode: .fit)
                            .frame(height: 300)
                            .frame(maxWidth: .infinity)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(Format.dayMonth(date)) · \(note.label)".uppercased())
                            .font(.caption.weight(.semibold))
                            .tracking(1.2)
                            .foregroundStyle(.secondary)
                        Text(note.title)
                            .font(Theme.serif(.title))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                    }

                    Text(note.text)
                        .font(.body)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    if let tip = note.tip, !tip.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionTitle("Чем отметить")
                            Text(tip)
                                .font(.body)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    VStack(spacing: 10) {
                        if let linked = note.item.flatMap({ model.item(id: $0) }) {
                            Button {
                                dismiss()
                                model.handle(url: linked.deepLink)
                            } label: {
                                Label("\(linked.kind.title): \(linked.title)", systemImage: linked.kind.symbol)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.ink)
                            .foregroundStyle(Theme.paper)
                        }
                        if let moreURL {
                            Button {
                                openURL(moreURL)
                            } label: {
                                Label("Подробнее в Википедии", systemImage: "book")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .controlSize(.large)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("В этот день")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: shareText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .task {
                guard let item = note.artworkItem, item.wiki != nil else { return }
                moreURL = await MediaResolver.shared.readMoreURL(for: item)
            }
        }
    }

    private var shareText: String {
        var lines = ["\(Format.dayMonth(date)) — \(note.label.lowercased()). \(note.title)", "", note.text]
        if let tip = note.tip, !tip.isEmpty {
            lines.append("")
            lines.append(tip)
        }
        lines.append("")
        lines.append("Из приложения «\(AppConfig.appName)»")
        return lines.joined(separator: "\n")
    }
}
