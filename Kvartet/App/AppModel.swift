import Observation
import SwiftUI
import WidgetKit

/// Запись дневника: что изучено и как понравилось.
struct JournalEntry: Identifiable, Hashable {
    let item: Item
    let completion: Completion
    var id: String { item.id }
}

/// Состояние приложения: каталог, отметки, навигация.
@MainActor
@Observable
final class AppModel {
    private(set) var library: ContentLibrary
    private(set) var state: UserState
    /// «Сегодня» — обновляется при возвращении в приложение и в полночь.
    private(set) var today: Date

    var selectedTab: AppTab = .today
    var todayPath: [Route] = []
    var archivePath: [Route] = []
    var journalPath: [Route] = []
    /// Что сразу открыть на экране рекомендации после перехода по ссылке
    /// (kvartet://item/<id>?open=reader|look|zoom).
    var pendingOpen: PendingOpen?
    var isSettingsPresented = false

    private let store = UserStateStore.shared
    @ObservationIgnored private var lastRemoteCheck: Date?

    init() {
        library = ContentLibrary.load()
        today = Date()
        state = UserStateStore.shared.ensureStartDay()
        #if DEBUG
        // Для автоматических скриншотов: запуск с аргументами -openURL kvartet://…
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-openURL"), index + 1 < arguments.count,
           let url = URL(string: arguments[index + 1]) {
            handle(url: url)
        }
        #endif
    }

    // MARK: - Дни и выпуски

    var startDay: Date { DayPlanner.startDay(from: state) }

    func issue(for date: Date) -> Issue {
        DayPlanner(library: library, startDay: startDay).issue(for: date)
    }

    var todayIssue: Issue { issue(for: today) }

    func item(id: String) -> Item? { library.item(id: id) }

    func issue(containing item: Item) -> Issue? { library.issue(containing: item.id) }

    /// Все дни от сегодняшнего до первого.
    var archiveDays: [Date] {
        let count = max(0, Days.between(startDay, today))
        return (0...count).map { Days.adding(days: -$0, to: today) }
    }

    /// Номер выпуска для подписи «Выпуск № 12».
    func issueNumber(for date: Date) -> Int {
        Days.between(startDay, date) + 1
    }

    // MARK: - Отметки и закладки

    func completion(for item: Item) -> Completion? { state.completions[item.id] }

    func isDone(_ item: Item) -> Bool { state.completions[item.id] != nil }

    func isBookmarked(_ item: Item) -> Bool { state.bookmarks[item.id] != nil }

    func markDone(_ item: Item, rating: Int?, note: String?) {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        mutate { state in
            var completion = state.completions[item.id] ?? Completion(date: Date())
            completion.rating = rating
            completion.note = (trimmed?.isEmpty ?? true) ? nil : trimmed
            state.completions[item.id] = completion
            state.bookmarks[item.id] = nil
        }
    }

    func unmark(_ item: Item) {
        mutate { $0.completions[item.id] = nil }
    }

    func toggleDone(_ item: Item) {
        if isDone(item) {
            unmark(item)
        } else {
            markDone(item, rating: nil, note: nil)
        }
    }

    func toggleBookmark(_ item: Item) {
        mutate { state in
            state.bookmarks[item.id] = state.bookmarks[item.id] == nil ? Date() : nil
        }
    }

    /// Начать заново: отметки стираются, выпуски снова идут с первого.
    func resetProgress() {
        mutate { state in
            state = UserState()
            state.startDay = Days.key(for: Date())
        }
        todayPath = []
        archivePath = []
        journalPath = []
    }

    private func mutate(_ change: (inout UserState) -> Void) {
        state = store.update(change)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Дневник и статистика

    var journalEntries: [JournalEntry] {
        state.completions
            .compactMap { id, completion in library.item(id: id).map { JournalEntry(item: $0, completion: completion) } }
            .sorted { $0.completion.date > $1.completion.date }
    }

    var bookmarkedItems: [Item] {
        state.bookmarks
            .sorted { $0.value > $1.value }
            .compactMap { library.item(id: $0.key) }
    }

    func completedCount(of kind: ItemKind) -> Int {
        state.completions.keys.compactMap { library.item(id: $0) }.filter { $0.kind == kind }.count
    }

    var currentStreak: Int {
        Streaks.current(dates: state.completions.values.map(\.date), today: today)
    }

    var bestStreak: Int {
        Streaks.best(dates: state.completions.values.map(\.date))
    }

    /// Дневник в Markdown — для экспорта.
    func journalMarkdown() -> String {
        var lines = ["# Дневник «\(AppConfig.appName)»", ""]
        var currentMonth = ""
        for entry in journalEntries {
            let month = Format.monthYear(entry.completion.date)
            if month != currentMonth {
                currentMonth = month
                lines.append("## \(month)")
                lines.append("")
            }
            let item = entry.item
            var line = "- \(Format.dayMonth(entry.completion.date)) — \(item.kind.title): «\(item.title)», \(item.metaLine)"
            if let rating = entry.completion.rating {
                line += " " + String(repeating: "★", count: rating) + String(repeating: "☆", count: max(0, 5 - rating))
            }
            lines.append(line)
            if let note = entry.completion.note {
                lines.append("  > \(note.replacingOccurrences(of: "\n", with: " "))")
            }
        }
        if journalEntries.isEmpty {
            lines.append("Пока пусто.")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Жизненный цикл

    /// Вызывается при каждом возвращении в приложение.
    func becameActive() {
        state = store.load()
        refreshDay()
        prefetchUpcomingArtwork()
        Task { await refreshRemoteCatalogIfNeeded() }
    }

    func refreshDay() {
        let now = Date()
        guard !Days.isSameDay(now, today) else { return }
        today = now
        todayPath = []
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Заранее скачиваем изображения на сегодня и завтра — для виджета и работы без сети.
    func prefetchUpcomingArtwork() {
        let todayItems = issue(for: today).items
        let tomorrowItems = issue(for: Days.adding(days: 1, to: today)).items
        Task.detached(priority: .utility) {
            var downloaded = await Self.prefetchArtwork(for: todayItems)
            // Завтрашние — чуть позже, чтобы не просить у iTunes всё разом.
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            downloaded = await Self.prefetchArtwork(for: tomorrowItems) || downloaded
            if downloaded {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    /// true — что-то скачали.
    private nonisolated static func prefetchArtwork(for items: [Item]) async -> Bool {
        var downloaded = false
        for item in items {
            guard let url = await MediaResolver.shared.artworkURL(for: item),
                  !ImageStore.shared.isCached(url)
            else { continue }
            await ImageStore.shared.prefetch(url)
            downloaded = true
        }
        return downloaded
    }

    private func refreshRemoteCatalogIfNeeded() async {
        guard AppConfig.remoteCatalogURL != nil else { return }
        if let lastRemoteCheck, Date().timeIntervalSince(lastRemoteCheck) < AppConfig.remoteCatalogRefreshInterval { return }
        lastRemoteCheck = Date()
        if await ContentLibrary.refreshRemote() {
            library = ContentLibrary.load()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: - Ссылки kvartet://

    /// kvartet://today, kvartet://archive, kvartet://journal, kvartet://settings,
    /// kvartet://item/<id> и kvartet://item/<id>?open=reader|look|zoom.
    func handle(url: URL) {
        guard url.scheme == AppConfig.urlScheme else { return }
        let parts = url.pathComponents.filter { $0 != "/" }
        switch url.host {
        case "item":
            guard let id = parts.first, library.item(id: id) != nil else { return }
            let open = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "open" })?.value
                .flatMap(PendingOpen.Action.init(rawValue:))
            pendingOpen = open.map { PendingOpen(itemID: id, action: $0) }
            selectedTab = .today
            todayPath = [.item(id)]
        case "archive":
            selectedTab = .archive
            archivePath = []
        case "journal":
            selectedTab = .journal
            journalPath = []
        case "settings":
            selectedTab = .today
            todayPath = []
            isSettingsPresented = true
        default:
            selectedTab = .today
            todayPath = []
        }
    }

    /// Забрать отложенное действие для рекомендации (одноразово).
    func takePendingOpen(for item: Item) -> PendingOpen.Action? {
        guard let pendingOpen, pendingOpen.itemID == item.id else { return nil }
        self.pendingOpen = nil
        return pendingOpen.action
    }
}

/// Действие, которое нужно выполнить сразу после перехода к рекомендации.
struct PendingOpen: Equatable {
    enum Action: String {
        case reader
        case look
        case zoom
    }

    let itemID: String
    let action: Action
}
