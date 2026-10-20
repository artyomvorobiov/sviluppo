import SwiftUI

/// Вкладка «Архив»: все прошедшие выпуски и отложенные рекомендации.
struct ArchiveTab: View {
    enum Segment: Hashable {
        case days
        case saved
    }

    @Environment(AppModel.self) private var model
    @Environment(Preferences.self) private var prefs
    @State private var segment: Segment = .days

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.archivePath) {
            List {
                Picker("Раздел", selection: $segment) {
                    Text("Выпуски").tag(Segment.days)
                    Text("Отложенное").tag(Segment.saved)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))

                switch segment {
                case .days:
                    daysList
                case .saved:
                    savedList
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("Архив")
            .navigationDestination(for: Route.self) { route in
                RouteDestination(route: route)
            }
        }
    }

    // MARK: - Выпуски

    private struct MonthGroup: Identifiable {
        let title: String
        var days: [Date]
        var id: String { title }
    }

    private var monthGroups: [MonthGroup] {
        var groups: [MonthGroup] = []
        for day in model.archiveDays {
            let title = Format.monthYear(day)
            if groups.last?.title == title {
                groups[groups.count - 1].days.append(day)
            } else {
                groups.append(MonthGroup(title: title, days: [day]))
            }
        }
        return groups
    }

    @ViewBuilder
    private var daysList: some View {
        ForEach(monthGroups) { group in
            Section(group.title) {
                ForEach(group.days, id: \.self) { day in
                    NavigationLink(value: Route.day(Days.key(for: day))) {
                        DayRow(date: day)
                    }
                }
            }
        }
        if model.archiveDays.count <= 1 {
            Section {
                Text("Каждый день здесь будет появляться новый выпуск. Пропущенные дни никуда не денутся — их можно открыть в архиве.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Отложенное

    @ViewBuilder
    private var savedList: some View {
        let items = model.bookmarkedItems
        if items.isEmpty {
            Section {
                ContentUnavailableView(
                    "Ничего не отложено",
                    systemImage: "bookmark",
                    description: Text("Нажмите на закладку на экране рекомендации, чтобы вернуться к ней позже.")
                )
                .listRowBackground(Color.clear)
            }
        } else {
            Section {
                ForEach(items) { item in
                    NavigationLink(value: Route.item(item.id)) {
                        ItemRow(item: item)
                    }
                    .swipeActions {
                        Button("Убрать") {
                            model.toggleBookmark(item)
                        }
                        .tint(.gray)
                    }
                }
            }
        }
    }
}

/// Строка дня в архиве.
struct DayRow: View {
    let date: Date
    @Environment(AppModel.self) private var model
    @Environment(Preferences.self) private var prefs

    var body: some View {
        let issue = model.issue(for: date)
        let items = issue.items(for: prefs.enabledKinds)
        HStack(spacing: 14) {
            VStack(spacing: 0) {
                Text(date, format: .dateTime.day())
                    .font(Theme.serif(.title2))
                Text(Format.shortDay(date).components(separatedBy: ",").first ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 40)

            VStack(alignment: .leading, spacing: 6) {
                Text(issue.theme)
                    .font(Theme.serif(.headline))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    ForEach(items) { item in
                        Image(systemName: item.kind.symbol)
                            .font(.caption)
                            .foregroundStyle(model.isDone(item) ? item.kind.color : Color.secondary.opacity(0.5))
                    }
                    if Days.isSameDay(date, model.today) {
                        Text("сегодня")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Строка рекомендации (отложенное, дневник).
struct ItemRow: View {
    let item: Item
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(item: item, maxPixel: 200)
                .frame(width: 52, height: item.kind == .film ? 72 : 52)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                KindLabel(item: item)
                Text(item.title)
                    .font(Theme.serif(.headline))
                    .lineLimit(2)
                Text(item.metaLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let trailing {
                    trailing
                }
            }
        }
        .padding(.vertical, 2)
    }
}
