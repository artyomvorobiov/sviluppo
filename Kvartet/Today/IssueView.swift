import SwiftUI

/// Выпуск дня: дата, тема, вступление и четыре карточки.
/// Используется и на вкладке «Сегодня», и в архиве.
struct IssueView: View {
    let date: Date
    let isToday: Bool

    @Environment(AppModel.self) private var model
    @Environment(Preferences.self) private var prefs

    var body: some View {
        let issue = model.issue(for: date)
        let items = issue.items(for: prefs.enabledKinds)
        let doneCount = items.filter { model.isDone($0) }.count

        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                IssueHeader(
                    issue: issue,
                    date: date,
                    number: model.issueNumber(for: date),
                    items: items,
                    doneCount: doneCount,
                    streak: isToday ? model.currentStreak : 0
                )

                ForEach(items) { item in
                    NavigationLink(value: Route.item(item.id)) {
                        ItemCard(item: item)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        ItemContextMenu(item: item)
                    }
                }

                if isToday {
                    IssueFooter(allDone: !items.isEmpty && doneCount == items.count)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle(isToday ? "" : Format.dayMonth(date))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isToday {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.isSettingsPresented = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Настройки")
                }
            }
        }
        .sheet(isPresented: settingsBinding) {
            SettingsView()
                .environment(model)
                .environment(prefs)
        }
        .sensoryFeedback(.success, trigger: doneCount) { old, new in new > old }
    }

    /// Настройки открываются только с экрана «Сегодня».
    private var settingsBinding: Binding<Bool> {
        Binding(
            get: { isToday && model.isSettingsPresented },
            set: { model.isSettingsPresented = $0 }
        )
    }
}

/// Шапка выпуска.
struct IssueHeader: View {
    let issue: Issue
    let date: Date
    let number: Int
    let items: [Item]
    let doneCount: Int
    let streak: Int

    @Environment(AppModel.self) private var model
    @ScaledMetric(relativeTo: .largeTitle) private var themeSize: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(Format.weekdayDayMonth(date).uppercased())
                Text("·")
                Text("№ \(number)")
            }
            .font(.caption.weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(.secondary)

            Text(issue.theme)
                .font(.system(size: themeSize, weight: .semibold, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(issue.intro)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ForEach(items) { item in
                    Circle()
                        .fill(model.isDone(item) ? item.kind.color : Color.clear)
                        .overlay(Circle().strokeBorder(item.kind.color, lineWidth: 1.5))
                        .frame(width: 10, height: 10)
                }
                Text("\(doneCount) из \(items.count)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                if streak > 1 {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Label("\(Format.count(streak, "день", "дня", "дней")) подряд", systemImage: "flame")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
            .accessibilityElement(children: .combine)
        }
    }
}

/// Подпись внизу выпуска.
struct IssueFooter: View {
    let allDone: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: allDone ? "checkmark.seal" : "moon.stars")
                .font(.title3)
            Text(allDone ? "Квартет собран. До завтра!" : "Завтра — новая тема.")
                .font(Theme.serif(.callout, weight: .regular))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

/// Меню по долгому нажатию на карточку.
struct ItemContextMenu: View {
    let item: Item
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.toggleDone(item)
        } label: {
            if model.isDone(item) {
                Label("Снять отметку", systemImage: "xmark.circle")
            } else {
                Label(item.kind.markActionTitle, systemImage: "checkmark.circle")
            }
        }
        Button {
            model.toggleBookmark(item)
        } label: {
            if model.isBookmarked(item) {
                Label("Убрать из отложенного", systemImage: "bookmark.slash")
            } else {
                Label("Отложить", systemImage: "bookmark")
            }
        }
    }
}
