import AppIntents
import WidgetKit

/// Отметка «изучено» прямо из виджета (интерактивные виджеты iOS 17+).
/// Файл входит и в приложение, и в расширение виджета.
struct ToggleDoneIntent: AppIntent {
    static var title: LocalizedStringResource = "Отметить рекомендацию"
    static var description = IntentDescription("Отмечает рекомендацию дня как изученную или снимает отметку.")
    static var isDiscoverable: Bool = false

    @Parameter(title: "Рекомендация")
    var itemID: String

    init() {}

    init(itemID: String) {
        self.itemID = itemID
    }

    func perform() async throws -> some IntentResult {
        let id = itemID
        UserStateStore.shared.update { state in
            if state.completions[id] != nil {
                state.completions[id] = nil
            } else {
                state.completions[id] = Completion(date: Date())
                state.bookmarks[id] = nil
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
