import Foundation

/// HTML-вёрстка режима чтения.
enum ReaderTemplate {
    static func html(article: ParsedArticle, item: Item?, theme: ReaderTheme, minutes: Int?) -> String {
        // Название из каталога аккуратнее, чем <title> страницы («… — Википедия»).
        let title = escape(item?.title ?? article.title)
        var meta: [String] = []
        if let site = article.siteName(for: item) { meta.append(escape(site)) }
        if let byline = article.author { meta.append(escape(byline)) }
        if let minutes { meta.append("\(minutes) мин чтения") }
        let lang = escape(article.lang ?? "ru")

        return """
        <!doctype html>
        <html lang="\(lang)">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <meta name="color-scheme" content="light dark">
        <style>\(css)</style>
        </head>
        <body class="theme-\(theme.rawValue)">
        <main class="reader">
        <p class="meta">\(meta.joined(separator: " · "))</p>
        <h1 class="title">\(title)</h1>
        <div class="content">\(article.content)</div>
        <p class="end">❦</p>
        </main>
        </body>
        </html>
        """
    }

    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static let css = """
    :root { color-scheme: light dark; }
    body {
      --bg: #FAF8F4; --fg: #1C1B1A; --muted: #6F6A62; --link: #8A5A12; --rule: rgba(0,0,0,.10); --code: rgba(0,0,0,.05);
      margin: 0; background: var(--bg); color: var(--fg);
      font: 19px/1.62 ui-serif, "New York", Georgia, serif;
      -webkit-text-size-adjust: 100%; text-rendering: optimizeLegibility;
      -webkit-hyphens: auto; hyphens: auto; overflow-wrap: break-word;
    }
    body.theme-sepia { --bg: #F4ECD8; --fg: #3B2F22; --muted: #7A6A55; --link: #8B4513; --rule: rgba(59,47,34,.15); --code: rgba(59,47,34,.07); }
    body.theme-dark { --bg: #111113; --fg: #E8E5DF; --muted: #9C988F; --link: #E3B35A; --rule: rgba(255,255,255,.12); --code: rgba(255,255,255,.07); }
    @media (prefers-color-scheme: dark) {
      body.theme-auto { --bg: #111113; --fg: #E8E5DF; --muted: #9C988F; --link: #E3B35A; --rule: rgba(255,255,255,.12); --code: rgba(255,255,255,.07); }
    }
    .reader { max-width: 680px; margin: 0 auto; padding: 20px 22px 96px; }
    .meta { margin: 8px 0 0; color: var(--muted); font: 600 12px/1.4 -apple-system, system-ui, sans-serif; letter-spacing: .08em; text-transform: uppercase; }
    .title { font: 700 30px/1.2 ui-serif, "New York", Georgia, serif; margin: 10px 0 24px; -webkit-hyphens: manual; hyphens: manual; }
    h2, h3, h4 { font-family: ui-serif, "New York", Georgia, serif; line-height: 1.25; margin: 1.6em 0 .5em; }
    h2 { font-size: 24px; } h3 { font-size: 20px; } h4 { font-size: 18px; }
    p { margin: 0 0 1em; }
    a { color: var(--link); text-decoration-thickness: 1px; text-underline-offset: 3px; }
    img, video, svg, canvas, iframe { max-width: 100% !important; height: auto !important; }
    img { display: block; margin: 18px auto; border-radius: 6px; }
    figure { margin: 24px 0; }
    figcaption, .caption { color: var(--muted); font: 14px/1.45 -apple-system, system-ui, sans-serif; margin-top: 6px; }
    blockquote { margin: 20px 0; padding: 2px 0 2px 18px; border-left: 3px solid var(--rule); color: var(--muted); font-style: italic; }
    ul, ol { padding-left: 1.3em; }
    li { margin: .3em 0; }
    hr { border: 0; border-top: 1px solid var(--rule); margin: 32px 0; }
    table { display: block; overflow-x: auto; border-collapse: collapse; font: 15px/1.4 -apple-system, system-ui, sans-serif; margin: 20px 0; }
    th, td { border: 1px solid var(--rule); padding: 6px 8px; vertical-align: top; }
    pre, code { font: 15px/1.45 ui-monospace, Menlo, monospace; background: var(--code); border-radius: 4px; }
    pre { padding: 12px; overflow-x: auto; white-space: pre-wrap; }
    sup { line-height: 0; }
    .end { text-align: center; color: var(--muted); margin-top: 48px; font-size: 22px; }
    """
}
