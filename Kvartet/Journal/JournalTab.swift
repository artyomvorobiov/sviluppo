import SwiftUI

/// Вкладка «Дневник»: всё изученное, оценки, заметки и статистика.
struct JournalTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.journalPath) {
            List {
                Section {
                    JournalStats()
                        .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                }

                let entries = model.journalEntries
                if entries.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "Дневник пока пуст",
                            systemImage: "book.closed",
                            description: Text("Отмечайте изученное — сюда попадут оценки и заметки, а с ними и ваша личная история открытий.")
                        )
                        .listRowBackground(Color.clear)
                    }
                } else {
                    ForEach(groups(entries)) { group in
                        Section(group.title) {
                            ForEach(group.entries) { entry in
                                NavigationLink(value: Route.item(entry.item.id)) {
                                    JournalRow(entry: entry)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("Дневник")
            .toolbar {
                if !model.journalEntries.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(
                            item: model.journalMarkdown(),
                            subject: Text("Дневник «\(AppConfig.appName)»"),
                            preview: SharePreview("Дневник «\(AppConfig.appName)»")
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Экспорт дневника")
                    }
                }
            }
            .navigationDestination(for: Route.self) { route in
                RouteDestination(route: route)
            }
        }
    }

    private struct MonthGroup: Identifiable {
        let title: String
        var entries: [JournalEntry]
        var id: String { title }
    }

    private func groups(_ entries: [JournalEntry]) -> [MonthGroup] {
        var result: [MonthGroup] = []
        for entry in entries {
            let title = Format.monthYear(entry.completion.date)
            if result.last?.title == title {
                result[result.count - 1].entries.append(entry)
            } else {
                result.append(MonthGroup(title: title, entries: [entry]))
            }
        }
        return result
    }
}

/// Счётчики по типам и серии.
struct JournalStats: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.currentStreak)")
                        .font(.system(size: 44, weight: .semibold, design: .serif))
                        .monospacedDigit()
                    Text("\(Format.plural(model.currentStreak, "день", "дня", "дней")) подряд")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(model.bestStreak)")
                        .font(Theme.serif(.title2))
                        .monospacedDigit()
                    Text("рекорд")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    stat(.painting)
                    stat(.article)
                }
                GridRow {
                    stat(.album)
                    stat(.film)
                }
            }
        }
    }

    private func stat(_ kind: ItemKind) -> some View {
        HStack(spacing: 8) {
            Image(systemName: kind.symbol)
                .foregroundStyle(kind.color)
                .frame(width: 22)
            Text(kind.counted(model.completedCount(of: kind)))
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Строка дневника: рекомендация, оценка и начало заметки.
struct JournalRow: View {
    let entry: JournalEntry

    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(item: entry.item, maxPixel: 200)
                .frame(width: 52, height: entry.item.kind == .film ? 72 : 52)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.item.title)
                    .font(Theme.serif(.headline))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(Format.dayMonth(entry.completion.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let rating = entry.completion.rating {
                        StarsView(rating: rating, color: entry.item.kind.color)
                    }
                }
                if let note = entry.completion.note {
                    Text(note)
                        .font(.footnote)
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
