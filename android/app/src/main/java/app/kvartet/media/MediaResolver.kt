package app.kvartet.media

import android.content.Context
import android.net.Uri
import android.util.Log
import app.kvartet.data.Item
import app.kvartet.data.ItemKind
import app.kvartet.data.KvartetJson
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.text.Normalizer

const val USER_AGENT = "Kvartet/1.0 (Android app; https://github.com/artyomvorobiov/sviluppo)"

/**
 * Находит изображения и фрагменты без ключей API — так же, как iOS-версия:
 * картины — свободные изображения Википедии; альбомы и фильмы — iTunes Search API,
 * а если там не нашлось — обложка или постер из статьи Википедии.
 */
class MediaResolver(context: Context) {

    private sealed interface Lookup {
        data class Found(val value: String) : Lookup
        data class NotFound(val retryAfterMs: Long) : Lookup
        data object Failed : Lookup
    }

    @Serializable
    private data class Entry(val value: String? = null, val date: Long, val retryAt: Long? = null)

    @Serializable
    private data class ITunesItem(
        val kind: String? = null,
        val artistName: String? = null,
        val collectionName: String? = null,
        val trackName: String? = null,
        val artworkUrl100: String? = null,
        val previewUrl: String? = null,
        val releaseDate: String? = null,
    )

    @Serializable
    private data class ITunesResponse(val results: List<ITunesItem> = emptyList())

    private sealed interface Match {
        data class Found(val item: ITunesItem) : Match
        data object NotFound : Match
        data object Empty : Match
        data object Failed : Match
    }

    private data class WikiInfo(val image: String? = null, val ruUrl: String? = null)

    private val file = File(context.filesDir, "media-cache.json")
    private val entrySerializer = MapSerializer(String.serializer(), Entry.serializer())
    private val cache: MutableMap<String, Entry> = read()
    private val mutex = Mutex()
    private val inFlight = mutableMapOf<String, Deferred<Lookup>>()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val iTunesGate = RequestGate(spacingMs = 1_000, pauseMs = 90_000)

    // region Публичный интерфейс

    /** Обложка, постер или изображение картины. */
    suspend fun artworkUrl(item: Item): String? {
        item.image?.let { return it }
        return resolve(artKey(item)) { findArtwork(item) }
    }

    /** Ключ кэша включает статью Википедии: если в каталоге её исправили, картинка ищется заново. */
    private fun artKey(item: Item) = "${item.id}|art|${item.wiki.orEmpty()}"

    /** Только из кэша, без сети. */
    fun cachedArtworkUrl(item: Item): String? {
        item.image?.let { return it }
        return synchronized(cache) { cache[artKey(item)]?.value }
    }

    /** Альбом — 30 секунд ключевого трека, фильм — трейлер. */
    suspend fun previewUrl(item: Item): String? {
        if (item.kind != ItemKind.ALBUM && item.kind != ItemKind.FILM) return null
        return resolve(item.id + "|preview") { findPreview(item) }
    }

    /** «Подробнее»: русская статья Википедии, если есть, иначе исходная. */
    suspend fun readMoreUrl(item: Item): String? {
        val wiki = item.wiki ?: return null
        val fallback = item.wikipediaUrl
        if (wiki.startsWith("ru:")) return fallback
        val value = resolve("${item.id}|wiki|$wiki") {
            val info = wikipediaInfo(wiki) ?: return@resolve Lookup.Failed
            info.ruUrl?.let { Lookup.Found(it) } ?: Lookup.NotFound(RETRY_NOT_FOUND)
        }
        return value ?: fallback
    }

    fun clear() {
        synchronized(cache) { cache.clear() }
        file.delete()
    }

    // endregion

    // region Кэш

    private suspend fun resolve(key: String, work: suspend () -> Lookup): String? {
        synchronized(cache) { cache[key] }?.let { entry ->
            if (entry.value != null) return entry.value
            val retryAt = entry.retryAt ?: (entry.date + RETRY_NOT_FOUND)
            if (System.currentTimeMillis() < retryAt) return null
        }
        val task = mutex.withLock {
            inFlight.getOrPut(key) { scope.async { work() } }
        }
        val result = try {
            task.await()
        } finally {
            mutex.withLock { if (inFlight[key] === task) inFlight.remove(key) }
        }
        val now = System.currentTimeMillis()
        return when (result) {
            is Lookup.Found -> {
                save(key, Entry(result.value, now))
                result.value
            }
            is Lookup.NotFound -> {
                save(key, Entry(null, now, now + result.retryAfterMs))
                null
            }
            Lookup.Failed -> null
        }
    }

    private fun read(): MutableMap<String, Entry> = try {
        if (file.exists()) KvartetJson.decodeFromString(entrySerializer, file.readText()).toMutableMap() else mutableMapOf()
    } catch (e: Exception) {
        mutableMapOf()
    }

    private fun save(key: String, entry: Entry) {
        synchronized(cache) {
            cache[key] = entry
            try {
                file.writeText(KvartetJson.encodeToString(entrySerializer, cache))
            } catch (e: Exception) {
                Log.w(TAG, "Cannot save media cache", e)
            }
        }
    }

    // endregion

    // region Поиск

    private suspend fun findArtwork(item: Item): Lookup {
        var failed = false
        var retryAfter = RETRY_NOT_FOUND
        val match = when (item.kind) {
            ItemKind.ALBUM -> iTunesAlbum(item)
            ItemKind.FILM -> iTunesMovie(item)
            ItemKind.PAINTING, ItemKind.ARTICLE -> null
        }
        when (match) {
            is Match.Found -> match.item.artworkUrl100?.let { return Lookup.Found(upscaled(it)) }
            Match.Empty -> retryAfter = RETRY_EMPTY
            Match.Failed -> failed = true
            Match.NotFound, null -> Unit
        }
        item.wiki?.let { wiki ->
            // Обложки и постеры в Википедии — несвободные файлы, их просим отдельно.
            val anyLicense = item.kind == ItemKind.ALBUM || item.kind == ItemKind.FILM
            val info = wikipediaInfo(wiki, anyLicense) ?: return Lookup.Failed
            info.image?.let { return Lookup.Found(it) }
        }
        return if (failed) Lookup.Failed else Lookup.NotFound(retryAfter)
    }

    private suspend fun findPreview(item: Item): Lookup = when (item.kind) {
        ItemKind.FILM -> when (val match = iTunesMovie(item)) {
            is Match.Found -> match.item.previewUrl?.let { Lookup.Found(it) } ?: Lookup.NotFound(RETRY_NOT_FOUND)
            Match.NotFound -> Lookup.NotFound(RETRY_NOT_FOUND)
            Match.Empty -> Lookup.NotFound(RETRY_EMPTY)
            Match.Failed -> Lookup.Failed
        }
        ItemKind.ALBUM -> iTunesSongPreview(item)
        else -> Lookup.NotFound(RETRY_NOT_FOUND)
    }

    private fun countries(item: Item) = if (item.isRussianWork) listOf("ru", "us") else listOf("us")

    private fun artists(item: Item) = listOfNotNull(item.originalCreator, item.creator)

    private fun titles(item: Item): List<String> {
        val titles = listOfNotNull(item.originalTitle, item.title).toMutableList()
        // У фильмов в поле search — международное название для iTunes.
        if (item.kind == ItemKind.FILM) item.search?.let { titles.add(0, it) }
        return titles
    }

    /** Итог нескольких поисков без совпадения: сбой, пустые ответы или просто не нашли. */
    private class Outcome {
        private var failed = false
        private var sawResults = false

        fun <T> record(results: List<T>?): List<T>? {
            if (results == null) failed = true else if (results.isNotEmpty()) sawResults = true
            return results
        }

        val miss: Match
            get() = when {
                failed -> Match.Failed
                sawResults -> Match.NotFound
                else -> Match.Empty
            }
    }

    private suspend fun iTunesAlbum(item: Item): Match {
        val artists = artists(item)
        val titles = titles(item)
        val outcome = Outcome()
        for (country in countries(item)) {
            val albums = outcome.record(iTunesSearch("${artists[0]} ${titles[0]}", "music", "album", country))
            albums?.firstOrNull { result ->
                artists.any { Matching.sameArtist(it, result.artistName) } &&
                    titles.any { Matching.sameTitle(it, result.collectionName) }
            }?.let { return Match.Found(it) }
            // Поиск альбомов находит не всё, а песня с альбома находится — и у неё та же обложка.
            val track = item.keyTrack ?: continue
            val songs = outcome.record(iTunesSearch("${artists[0]} $track", "music", "song", country))
            songs?.firstOrNull { result ->
                artists.any { Matching.sameArtist(it, result.artistName) } &&
                    titles.any { Matching.sameTitle(it, result.collectionName) }
            }?.let { return Match.Found(it) }
        }
        return outcome.miss
    }

    private suspend fun iTunesMovie(item: Item): Match {
        val titles = titles(item)
        val outcome = Outcome()
        for (country in countries(item)) {
            // В американском iTunes нет смысла искать по-русски или по-японски.
            for (title in titles.filter { country != "us" || Matching.isLatin(it) }) {
                // Поиск с media=movie сейчас ничего не находит — ищем по всему магазину.
                val results = outcome.record(iTunesSearch(title, null, null, country, limit = 50))
                results?.firstOrNull { result ->
                    result.kind == "feature-movie" &&
                        titles.any { Matching.sameTitle(it, result.trackName) } &&
                        Matching.isYear(item.yearValue, result.releaseDate)
                }?.let { return Match.Found(it) }
            }
        }
        return outcome.miss
    }

    private suspend fun iTunesSongPreview(item: Item): Lookup {
        val track = item.keyTrack ?: return Lookup.NotFound(RETRY_NOT_FOUND)
        val artists = artists(item)
        val outcome = Outcome()
        for (country in countries(item)) {
            val results = outcome.record(iTunesSearch("${artists[0]} $track", "music", "song", country))
            results?.firstOrNull { result ->
                result.previewUrl != null &&
                    artists.any { Matching.sameArtist(it, result.artistName) } &&
                    Matching.sameTitle(track, result.trackName)
            }?.previewUrl?.let { return Lookup.Found(it) }
        }
        return when (outcome.miss) {
            Match.Failed -> Lookup.Failed
            Match.Empty -> Lookup.NotFound(RETRY_EMPTY)
            else -> Lookup.NotFound(RETRY_NOT_FOUND)
        }
    }

    /** null — ошибка сети. */
    private suspend fun iTunesSearch(
        term: String,
        media: String?,
        entity: String?,
        country: String,
        limit: Int = 25,
    ): List<ITunesItem>? {
        val builder = Uri.parse("https://itunes.apple.com/search").buildUpon()
            .appendQueryParameter("term", term)
            .appendQueryParameter("country", country)
            .appendQueryParameter("limit", limit.toString())
        media?.let { builder.appendQueryParameter("media", it) }
        entity?.let { builder.appendQueryParameter("entity", it) }
        val text = get(builder.build().toString(), iTunesGate) ?: return null
        val results = try {
            KvartetJson.decodeFromString(ITunesResponse.serializer(), text).results
        } catch (e: Exception) {
            emptyList()
        }
        if (results.isEmpty()) Log.i(TAG, "iTunes: nothing for «$term» (${entity ?: "all"}, $country)")
        return results
    }

    private fun upscaled(url: String) = url.replace("100x100bb", "1200x1200bb")

    /** `wiki` в формате "en:The_Hunters_in_the_Snow". null — ошибка сети. */
    private suspend fun wikipediaInfo(wiki: String, anyLicense: Boolean = false): WikiInfo? {
        val parts = wiki.split(":", limit = 2)
        if (parts.size != 2) return WikiInfo()
        val builder = Uri.parse("https://${parts[0]}.wikipedia.org/w/api.php").buildUpon()
            .appendQueryParameter("action", "query")
            .appendQueryParameter("format", "json")
            .appendQueryParameter("formatversion", "2")
            .appendQueryParameter("redirects", "1")
            .appendQueryParameter("prop", "pageimages|langlinks|info")
            .appendQueryParameter("piprop", "thumbnail")
            .appendQueryParameter("pithumbsize", "1600")
            .appendQueryParameter("lllang", "ru")
            .appendQueryParameter("llprop", "url")
            .appendQueryParameter("inprop", "url")
            .appendQueryParameter("titles", parts[1].replace('_', ' '))
        if (anyLicense) builder.appendQueryParameter("pilicense", "any")
        val text = get(builder.build().toString()) ?: return null
        return try {
            val page = KvartetJson.parseToJsonElement(text).jsonObject["query"]?.jsonObject
                ?.get("pages")?.jsonArray?.firstOrNull()?.jsonObject ?: return WikiInfo()
            if (page["missing"] != null) return WikiInfo()
            val image = (page["thumbnail"] as? JsonObject)?.get("source")?.jsonPrimitive?.content
            val fullUrl = page["fullurl"]?.jsonPrimitive?.content
            val ruUrl = if (parts[0] == "ru") fullUrl else (page["langlinks"] as? JsonArray)
                ?.map { it.jsonObject }
                ?.firstOrNull { it["lang"]?.jsonPrimitive?.content == "ru" }
                ?.get("url")?.jsonPrimitive?.content
            WikiInfo(image, ruUrl)
        } catch (e: Exception) {
            WikiInfo()
        }
    }

    // endregion

    private suspend fun get(url: String, gate: RequestGate? = null): String? = withContext(Dispatchers.IO) {
        if (gate != null && !gate.enter()) return@withContext null
        try {
            val connection = URL(url).openConnection() as HttpURLConnection
            connection.connectTimeout = 12_000
            connection.readTimeout = 15_000
            connection.setRequestProperty("User-Agent", USER_AGENT)
            val code = connection.responseCode
            if (code != 200) {
                Log.w(TAG, "HTTP $code for $url")
                if (code == 403 || code == 429) gate?.pause()
                connection.disconnect()
                return@withContext null
            }
            connection.inputStream.bufferedReader().use { it.readText() }
        } catch (e: Exception) {
            Log.w(TAG, "${e.message} for $url")
            null
        }
    }

    private companion object {
        const val TAG = "Kvartet"
        /** Через сколько повторять поиск, если подходящего результата не нашлось. */
        const val RETRY_NOT_FOUND = 3L * 24 * 3600 * 1000
        /** …и если iTunes вернул пустой список. */
        const val RETRY_EMPTY = 20L * 60 * 1000
    }
}

/** Запросы не чаще одного в `spacingMs`, а после отказа (403/429) сервис какое-то время не беспокоим. */
class RequestGate(private val spacingMs: Long, private val pauseMs: Long) {
    private val mutex = Mutex()
    private var nextSlot = 0L
    @Volatile private var pausedUntil = 0L

    suspend fun enter(): Boolean {
        var wait = 0L
        val now = System.currentTimeMillis()
        if (now < pausedUntil) return false
        mutex.withLock {
            val slot = maxOf(now, nextSlot)
            nextSlot = slot + spacingMs
            wait = slot - now
        }
        if (wait > 0) delay(wait)
        return System.currentTimeMillis() >= pausedUntil
    }

    fun pause() {
        pausedUntil = System.currentTimeMillis() + pauseMs
    }
}

/** Нестрогое сравнение названий и имён из разных источников. */
object Matching {
    fun normalize(text: String): String {
        var value = Normalizer.normalize(text, Normalizer.Form.NFD).replace(Regex("\\p{M}+"), "")
        value = value.lowercase().replace('ё', 'е').replace("&", " and ")
        // «(Remastered)», «[Deluxe Edition]», «(1996)»
        value = value.replace(Regex("\\s*[(\\[][^)\\]]*[)\\]]"), " ")
        return value.map { if (it.isLetterOrDigit()) it else ' ' }.joinToString("")
            .split(' ').filter { it.isNotEmpty() }.joinToString(" ")
    }

    fun sameTitle(expected: String, candidate: String?): Boolean {
        candidate ?: return false
        val a = normalize(expected)
        val b = normalize(candidate)
        if (a.isEmpty() || b.isEmpty()) return false
        return a == b || b.startsWith("$a ") || a.startsWith("$b ")
    }

    fun sameArtist(expected: String, candidate: String?): Boolean {
        candidate ?: return false
        val a = normalize(expected)
        val b = normalize(candidate)
        if (a.isEmpty() || b.isEmpty()) return false
        return a == b || b.contains(a) || a.contains(b)
    }

    fun isYear(year: Int?, releaseDate: String?, tolerance: Int = 2): Boolean {
        year ?: return false
        val released = releaseDate?.take(4)?.toIntOrNull() ?: return false
        return kotlin.math.abs(released - year) <= tolerance
    }

    /** Название латиницей (в том числе с диакритикой). */
    fun isLatin(text: String): Boolean = text.all { !it.isLetter() || it.code < 0x0250 }
}
