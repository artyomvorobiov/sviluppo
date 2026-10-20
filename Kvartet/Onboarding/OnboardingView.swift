import SwiftUI

/// Первый запуск: что это за приложение и когда напоминать.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(Preferences.self) private var prefs
    @State private var remind = true
    @State private var time = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var isFinishing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    QuartetMark()
                        .frame(width: 56, height: 56)
                    Text(AppConfig.appName)
                        .font(.system(size: 52, weight: .semibold, design: .serif))
                    Text("Каждый день — четыре открытия, связанные одной темой.")
                        .font(Theme.serif(.title3, weight: .regular))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 18) {
                    ForEach(ItemKind.displayOrder) { kind in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: kind.symbol)
                                .font(.title3)
                                .foregroundStyle(kind.color)
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.title)
                                    .font(.headline)
                                Text(kind.onboardingLine)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Text("Отмечайте изученное, ставьте оценки и пишите пару слов — так получится дневник ваших открытий. Виджет покажет выпуск дня прямо на экране «Домой».")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 0) {
                    Toggle("Напоминать каждый день", isOn: $remind)
                        .padding(.vertical, 10)
                    if remind {
                        Divider()
                        DatePicker("Время", selection: $time, displayedComponents: .hourAndMinute)
                            .padding(.vertical, 6)
                    }
                }
                .padding(.horizontal, 16)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
            }
            .padding(.horizontal, 24)
            .padding(.top, 48)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.paper.ignoresSafeArea())
        // Кнопка всегда видна, даже на маленьком экране.
        .safeAreaInset(edge: .bottom) {
            Button {
                finish()
            } label: {
                if isFinishing {
                    ProgressView().tint(Theme.paper)
                } else {
                    Text("Начать")
                }
            }
            .buttonStyle(FilledButtonStyle())
            .disabled(isFinishing)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Theme.paper)
        }
        .interactiveDismissDisabled()
    }

    private func finish() {
        isFinishing = true
        prefs.reminderTime = time
        Task {
            if remind {
                prefs.reminderEnabled = await ReminderScheduler.requestAuthorization()
            } else {
                prefs.reminderEnabled = false
            }
            await ReminderScheduler.reschedule(model: model, prefs: prefs)
            prefs.didOnboard = true
        }
    }
}

/// Знак приложения: четыре квадрата цветов четырёх типов.
struct QuartetMark: View {
    var body: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            GridRow {
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(ItemKind.painting.color)
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(ItemKind.article.color)
            }
            GridRow {
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(ItemKind.album.color)
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(ItemKind.film.color)
            }
        }
        .accessibilityHidden(true)
    }
}
