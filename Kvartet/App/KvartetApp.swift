import SwiftUI

@main
struct KvartetApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @State private var prefs: Preferences

    init() {
        let prefs = Preferences()
        #if DEBUG
        // Для автоматических скриншотов: запуск с аргументом -skipOnboarding.
        if ProcessInfo.processInfo.arguments.contains("-skipOnboarding") {
            prefs.didOnboard = true
        }
        #endif
        _prefs = State(initialValue: prefs)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(prefs)
        }
    }
}
