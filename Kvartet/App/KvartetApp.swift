import SwiftUI

@main
struct KvartetApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @State private var prefs = Preferences()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(prefs)
        }
    }
}
