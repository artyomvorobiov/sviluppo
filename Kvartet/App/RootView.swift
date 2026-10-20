import SwiftUI
import UIKit

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(Preferences.self) private var prefs
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            TodayTab()
                .tabItem { Label("Сегодня", systemImage: "sun.max") }
                .tag(AppTab.today)
            ArchiveTab()
                .tabItem { Label("Архив", systemImage: "calendar") }
                .tag(AppTab.archive)
            JournalTab()
                .tabItem { Label("Дневник", systemImage: "book.closed") }
                .tag(AppTab.journal)
        }
        .tint(Theme.accent)
        .fullScreenCover(isPresented: onboardingBinding) {
            OnboardingView()
                .environment(model)
                .environment(prefs)
        }
        .onOpenURL { url in
            model.handle(url: url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .kvartetOpenURL)) { note in
            if let url = note.object as? URL {
                model.handle(url: url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            model.refreshDay()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            activate()
        }
        .onChange(of: prefs.enabledKinds) { _, _ in
            Task { await ReminderScheduler.reschedule(model: model, prefs: prefs) }
        }
        .task {
            activate()
        }
    }

    private var onboardingBinding: Binding<Bool> {
        Binding(get: { !prefs.didOnboard }, set: { _ in })
    }

    private func activate() {
        model.becameActive()
        Task { await ReminderScheduler.reschedule(model: model, prefs: prefs) }
    }
}

/// Вкладка «Сегодня».
struct TodayTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.todayPath) {
            IssueView(date: model.today, isToday: true)
                .navigationDestination(for: Route.self) { route in
                    RouteDestination(route: route)
                }
        }
    }
}
