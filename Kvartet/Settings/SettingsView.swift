import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(Preferences.self) private var prefs
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var notificationsDenied = false
    @State private var confirmReset = false
    @State private var cacheCleared = false

    var body: some View {
        @Bindable var prefs = prefs
        NavigationStack {
            Form {
                Section {
                    ForEach(ItemKind.displayOrder) { kind in
                        Toggle(isOn: kindBinding(kind)) {
                            Label(kind.pluralTitle, systemImage: kind.symbol)
                        }
                        .tint(kind.color)
                    }
                } header: {
                    Text("Что показывать")
                } footer: {
                    Text("Выключенные типы не появятся ни в выпусках, ни в виджетах.")
                }

                Section {
                    Toggle("Ежедневное напоминание", isOn: reminderBinding)
                    if prefs.reminderEnabled {
                        DatePicker("Время", selection: $prefs.reminderTime, displayedComponents: .hourAndMinute)
                    }
                    if notificationsDenied {
                        Button("Разрешить уведомления в Настройках") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                    }
                } header: {
                    Text("Напоминание")
                } footer: {
                    Text("Утром придёт тема дня и первая рекомендация.")
                }

                Section("Сервисы") {
                    Picker("Музыка", selection: $prefs.musicService) {
                        ForEach(MusicService.allCases) { service in
                            Text(service.title).tag(service)
                        }
                    }
                    Picker("Фильмы", selection: $prefs.filmService) {
                        ForEach(FilmService.allCases) { service in
                            Text(service.title).tag(service)
                        }
                    }
                }

                Section("Чтение") {
                    Picker("Оформление", selection: $prefs.readerTheme) {
                        ForEach(ReaderTheme.allCases) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                    Stepper(value: $prefs.readerTextScale, in: 0.8...1.6, step: 0.1) {
                        HStack {
                            Text("Размер текста")
                            Spacer()
                            Text("\(Int((prefs.readerTextScale * 100).rounded())) %")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }

                Section {
                    ShareLink(item: model.journalMarkdown(), preview: SharePreview("Дневник «\(AppConfig.appName)»")) {
                        Label("Экспортировать дневник", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        ImageStore.shared.clearAll()
                        ArticleCache.clearAll()
                        cacheCleared = true
                    } label: {
                        Label(cacheCleared ? "Кэш очищен" : "Очистить кэш картинок и статей", systemImage: "trash")
                    }
                    .disabled(cacheCleared)
                    Button(role: .destructive) {
                        confirmReset = true
                    } label: {
                        Label("Начать сначала", systemImage: "arrow.counterclockwise")
                    }
                } header: {
                    Text("Данные")
                } footer: {
                    if !AppGroup.isShared {
                        Text("App Group не настроена: виджет не увидит ваши отметки. Как исправить — в README проекта.")
                    }
                }

                Section("О приложении") {
                    LabeledContent("Версия", value: appVersion)
                    LabeledContent("Выпусков в каталоге", value: "\(model.library.issues.count)")
                    Text("Изображения картин — Wikimedia Commons (общественное достояние). Обложки, фрагменты и трейлеры — iTunes Search API. Режим чтения — Mozilla Readability (Apache 2.0).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .onChange(of: prefs.reminderTime) { _, _ in
                reschedule()
            }
            .confirmationDialog("Начать сначала?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Стереть отметки и дневник", role: .destructive) {
                    model.resetProgress()
                    reschedule()
                    dismiss()
                }
            } message: {
                Text("Отметки, оценки, заметки и закладки будут удалены, выпуски начнутся с первого.")
            }
            .task {
                notificationsDenied = await ReminderScheduler.isDenied()
            }
        }
    }

    // MARK: - Привязки

    private func kindBinding(_ kind: ItemKind) -> Binding<Bool> {
        Binding(
            get: { prefs.isEnabled(kind) },
            set: { prefs.setKind(kind, enabled: $0) }
        )
    }

    private var reminderBinding: Binding<Bool> {
        Binding(
            get: { prefs.reminderEnabled },
            set: { newValue in
                if newValue {
                    Task {
                        let granted = await ReminderScheduler.requestAuthorization()
                        prefs.reminderEnabled = granted
                        notificationsDenied = !granted
                        reschedule()
                    }
                } else {
                    prefs.reminderEnabled = false
                    reschedule()
                }
            }
        )
    }

    private func reschedule() {
        Task { await ReminderScheduler.reschedule(model: model, prefs: prefs) }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}
