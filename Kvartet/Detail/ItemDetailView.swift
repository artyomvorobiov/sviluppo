import SwiftUI

/// Экран рекомендации: изображение, описание, действия и отметка «изучено».
struct ItemDetailView: View {
    let item: Item

    @Environment(AppModel.self) private var model
    @Environment(Preferences.self) private var prefs
    @Environment(\.openURL) private var openURL

    @State private var showCompletion = false
    @State private var showReader = false
    @State private var showSlowLooking = false
    @State private var showZoom = false
    @State private var safariLink: IdentifiedURL?
    @State private var trailerLink: IdentifiedURL?
    @State private var isLoadingTrailer = false
    @State private var readMoreURL: URL?
    @State private var shareCardURL: URL?
    @State private var player = PreviewPlayer()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                DetailHero(item: item) { showZoom = true }
                titleBlock
                actions
                sections
                completionBlock
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
        .background(Theme.paper.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showCompletion) {
            CompletionSheet(item: item)
                .environment(model)
        }
        .fullScreenCover(isPresented: $showReader) {
            ReaderScreen(item: item)
                .environment(model)
                .environment(prefs)
        }
        .fullScreenCover(isPresented: $showSlowLooking) {
            SlowLookingView(item: item)
                .environment(model)
                .environment(prefs)
        }
        .fullScreenCover(isPresented: $showZoom) {
            ZoomViewer(item: item)
        }
        .sheet(item: $safariLink) { link in
            SafariView(url: link.url)
                .ignoresSafeArea()
        }
        .sheet(item: $trailerLink) { link in
            TrailerPlayerView(url: link.url)
        }
        .task(id: item.id) {
            readMoreURL = await MediaResolver.shared.readMoreURL(for: item)
        }
        .task(id: item.id) {
            shareCardURL = await ShareCardRenderer.render(item: item, theme: model.issue(containing: item)?.theme)
        }
        .onDisappear {
            player.stop()
        }
    }

    // MARK: - Заголовок

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            KindLabel(item: item)
            Text(item.title)
                .font(.system(.largeTitle, design: .serif).weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let original = item.originalTitle, original != item.title {
                Text(original)
                    .font(.system(.title3, design: .serif))
                    .italic()
                    .foregroundStyle(.secondary)
            }
            Text(item.metaLine)
                .font(.headline)
                .foregroundStyle(.secondary)
            if let details = item.details, !details.isEmpty {
                Text(details.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Действия

    @ViewBuilder
    private var actions: some View {
        switch item.kind {
        case .painting:
            VStack(spacing: 10) {
                Button {
                    showSlowLooking = true
                } label: {
                    Label("Медленный просмотр", systemImage: "eye")
                }
                .buttonStyle(FilledButtonStyle())

                HStack(spacing: 10) {
                    Button {
                        showZoom = true
                    } label: {
                        Label("Увеличить", systemImage: "plus.magnifyingglass")
                    }
                    .buttonStyle(OutlineButtonStyle())

                    if let readMoreURL {
                        Button {
                            openInApp(readMoreURL)
                        } label: {
                            Label("Википедия", systemImage: "book")
                        }
                        .buttonStyle(OutlineButtonStyle())
                    }
                }
            }

        case .article:
            VStack(spacing: 10) {
                Button {
                    showReader = true
                } label: {
                    Label("Читать", systemImage: "text.alignleft")
                }
                .buttonStyle(FilledButtonStyle())
                .disabled(item.articleURL == nil)

                if let url = item.articleURL {
                    Button {
                        openInApp(url)
                    } label: {
                        Label("Открыть оригинал", systemImage: "safari")
                    }
                    .buttonStyle(OutlineButtonStyle())
                }
            }

        case .album:
            VStack(spacing: 10) {
                if item.keyTrack != nil {
                    PreviewButton(item: item, player: player)
                }
                Button {
                    openExternal(prefs.musicService.url(for: item))
                } label: {
                    Label("Слушать в \(prefs.musicService.title)", systemImage: "play.fill")
                }
                .buttonStyle(FilledButtonStyle())

                HStack(spacing: 10) {
                    Menu {
                        ForEach(MusicService.allCases.filter { $0 != prefs.musicService }) { service in
                            Button(service.title) { openExternal(service.url(for: item)) }
                        }
                    } label: {
                        OutlineLabel { Label("Другие сервисы", systemImage: "ellipsis.circle") }
                    }
                    if let readMoreURL {
                        Button {
                            openInApp(readMoreURL)
                        } label: {
                            Label("Об альбоме", systemImage: "book")
                        }
                        .buttonStyle(OutlineButtonStyle())
                    }
                }
            }

        case .film:
            VStack(spacing: 10) {
                Button {
                    openExternal(prefs.filmService.url(for: item))
                } label: {
                    Label("Где смотреть: \(prefs.filmService.title)", systemImage: "play.rectangle")
                }
                .buttonStyle(FilledButtonStyle())

                HStack(spacing: 10) {
                    Button {
                        Task { await playTrailer() }
                    } label: {
                        if isLoadingTrailer {
                            ProgressView()
                        } else {
                            Label("Трейлер", systemImage: "film")
                        }
                    }
                    .buttonStyle(OutlineButtonStyle())
                    .disabled(isLoadingTrailer)

                    Menu {
                        ForEach(FilmService.allCases.filter { $0 != prefs.filmService }) { service in
                            Button(service.title) { openExternal(service.url(for: item)) }
                        }
                        if let readMoreURL {
                            Button("Википедия") { openInApp(readMoreURL) }
                        }
                    } label: {
                        OutlineLabel { Label("Ещё", systemImage: "ellipsis.circle") }
                    }
                }
            }
        }
    }

    // MARK: - Текст

    @ViewBuilder
    private var sections: some View {
        DetailSection(title: "О чём", text: item.summary)
        if let why = item.why {
            DetailSection(title: "Почему стоит", text: why)
        }
        if let lookFor = item.lookFor, !lookFor.isEmpty {
            BulletSection(title: item.kind.lookForTitle, items: lookFor, color: item.kind.color)
        }
        if let fact = item.fact {
            FactCard(text: fact, color: item.kind.color)
        }
        if let more = item.more, !more.isEmpty {
            BulletSection(title: "Если понравится", items: more, color: item.kind.color)
        }
    }

    // MARK: - Отметка

    @ViewBuilder
    private var completionBlock: some View {
        if let completion = model.completion(for: item) {
            VStack(alignment: .leading, spacing: 10) {
                Label("\(item.kind.doneTitle) \(Format.dayMonth(completion.date))", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(item.kind.color)
                if let rating = completion.rating {
                    StarsView(rating: rating, color: item.kind.color)
                }
                if let note = completion.note {
                    Text(note)
                        .font(Theme.serif(.body, weight: .regular))
                        .italic()
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Изменить отзыв") { showCompletion = true }
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 2)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
        } else {
            Button {
                showCompletion = true
            } label: {
                Label(item.kind.markActionTitle, systemImage: "checkmark.circle")
            }
            .buttonStyle(FilledButtonStyle(background: item.kind.color, foreground: .white))
        }
    }

    // MARK: - Панель

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                model.toggleBookmark(item)
            } label: {
                Image(systemName: model.isBookmarked(item) ? "bookmark.fill" : "bookmark")
            }
            .accessibilityLabel(model.isBookmarked(item) ? "Убрать из отложенного" : "Отложить")

            Menu {
                ShareLink(item: shareText) {
                    Label("Поделиться ссылкой", systemImage: "link")
                }
                if let shareCardURL {
                    ShareLink(item: shareCardURL) {
                        Label("Карточка для сторис", systemImage: "photo.on.rectangle")
                    }
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Поделиться")
        }
    }

    private var shareText: String {
        var text = "«\(item.title)» — \(item.metaLine)"
        if let link = item.articleURL ?? readMoreURL ?? item.wikipediaURL {
            text += "\n\(link.absoluteString)"
        }
        text += "\nНашёл(ла) в «\(AppConfig.appName)»"
        return text
    }

    // MARK: - Переходы

    /// Внутри приложения (Википедия, оригинал статьи).
    private func openInApp(_ url: URL) {
        if SafariView.canOpen(url) {
            safariLink = IdentifiedURL(url)
        } else {
            openURL(url)
        }
    }

    /// В другом приложении (стриминги открываются в своих приложениях по universal links).
    private func openExternal(_ url: URL?) {
        guard let url else { return }
        openURL(url)
    }

    private func playTrailer() async {
        isLoadingTrailer = true
        defer { isLoadingTrailer = false }
        player.stop()
        if let url = await MediaResolver.shared.previewURL(for: item) {
            trailerLink = IdentifiedURL(url)
        } else {
            openExternal(FilmService.youTubeTrailerURL(for: item))
        }
    }
}

/// «Любопытно» — выделенный факт.
struct FactCard: View {
    let text: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Любопытно", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(color)
            Text(text)
                .font(Theme.serif(.body, weight: .regular))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(color.opacity(0.09))
        )
    }
}
