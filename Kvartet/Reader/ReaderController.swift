import Observation
import SwiftUI
import WebKit

/// Статья, очищенная Readability.js (сохраняется для чтения без сети).
struct ParsedArticle: Codable, Equatable {
    var title: String
    var byline: String?
    var siteName: String?
    var content: String
    /// Длина основного текста в символах (по ней считается время чтения).
    var length: Int
    var lang: String?
}

extension ParsedArticle {
    /// Издание: из каталога («Википедия»), иначе как его указал сайт («Фонд Викимедиа»).
    func siteName(for item: Item?) -> String? {
        [item?.source, siteName].compactMap { $0 }.first { !$0.isEmpty }
    }

    /// Автор, если сайт назвал настоящего автора, а не «Contributors to Wikimedia projects».
    var author: String? {
        guard let byline, !byline.isEmpty else { return nil }
        let lowercased = byline.lowercased()
        let boilerplate = ["wikimedia", "wikipedia", "викимеди", "википеди"]
        return boilerplate.contains { lowercased.contains($0) } ? nil : byline
    }
}

/// Кэш очищенных статей: открытая однажды статья доступна офлайн.
enum ArticleCache {
    private static func fileURL(id: String) -> URL {
        AppGroup.directory("Articles").appendingPathComponent("\(id).json")
    }

    static func load(id: String) -> ParsedArticle? {
        guard let data = try? Data(contentsOf: fileURL(id: id)) else { return nil }
        return try? JSONDecoder().decode(ParsedArticle.self, from: data)
    }

    static func save(_ article: ParsedArticle, id: String) {
        guard let data = try? JSONEncoder().encode(article) else { return }
        try? data.write(to: fileURL(id: id), options: .atomic)
    }

    static func clearAll() {
        try? FileManager.default.removeItem(at: AppGroup.directory("Articles"))
    }
}

/// Делегат WKWebView, передающий события контроллеру через замыкания.
final class ReaderWebDelegate: NSObject, WKNavigationDelegate {
    var onFinish: (() -> Void)?
    var onFail: ((Error) -> Void)?
    /// true — ссылку обработали сами, переход отменить.
    var onLinkActivated: ((URL) -> Bool)?
    var allowsJavaScript: (() -> Bool)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish?()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onFail?(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onFail?(error)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url,
           onLinkActivated?(url) == true {
            decisionHandler(.cancel, preferences)
            return
        }
        preferences.allowsContentJavaScript = allowsJavaScript?() ?? true
        decisionHandler(.allow, preferences)
    }
}

/// Читалка: загружает страницу, извлекает текст Readability.js и показывает его
/// в аккуратной вёрстке. Если извлечь не удалось — показывает оригинальную страницу.
@MainActor
@Observable
final class ReaderController {
    enum Phase: Equatable {
        case idle
        /// Грузим оригинал, чтобы извлечь текст.
        case fetching
        /// Показываем подготовленный текст.
        case renderingReader
        case reader
        /// Пользователь попросил оригинальную страницу.
        case loadingOriginal
        case original
        case failed
    }

    private(set) var phase: Phase = .idle
    private(set) var progress: Double = 0
    private(set) var article: ParsedArticle?
    var linkToOpen: IdentifiedURL?

    let webView: WKWebView
    private let delegate = ReaderWebDelegate()
    @ObservationIgnored private var item: Item?
    @ObservationIgnored private var sourceURL: URL?
    @ObservationIgnored private var theme: ReaderTheme = .auto
    @ObservationIgnored private var scrollObservation: NSKeyValueObservation?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var pendingScrollRatio: Double?

    var isLoading: Bool {
        phase == .idle || phase == .fetching || phase == .renderingReader
    }

    var isReaderMode: Bool {
        phase == .reader || phase == .renderingReader
    }

    var canSwitchMode: Bool {
        article != nil && sourceURL != nil
    }

    /// Оценка времени чтения по длине текста (~1300 знаков в минуту).
    var minutes: Int? {
        article.map { max(1, Int((Double($0.length) / 1300).rounded())) }
    }

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.dataDetectorTypes = []
        if let url = Bundle.main.url(forResource: "Readability", withExtension: "js"),
           let source = try? String(contentsOf: url, encoding: .utf8) {
            let script = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient)
            configuration.userContentController.addUserScript(script)
        }
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = delegate

        delegate.onFinish = { [weak self] in self?.handleFinish() }
        delegate.onFail = { [weak self] error in self?.handleFailure(error) }
        delegate.onLinkActivated = { [weak self] url in self?.handleLink(url) ?? false }
        delegate.allowsJavaScript = { [weak self] in
            guard let self else { return true }
            return !self.isReaderMode
        }

        scrollObservation = webView.scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.updateProgress()
            }
        }
    }

    // MARK: - Управление

    func start(item: Item, theme: ReaderTheme, textScale: Double) {
        guard phase == .idle else { return }
        self.item = item
        self.theme = theme
        sourceURL = item.articleURL
        webView.pageZoom = CGFloat(textScale)
        if let cached = ArticleCache.load(id: item.id) {
            article = cached
            renderReader(keepScroll: false)
        } else {
            fetch()
        }
    }

    func retry() {
        if article != nil {
            renderReader(keepScroll: false)
        } else {
            fetch()
        }
    }

    func showOriginal() {
        guard let sourceURL else { return }
        phase = .loadingOriginal
        progress = 0
        webView.load(URLRequest(url: sourceURL))
    }

    func showReader() {
        renderReader(keepScroll: false)
    }

    func setTheme(_ theme: ReaderTheme) {
        self.theme = theme
        if isReaderMode {
            renderReader(keepScroll: true)
        }
    }

    func setTextScale(_ scale: Double) {
        webView.pageZoom = CGFloat(scale)
    }

    // MARK: - Загрузка

    private func fetch() {
        guard let sourceURL else {
            phase = .failed
            return
        }
        phase = .fetching
        webView.load(URLRequest(url: sourceURL, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30))
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled, let self, self.phase == .fetching else { return }
            // Страница грузится слишком долго (реклама, счётчики) — пробуем извлечь текст из того, что есть.
            self.parseCurrentPage()
        }
    }

    private func handleFinish() {
        switch phase {
        case .fetching:
            parseCurrentPage()
        case .renderingReader:
            phase = .reader
            restoreScrollIfNeeded()
        case .loadingOriginal:
            phase = .original
        default:
            break
        }
    }

    private func handleFailure(_ error: Error) {
        let nsError = error as NSError
        // Отмена — обычное дело при редиректах и повторной загрузке.
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 { return } // «Frame load interrupted»
        timeoutTask?.cancel()
        switch phase {
        case .fetching, .loadingOriginal:
            if article != nil {
                renderReader(keepScroll: false)
            } else {
                phase = .failed
            }
        case .renderingReader:
            phase = .reader
        default:
            break
        }
    }

    private func parseCurrentPage() {
        timeoutTask?.cancel()
        let arguments: [String: Any] = ["expectedTitle": item?.title ?? ""]
        webView.callAsyncJavaScript(Self.parseScript, arguments: arguments, in: nil, in: .defaultClient) { [weak self] result in
            MainActor.assumeIsolated {
                self?.handleParse(result)
            }
        }
    }

    private func handleParse(_ result: Result<Any, Error>) {
        guard phase == .fetching else { return }
        guard case .success(let value) = result,
              let dictionary = value as? [String: Any],
              let content = dictionary["content"] as? String,
              !content.isEmpty
        else {
            // Не получилось — показываем страницу как есть, она уже загружена.
            phase = .original
            return
        }
        let parsed = ParsedArticle(
            title: (dictionary["title"] as? String) ?? item?.title ?? "",
            byline: (dictionary["byline"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            siteName: (dictionary["siteName"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            content: content,
            length: (dictionary["length"] as? NSNumber)?.intValue ?? content.count,
            lang: (dictionary["lang"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        )
        article = parsed
        if let item {
            ArticleCache.save(parsed, id: item.id)
        }
        renderReader(keepScroll: false)
    }

    private func renderReader(keepScroll: Bool) {
        guard let article else { return }
        pendingScrollRatio = keepScroll ? progress : nil
        phase = .renderingReader
        let html = ReaderTemplate.html(article: article, item: item, theme: theme, minutes: minutes)
        webView.loadHTMLString(html, baseURL: sourceURL)
    }

    // MARK: - Ссылки и прокрутка

    private func handleLink(_ url: URL) -> Bool {
        // Сноски и оглавление внутри статьи.
        if let sourceURL, url.fragment != nil,
           url.absoluteString.hasPrefix(sourceURL.absoluteString.components(separatedBy: "#")[0] + "#") {
            return false
        }
        if SafariView.canOpen(url) {
            linkToOpen = IdentifiedURL(url)
        }
        return true
    }

    private func updateProgress() {
        let scrollView = webView.scrollView
        let insets = scrollView.adjustedContentInset
        let maxOffset = scrollView.contentSize.height - scrollView.bounds.height + insets.top + insets.bottom
        guard maxOffset > 1 else { return }
        let value = min(1, max(0, (scrollView.contentOffset.y + insets.top) / maxOffset))
        if abs(value - progress) > 0.004 || value == 1 || value == 0 {
            progress = value
        }
    }

    private func restoreScrollIfNeeded() {
        guard let ratio = pendingScrollRatio, ratio > 0 else {
            progress = 0
            return
        }
        pendingScrollRatio = nil
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard let self else { return }
            let scrollView = self.webView.scrollView
            let insets = scrollView.adjustedContentInset
            let maxOffset = scrollView.contentSize.height - scrollView.bounds.height + insets.top + insets.bottom
            guard maxOffset > 0 else { return }
            scrollView.setContentOffset(CGPoint(x: 0, y: maxOffset * ratio - insets.top), animated: false)
        }
    }

    /// Тело async-функции для callAsyncJavaScript. Readability подключена user script'ом в том же «мире».
    /// Аргумент `expectedTitle` — название статьи из каталога.
    private static let parseScript = """
    if (typeof Readability === "undefined") { return null; }
    const documentClone = document.cloneNode(true);
    // Мобильная Википедия сворачивает разделы (hidden="until-found"), а Readability пропускает скрытое.
    documentClone.querySelectorAll('[hidden="until-found"]').forEach((node) => node.removeAttribute("hidden"));
    // Служебное у Википедии: «перенаправлено с…», ссылки «править», навигационные шаблоны.
    documentClone
      .querySelectorAll(".mw-redirectedfrom, #contentSub, #siteSub, .mw-editsection, .mw-jump-link, .navbox, .noprint")
      .forEach((node) => node.remove());
    const article = new Readability(documentClone, { charThreshold: 250 }).parse();
    if (!article || !article.content) { return null; }

    // Заголовок показывает сама читалка — убираем его повтор в начале текста.
    const normalize = (text) => (text || "").replace(/\\u00AD/g, "").replace(/[^\\p{L}\\p{N}]+/gu, " ").trim().toLowerCase();
    const titles = [expectedTitle, article.title].map(normalize).filter((text) => text.length > 0);
    const parsed = new DOMParser().parseFromString(article.content, "text/html");
    const heading = parsed.body.querySelector("h1, h2, h3");
    if (heading) {
      const text = normalize(heading.textContent);
      const position = normalize(parsed.body.textContent).indexOf(text);
      if (text.length > 0 && titles.includes(text) && position >= 0 && position < 200) {
        heading.remove();
      }
    }

    // Время чтения считаем по абзацам: сноски, таблицы и списки литературы почти никто не читает.
    const paragraphs = Array.from(parsed.body.querySelectorAll("p"))
      .reduce((sum, node) => sum + node.textContent.trim().length, 0);
    const total = article.length || 0;

    return {
      title: article.title || "",
      byline: article.byline || "",
      siteName: article.siteName || "",
      content: parsed.body.innerHTML,
      length: paragraphs > total * 0.3 ? paragraphs : total,
      lang: article.lang || document.documentElement.lang || ""
    };
    """
}
