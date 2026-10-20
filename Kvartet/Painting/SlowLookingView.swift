import SwiftUI
import UIKit

/// «Медленный просмотр»: картина на весь экран и подсказки, сменяющиеся каждые ~20 секунд.
/// Идея из практики slow looking — смотреть на одну работу дольше, чем привыкли.
struct SlowLookingView: View {
    let item: Item

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var image: UIImage?
    @State private var elapsed: Double = 0
    @State private var isRunning = true
    @State private var showsPrompt = true
    @State private var showCompletion = false

    /// Секунд на одну подсказку.
    private let secondsPerPrompt: Double = 20

    private var prompts: [String] {
        var list = ["Не спешите читать подписи. Просто посмотрите на картину целиком — около полуминуты."]
        list += item.lookFor ?? []
        list.append("Теперь посмотрите туда, куда не смотрели. Края, фон, тени, пустоты.")
        list.append("Закройте глаза и попробуйте вспомнить картину. Что всплывает первым?")
        return list
    }

    private var totalDuration: Double { Double(prompts.count) * secondsPerPrompt }
    private var currentIndex: Int { min(prompts.count - 1, Int(elapsed / secondsPerPrompt)) }
    private var isFinished: Bool { elapsed >= totalDuration }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                ZoomableImage(image: image)
                    .ignoresSafeArea()
            } else {
                ProgressView().tint(.white)
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                if showsPrompt {
                    promptCard
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .statusBarHidden()
        .preferredColorScheme(.dark)
        .task { image = await ArtworkLoader.image(for: item, maxPixel: 3000) }
        .task(id: isRunning) { await tick() }
        .sheet(isPresented: $showCompletion) {
            CompletionSheet(item: item)
                .environment(model)
        }
    }

    // MARK: - Части

    private var topBar: some View {
        HStack(spacing: 12) {
            CloseButton { dismiss() }
            ProgressView(value: min(elapsed, totalDuration), total: totalDuration)
                .tint(.white)
            Button {
                withAnimation(.easeInOut) { showsPrompt.toggle() }
            } label: {
                Image(systemName: showsPrompt ? "text.bubble.fill" : "text.bubble")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.black.opacity(0.45)))
            }
            .accessibilityLabel(showsPrompt ? "Скрыть подсказки" : "Показать подсказки")
        }
        .padding(.top, 8)
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isFinished ? "Что вы увидели?" : "Подсказка \(currentIndex + 1) из \(prompts.count)")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.6))

            Text(isFinished ? "Запишите одну мысль — так картина запомнится надолго." : prompts[currentIndex])
                .font(Theme.serif(.title3, weight: .regular))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .id(isFinished ? -1 : currentIndex)
                .transition(.opacity)

            HStack(spacing: 10) {
                if isFinished {
                    Button {
                        showCompletion = true
                    } label: {
                        Label("Записать в дневник", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(FilledButtonStyle(background: .white, foreground: .black))

                    Button {
                        elapsed = 0
                        isRunning = true
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(RoundGlassButtonStyle())
                    .accessibilityLabel("Ещё раз")
                } else {
                    Button {
                        isRunning.toggle()
                    } label: {
                        Image(systemName: isRunning ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(RoundGlassButtonStyle())
                    .accessibilityLabel(isRunning ? "Пауза" : "Продолжить")

                    Button {
                        withAnimation(.easeInOut) {
                            elapsed = min(totalDuration, Double(currentIndex + 1) * secondsPerPrompt)
                        }
                    } label: {
                        Image(systemName: "forward.fill")
                    }
                    .buttonStyle(RoundGlassButtonStyle())
                    .accessibilityLabel("Следующая подсказка")

                    Spacer()
                    Text(remainingText)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.4), value: currentIndex)
    }

    private var remainingText: String {
        let seconds = max(0, Int(totalDuration - elapsed))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - Таймер

    private func tick() async {
        while isRunning && !isFinished && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard isRunning, !Task.isCancelled else { return }
            elapsed += 1
        }
        // Останавливаемся, чтобы кнопка «Ещё раз» перезапустила таймер.
        if isFinished {
            isRunning = false
        }
    }
}

/// Круглая полупрозрачная кнопка поверх картины.
struct RoundGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 46, height: 46)
            .background(Circle().fill(.white.opacity(configuration.isPressed ? 0.3 : 0.16)))
    }
}
