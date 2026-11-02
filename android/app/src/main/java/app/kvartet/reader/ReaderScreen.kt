package app.kvartet.reader

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.view.ViewGroup
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import app.kvartet.Kvartet
import app.kvartet.data.Item
import app.kvartet.data.KvartetJson
import app.kvartet.data.ReaderTheme
import app.kvartet.ui.CompletionDialog
import app.kvartet.ui.Palette
import app.kvartet.ui.TopBar
import app.kvartet.ui.color
import app.kvartet.ui.openInApp
import app.kvartet.ui.shareText
import kotlinx.coroutines.delay
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.serializer
import java.io.File

/** Статья, очищенная Readability.js (сохраняется для чтения без сети). */
@Serializable
data class ParsedArticle(
    val title: String = "",
    val byline: String = "",
    val siteName: String = "",
    val content: String,
    val length: Int = 0,
    val lang: String = "",
)

object ArticleCache {
    private fun file(context: Context, id: String) = File(File(context.filesDir, "articles").apply { mkdirs() }, "$id.json")

    fun load(context: Context, id: String): ParsedArticle? = try {
        file(context, id).takeIf { it.exists() }?.let { KvartetJson.decodeFromString(ParsedArticle.serializer(), it.readText()) }
    } catch (e: Exception) {
        null
    }

    fun save(context: Context, id: String, article: ParsedArticle) {
        runCatching { file(context, id).writeText(KvartetJson.encodeToString(ParsedArticle.serializer(), article)) }
    }

    fun clearAll(context: Context) {
        File(context.filesDir, "articles").deleteRecursively()
    }
}

private enum class Phase { FETCHING, READER, ORIGINAL, FAILED }

/** Читалка: загружает страницу, извлекает текст Readability.js и показывает его в аккуратной вёрстке. */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun ReaderScreen(item: Item, onBack: () -> Unit) {
    val context = LocalContext.current
    val settings by Kvartet.settings.state.collectAsState()
    val state by Kvartet.store.state.collectAsState()
    val dark = isSystemInDarkTheme()
    var phase by remember { mutableStateOf(Phase.FETCHING) }
    var article by remember { mutableStateOf(ArticleCache.load(context, item.id)) }
    var progress by remember { mutableFloatStateOf(0f) }
    var menu by remember { mutableStateOf(false) }
    var showCompletion by remember { mutableStateOf(false) }
    var showOriginal by remember { mutableStateOf(false) }
    val url = item.url

    val webView = remember {
        WebView(context).apply {
            layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            setBackgroundColor(android.graphics.Color.TRANSPARENT)
        }
    }
    DisposableEffect(Unit) { onDispose { webView.destroy() } }

    val themeClass = when (settings.readerTheme) {
        ReaderTheme.AUTO -> if (dark) "dark" else "light"
        ReaderTheme.LIGHT -> "light"
        ReaderTheme.SEPIA -> "sepia"
        ReaderTheme.DARK -> "dark"
    }

    fun render(parsed: ParsedArticle) {
        val minutes = maxOf(1, Math.round(parsed.length / 1300.0).toInt())
        val html = ReaderTemplate.html(parsed, item, themeClass, minutes, plainLinks = item.isWikipediaArticle)
        webView.settings.javaScriptEnabled = false
        webView.loadDataWithBaseURL(url, html, "text/html", "utf-8", null)
        phase = Phase.READER
    }

    fun parse() {
        if (phase != Phase.FETCHING) return
        val readability = context.assets.open("Readability.js").bufferedReader().use { it.readText() }
        val script = context.assets.open("reader-parse.js").bufferedReader().use { it.readText() }
        val title = KvartetJson.encodeToString(String.serializer(), item.title)
        webView.evaluateJavascript(readability + "\n" + script, null)
        webView.evaluateJavascript("kvartetParse($title, ${item.isWikipediaArticle})") { value ->
            if (phase != Phase.FETCHING) return@evaluateJavascript
            val parsed = runCatching {
                val json = KvartetJson.decodeFromString(String.serializer(), value)
                KvartetJson.decodeFromString(ParsedArticle.serializer(), json)
            }.getOrNull()
            if (parsed != null && parsed.content.isNotBlank()) {
                ArticleCache.save(context, item.id, parsed)
                article = parsed
                render(parsed)
            } else {
                // Не получилось — показываем страницу как есть, она уже загружена.
                phase = Phase.ORIGINAL
            }
        }
    }

    LaunchedEffect(item.id) {
        webView.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) {
                progress = 0f
            }

            override fun onPageFinished(view: WebView, url: String?) {
                if (phase == Phase.FETCHING) parse()
            }

            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                if (phase == Phase.FETCHING || showOriginal) return false
                if (request.url.fragment != null && request.url.toString().startsWith(url.orEmpty())) return false
                openInApp(context, request.url.toString())
                return true
            }
        }
        webView.setOnScrollChangeListener { view, _, scrollY, _, _ ->
            val web = view as WebView
            val max = web.contentHeight * web.resources.displayMetrics.density - web.height
            if (max > 1) progress = (scrollY / max).coerceIn(0f, 1f)
        }
        val cached = article
        when {
            cached != null -> render(cached)
            url == null -> phase = Phase.FAILED
            else -> {
                webView.loadUrl(url)
                // Страница грузится слишком долго (реклама, счётчики) — пробуем извлечь то, что есть.
                delay(15_000)
                if (phase == Phase.FETCHING) parse()
            }
        }
    }

    LaunchedEffect(settings.readerTextScale) {
        webView.settings.textZoom = Math.round(settings.readerTextScale * 100)
    }
    LaunchedEffect(themeClass) {
        article?.let { if (phase == Phase.READER && !showOriginal) render(it) }
    }

    Column(Modifier.fillMaxSize()) {
        TopBar(title = item.source ?: article?.siteName, onBack = onBack) {
            Box {
                IconButton(onClick = { menu = true }) { Icon(Icons.Filled.MoreVert, contentDescription = "Настройки чтения") }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    DropdownMenuItem(text = { Text("Крупнее") }, onClick = {
                        Kvartet.settings.update { it.copy(readerTextScale = it.readerTextScale + 0.1f) }
                    })
                    DropdownMenuItem(text = { Text("Мельче") }, onClick = {
                        Kvartet.settings.update { it.copy(readerTextScale = it.readerTextScale - 0.1f) }
                    })
                    HorizontalDivider()
                    ReaderTheme.entries.forEach { theme ->
                        DropdownMenuItem(
                            text = { Text(theme.title) },
                            trailingIcon = { if (settings.readerTheme == theme) Icon(Icons.Filled.Check, null) },
                            onClick = { Kvartet.settings.update { it.copy(readerTheme = theme) } },
                        )
                    }
                    HorizontalDivider()
                    if (article != null && url != null) {
                        DropdownMenuItem(
                            text = { Text(if (showOriginal) "Режим чтения" else "Оригинальная страница") },
                            onClick = {
                                menu = false
                                if (showOriginal) {
                                    showOriginal = false
                                    article?.let { render(it) }
                                } else {
                                    showOriginal = true
                                    webView.settings.javaScriptEnabled = true
                                    webView.loadUrl(url)
                                }
                            },
                        )
                    }
                    url?.let { link ->
                        DropdownMenuItem(text = { Text("Поделиться") }, onClick = {
                            menu = false
                            shareText(context, "«${item.title}»\n$link")
                        })
                        DropdownMenuItem(text = { Text("Открыть в браузере") }, onClick = {
                            menu = false
                            openInApp(context, link)
                        })
                    }
                }
            }
        }
        if (phase == Phase.READER) {
            LinearProgressIndicator(
                progress = { progress },
                modifier = Modifier.fillMaxWidth().height(2.dp),
                color = item.kind.color,
                trackColor = Color.Transparent,
            )
        }
        Box(Modifier.fillMaxSize()) {
            AndroidView(factory = { webView }, modifier = Modifier.fillMaxSize())
            when (phase) {
                Phase.FETCHING -> Column(
                    Modifier.fillMaxSize().padding(32.dp),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    CircularProgressIndicator(color = item.kind.color)
                    Spacer(Modifier.height(16.dp))
                    Text("Готовим статью для чтения…", color = Palette.muted)
                }
                Phase.FAILED -> Column(
                    Modifier.fillMaxSize().padding(32.dp),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text("Не удалось загрузить статью", textAlign = TextAlign.Center)
                    Spacer(Modifier.height(8.dp))
                    Text("Проверьте подключение к интернету и попробуйте ещё раз.", color = Palette.muted, textAlign = TextAlign.Center)
                }
                else -> Unit
            }
            val done = state.completions.containsKey(item.id)
            if (phase == Phase.READER && !showOriginal && progress > 0.85f && !done) {
                ExtendedFloatingActionButton(
                    onClick = { showCompletion = true },
                    icon = { Icon(Icons.Filled.Check, null) },
                    text = { Text("Прочитано") },
                    containerColor = item.kind.color,
                    contentColor = Color.White,
                    modifier = Modifier.align(Alignment.BottomCenter).padding(24.dp),
                )
            }
        }
    }

    if (showCompletion) CompletionDialog(item, onDismiss = { showCompletion = false })
}

/** HTML-вёрстка режима чтения (та же, что в iOS-версии). */
object ReaderTemplate {
    fun html(article: ParsedArticle, item: Item, theme: String, minutes: Int, plainLinks: Boolean): String {
        val site = item.source ?: article.siteName.ifBlank { null }
        val lower = article.byline.lowercase()
        val byline = article.byline.takeIf {
            it.isNotBlank() && listOf("wikimedia", "wikipedia", "викимеди", "википеди").none { word -> lower.contains(word) }
        }
        val meta = listOfNotNull(site, byline, "$minutes мин чтения").joinToString(" · ") { escape(it) }
        val classes = "theme-$theme" + if (plainLinks) " plain-links" else ""
        return """
            <!doctype html>
            <html lang="${escape(article.lang.ifBlank { "ru" })}">
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>$CSS</style>
            </head>
            <body class="$classes">
            <main class="reader">
            <p class="meta">$meta</p>
            <h1 class="title">${escape(item.title)}</h1>
            <div class="content">${article.content}</div>
            <p class="end">❦</p>
            </main>
            </body>
            </html>
        """.trimIndent()
    }

    private fun escape(text: String) = text
        .replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")

    private const val CSS = """
        body {
          --bg: #FAF8F4; --fg: #1C1B1A; --muted: #6F6A62; --link: #8A5A12; --rule: rgba(0,0,0,.10); --code: rgba(0,0,0,.05);
          margin: 0; background: var(--bg); color: var(--fg);
          font: 19px/1.62 "Noto Serif", Georgia, serif;
          -webkit-text-size-adjust: 100%; hyphens: auto; overflow-wrap: break-word;
        }
        body.theme-sepia { --bg: #F4ECD8; --fg: #3B2F22; --muted: #7A6A55; --link: #8B4513; --rule: rgba(59,47,34,.15); --code: rgba(59,47,34,.07); }
        body.theme-dark { --bg: #111113; --fg: #E8E5DF; --muted: #9C988F; --link: #E3B35A; --rule: rgba(255,255,255,.12); --code: rgba(255,255,255,.07); }
        .reader { max-width: 680px; margin: 0 auto; padding: 16px 22px 120px; }
        .meta { margin: 8px 0 0; color: var(--muted); font: 600 12px/1.4 sans-serif; letter-spacing: .08em; text-transform: uppercase; }
        .title { font: 700 30px/1.2 "Noto Serif", Georgia, serif; margin: 10px 0 24px; hyphens: manual; }
        h2, h3, h4 { font-family: "Noto Serif", Georgia, serif; line-height: 1.25; margin: 1.6em 0 .5em; }
        h2 { font-size: 24px; } h3 { font-size: 20px; } h4 { font-size: 18px; }
        p { margin: 0 0 1em; }
        a { color: var(--link); text-decoration-thickness: 1px; text-underline-offset: 3px; }
        .plain-links a { color: inherit; text-decoration: none; pointer-events: none; }
        img, video, svg, canvas, iframe { max-width: 100% !important; height: auto !important; }
        img { display: block; margin: 18px auto; border-radius: 6px; }
        figure { margin: 24px 0; }
        figcaption, .caption { color: var(--muted); font: 14px/1.45 sans-serif; margin-top: 6px; }
        blockquote { margin: 20px 0; padding: 2px 0 2px 18px; border-left: 3px solid var(--rule); color: var(--muted); font-style: italic; }
        ul, ol { padding-left: 1.3em; }
        li { margin: .3em 0; }
        hr { border: 0; border-top: 1px solid var(--rule); margin: 32px 0; }
        table { display: block; overflow-x: auto; border-collapse: collapse; font: 15px/1.4 sans-serif; margin: 20px 0; }
        th, td { border: 1px solid var(--rule); padding: 6px 8px; vertical-align: top; }
        pre, code { font: 15px/1.45 monospace; background: var(--code); border-radius: 4px; }
        pre { padding: 12px; overflow-x: auto; white-space: pre-wrap; }
        sup { line-height: 0; }
        .end { text-align: center; color: var(--muted); margin-top: 48px; font-size: 22px; }
    """
}
