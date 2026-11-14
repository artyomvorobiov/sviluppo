package app.kvartet.data

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File
import java.time.LocalDate
import java.time.temporal.ChronoUnit

val KvartetJson = Json {
    ignoreUnknownKeys = true
    encodeDefaults = true
}

/**
 * Каталог выпусков: встроенный (assets/catalog.json — тот же файл, что и в iOS-версии)
 * или скачанный с [REMOTE_URL], если он не старше встроенного.
 */
object CatalogLoader {
    const val REMOTE_URL = "https://raw.githubusercontent.com/artyomvorobiov/kvartet-catalog/main/catalog.json"
    private const val REMOTE_FILE = "catalog-remote.json"

    fun load(context: Context): Catalog {
        val bundled = decode(context.assets.open("catalog.json").bufferedReader().use { it.readText() })
            ?: Catalog(SUPPORTED_SCHEMA, null, emptyList())
        val remote = runCatching { File(context.filesDir, REMOTE_FILE).readText() }.getOrNull()?.let(::decode)
        return if (remote != null && (remote.updated ?: "") >= (bundled.updated ?: "")) remote else bundled
    }

    /**
     * Скачивает удалённый каталог. Новые выпуски появятся при следующем запуске приложения.
     * Возвращает true, если файл изменился.
     */
    fun refreshRemote(context: Context, userAgent: String): Boolean {
        val text = try {
            val connection = java.net.URL(REMOTE_URL).openConnection() as java.net.HttpURLConnection
            connection.connectTimeout = 15_000
            connection.readTimeout = 20_000
            connection.useCaches = false
            connection.setRequestProperty("User-Agent", userAgent)
            if (connection.responseCode != 200) {
                connection.disconnect()
                return false
            }
            connection.inputStream.bufferedReader().use { it.readText() }
        } catch (e: Exception) {
            return false
        }
        if (decode(text) == null) return false
        val file = File(context.filesDir, REMOTE_FILE)
        if (file.exists() && file.readText() == text) return false
        val temp = File(context.filesDir, "$REMOTE_FILE.tmp")
        temp.writeText(text)
        return temp.renameTo(file)
    }

    private fun decode(text: String): Catalog? = runCatching {
        KvartetJson.decodeFromString(Catalog.serializer(), text)
    }.getOrNull()?.takeIf { it.schemaVersion <= SUPPORTED_SCHEMA && it.issues.isNotEmpty() }

    private const val SUPPORTED_SCHEMA = 1
}

/** Какой выпуск в какой день: № 1 — в день первого запуска, дальше по кругу. */
class DayPlanner(private val catalog: Catalog, private val startDay: LocalDate) {
    private val placeholder = Issue("empty", "Скоро", "Выпуски готовятся.", emptyList())

    fun index(date: LocalDate): Int = maxOf(0, ChronoUnit.DAYS.between(startDay, date).toInt())

    fun issueFor(date: LocalDate): Issue {
        val issues = catalog.issues
        if (issues.isEmpty()) return placeholder
        return issues[index(date) % issues.size]
    }
}

/** Отметки и закладки пользователя. */
class UserStore(context: Context) {
    private val file = File(context.filesDir, "user-state.json")
    private val _state = MutableStateFlow(read())
    val state: StateFlow<UserState> = _state.asStateFlow()

    private fun read(): UserState = try {
        if (file.exists()) KvartetJson.decodeFromString(UserState.serializer(), file.readText()) else UserState()
    } catch (e: Exception) {
        UserState()
    }

    @Synchronized
    fun update(change: (UserState) -> UserState): UserState {
        val updated = change(_state.value)
        val temp = File(file.parentFile, "${file.name}.tmp")
        temp.writeText(KvartetJson.encodeToString(UserState.serializer(), updated))
        temp.renameTo(file)
        _state.value = updated
        return updated
    }

    fun ensureStartDay() {
        if (_state.value.startDay == null) {
            update { it.copy(startDay = LocalDate.now().toString()) }
        }
    }
}

enum class MusicService(val title: String) {
    YANDEX_MUSIC("Яндекс Музыка"),
    APPLE_MUSIC("Apple Music"),
    SPOTIFY("Spotify"),
    YOUTUBE_MUSIC("YouTube Music");

    fun url(item: Item): String {
        val query = item.search ?: "${item.originalCreator ?: item.creator} ${item.originalTitle ?: item.title}"
        val encoded = android.net.Uri.encode(query)
        return when (this) {
            YANDEX_MUSIC -> "https://music.yandex.ru/search?text=$encoded"
            APPLE_MUSIC -> "https://music.apple.com/search?term=$encoded"
            SPOTIFY -> "https://open.spotify.com/search/$encoded"
            YOUTUBE_MUSIC -> "https://music.youtube.com/search?q=$encoded"
        }
    }
}

enum class FilmService(val title: String) {
    KINOPOISK("Кинопоиск"),
    APPLE_TV("Apple TV"),
    IMDB("IMDb"),
    LETTERBOXD("Letterboxd");

    fun url(item: Item): String {
        val year = item.yearValue?.let { " $it" }.orEmpty()
        val original = item.originalTitle ?: item.title
        return when (this) {
            KINOPOISK -> "https://www.kinopoisk.ru/index.php?kp_query=${android.net.Uri.encode(item.title + year)}"
            APPLE_TV -> "https://tv.apple.com/search?term=${android.net.Uri.encode(original)}"
            IMDB -> "https://www.imdb.com/find/?q=${android.net.Uri.encode(original + year)}"
            LETTERBOXD -> "https://letterboxd.com/search/films/${android.net.Uri.encode(original)}/"
        }
    }

    companion object {
        /** Запасной вариант, если трейлера нет в iTunes. */
        fun youTubeTrailerUrl(item: Item): String {
            val year = item.yearValue?.let { " $it" }.orEmpty()
            return "https://www.youtube.com/results?search_query=${android.net.Uri.encode("${item.title}$year трейлер")}"
        }
    }
}

enum class ReaderTheme(val title: String) {
    AUTO("Как в системе"),
    LIGHT("Светлая"),
    SEPIA("Сепия"),
    DARK("Тёмная"),
}

@Serializable
data class Settings(
    val enabledKinds: Set<ItemKind> = ItemKind.entries.toSet(),
    val reminderEnabled: Boolean = false,
    val reminderHour: Int = 9,
    val reminderMinute: Int = 0,
    val musicService: MusicService = MusicService.YANDEX_MUSIC,
    val filmService: FilmService = FilmService.KINOPOISK,
    val readerTheme: ReaderTheme = ReaderTheme.AUTO,
    val readerTextScale: Float = 1f,
    val onboarded: Boolean = false,
)

/** Настройки приложения (общие с виджетами). */
class SettingsStore(context: Context) {
    private val prefs = context.getSharedPreferences("kvartet", Context.MODE_PRIVATE)
    private val _state = MutableStateFlow(read())
    val state: StateFlow<Settings> = _state.asStateFlow()

    private fun read(): Settings = try {
        prefs.getString("settings", null)?.let { KvartetJson.decodeFromString(Settings.serializer(), it) } ?: Settings()
    } catch (e: Exception) {
        Settings()
    }

    @Synchronized
    fun update(change: (Settings) -> Settings) {
        var updated = change(_state.value)
        // Хотя бы один тип всегда остаётся включённым.
        if (updated.enabledKinds.isEmpty()) updated = updated.copy(enabledKinds = _state.value.enabledKinds)
        updated = updated.copy(readerTextScale = updated.readerTextScale.coerceIn(0.8f, 1.6f))
        prefs.edit().putString("settings", KvartetJson.encodeToString(Settings.serializer(), updated)).apply()
        _state.value = updated
    }
}
