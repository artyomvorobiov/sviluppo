import SwiftUI
import WebKit

/// Полноэкранная читалка статьи.
struct ReaderScreen: View {
    let item: Item

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppModel.self) private var model
    @Environment(Preferences.self) private var prefs
    @State private var controller = ReaderController()
    @State private var showCompletion = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                background.ignoresSafeArea()

                ReaderWebView(webView: controller.webView)
                    .ignoresSafeArea(edges: .bottom)
                    .opacity(controller.phase == .failed ? 0 : 1)

                if controller.isLoading {
                    loadingView
                }

                if controller.phase == .failed {
                    failureView
                }

                ProgressView(value: controller.progress)
                    .progressViewStyle(.linear)
                    .tint(item.kind.color)
                    .scaleEffect(x: 1, y: 0.6, anchor: .top)
                    .opacity(controller.isLoading ? 0 : 1)
            }
            .overlay(alignment: .bottom) {
                if showFinishButton {
                    finishButton
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.35), value: showFinishButton)
            .navigationTitle(controller.article?.siteName(for: item) ?? item.source ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Закрыть")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    settingsMenu
                }
            }
        }
        .task {
            controller.start(item: item, theme: prefs.readerTheme, textScale: prefs.readerTextScale)
        }
        .sheet(item: $controller.linkToOpen) { link in
            SafariView(url: link.url)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showCompletion) {
            CompletionSheet(item: item)
                .environment(model)
        }
    }

    // MARK: - Части

    private var background: Color {
        switch prefs.readerTheme {
        case .auto, .light: Theme.paper
        case .sepia: Color(red: 0.957, green: 0.925, blue: 0.847)
        case .dark: Color(red: 0.067, green: 0.067, blue: 0.075)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Готовим статью для чтения…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
    }

    private var failureView: some View {
        ContentUnavailableView {
            Label("Не удалось загрузить статью", systemImage: "wifi.exclamationmark")
        } description: {
            Text("Проверьте подключение к интернету и попробуйте ещё раз.")
        } actions: {
            Button("Повторить") { controller.retry() }
                .buttonStyle(.bordered)
        }
    }

    private var showFinishButton: Bool {
        controller.phase == .reader && controller.progress > 0.85 && !model.isDone(item)
    }

    private var finishButton: some View {
        Button {
            showCompletion = true
        } label: {
            Label("Прочитано", systemImage: "checkmark")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 13)
                .background(Capsule().fill(item.kind.color))
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        }
    }

    private var settingsMenu: some View {
        Menu {
            Section("Размер текста") {
                Button {
                    changeTextScale(by: 0.1)
                } label: {
                    Label("Крупнее", systemImage: "plus.magnifyingglass")
                }
                Button {
                    changeTextScale(by: -0.1)
                } label: {
                    Label("Мельче", systemImage: "minus.magnifyingglass")
                }
            }

            Picker("Оформление", selection: themeBinding) {
                ForEach(ReaderTheme.allCases) { theme in
                    Text(theme.title).tag(theme)
                }
            }

            if controller.canSwitchMode {
                Button {
                    if controller.isReaderMode {
                        controller.showOriginal()
                    } else {
                        controller.showReader()
                    }
                } label: {
                    if controller.isReaderMode {
                        Label("Оригинальная страница", systemImage: "globe")
                    } else {
                        Label("Режим чтения", systemImage: "doc.plaintext")
                    }
                }
            }

            if let url = item.articleURL {
                ShareLink(item: url) {
                    Label("Поделиться", systemImage: "square.and.arrow.up")
                }
                Button {
                    openURL(url)
                } label: {
                    Label("Открыть в Safari", systemImage: "safari")
                }
            }
        } label: {
            Image(systemName: "textformat.size")
        }
        .accessibilityLabel("Настройки чтения")
    }

    private var themeBinding: Binding<ReaderTheme> {
        Binding(
            get: { prefs.readerTheme },
            set: { newValue in
                prefs.readerTheme = newValue
                controller.setTheme(newValue)
            }
        )
    }

    private func changeTextScale(by delta: Double) {
        prefs.readerTextScale += delta
        controller.setTextScale(prefs.readerTextScale)
    }
}

/// Готовый WKWebView из контроллера.
struct ReaderWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
