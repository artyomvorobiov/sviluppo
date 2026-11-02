package app.kvartet

import android.content.Context
import app.kvartet.data.Catalog
import app.kvartet.data.CatalogLoader
import app.kvartet.data.Completion
import app.kvartet.data.DayPlanner
import app.kvartet.data.Format
import app.kvartet.data.Issue
import app.kvartet.data.Item
import app.kvartet.data.SettingsStore
import app.kvartet.data.Streaks
import app.kvartet.data.UserState
import app.kvartet.data.UserStore
import app.kvartet.media.MediaResolver
import app.kvartet.widget.Widgets
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.temporal.ChronoUnit

/** Состояние приложения: каталог, отметки, настройки. Общее для экранов и виджетов. */
object Kvartet {
    lateinit var catalog: Catalog
        private set
    lateinit var store: UserStore
        private set
    lateinit var settings: SettingsStore
        private set
    lateinit var media: MediaResolver
        private set

    private lateinit var appContext: Context
    private val itemsById = mutableMapOf<String, Item>()
    private val issueByItemId = mutableMapOf<String, Issue>()

    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    private val _today = MutableStateFlow(LocalDate.now())
    /** «Сегодня» — обновляется при возвращении в приложение. */
    val today: StateFlow<LocalDate> = _today.asStateFlow()

    @Volatile private var initialized = false

    fun init(context: Context) {
        if (initialized) return
        synchronized(this) {
            if (initialized) return
            appContext = context.applicationContext
            catalog = CatalogLoader.load(appContext)
            catalog.issues.forEach { issue ->
                issue.items.forEach {
                    itemsById[it.id] = it
                    issueByItemId[it.id] = issue
                }
            }
            store = UserStore(appContext)
            settings = SettingsStore(appContext)
            media = MediaResolver(appContext)
            store.ensureStartDay()
            initialized = true
        }
    }

    // region Дни и выпуски

    val startDay: LocalDate
        get() = store.state.value.startDay?.let { runCatching { LocalDate.parse(it) }.getOrNull() } ?: LocalDate.now()

    fun issueFor(date: LocalDate): Issue = DayPlanner(catalog, startDay).issueFor(date)

    /** Номер выпуска для подписи «№ 12». */
    fun issueNumber(date: LocalDate): Int = ChronoUnit.DAYS.between(startDay, date).toInt() + 1

    fun item(id: String): Item? = itemsById[id]

    fun issueContaining(item: Item): Issue? = issueByItemId[item.id]

    /** Рекомендации выпуска с учётом выбранных типов. */
    fun visibleItems(issue: Issue): List<Item> {
        val kinds = settings.state.value.enabledKinds
        return issue.items.filter { it.kind in kinds }.sortedBy { it.kind.ordinal }
    }

    /** Все дни от сегодняшнего до первого. */
    fun archiveDays(): List<LocalDate> {
        val today = today.value
        val count = maxOf(0, ChronoUnit.DAYS.between(startDay, today).toInt())
        return (0..count).map { today.minusDays(it.toLong()) }
    }

    fun refreshDay() {
        val now = LocalDate.now()
        if (now != _today.value) {
            _today.value = now
            Widgets.updateAll(appContext)
        }
        prefetchUpcomingArtwork()
    }

    // endregion

    // region Отметки

    fun completion(state: UserState, id: String): Completion? = state.completions[id]

    fun markDone(item: Item, rating: Int?, note: String?) {
        val trimmed = note?.trim()?.takeIf { it.isNotEmpty() }
        store.update { state ->
            val completion = (state.completions[item.id] ?: Completion(System.currentTimeMillis()))
                .copy(rating = rating, note = trimmed)
            state.copy(completions = state.completions + (item.id to completion), bookmarks = state.bookmarks - item.id)
        }
        changed()
    }

    fun unmark(item: Item) {
        store.update { it.copy(completions = it.completions - item.id) }
        changed()
    }

    fun toggleDone(id: String) {
        val item = item(id) ?: return
        if (store.state.value.completions.containsKey(id)) unmark(item) else markDone(item, null, null)
    }

    fun toggleBookmark(item: Item) {
        store.update { state ->
            val bookmarks = if (state.bookmarks.containsKey(item.id)) state.bookmarks - item.id
            else state.bookmarks + (item.id to System.currentTimeMillis())
            state.copy(bookmarks = bookmarks)
        }
    }

    /** Начать заново: отметки стираются, выпуски снова идут с первого. */
    fun resetProgress() {
        store.update { UserState(startDay = LocalDate.now().toString()) }
        changed()
    }

    private fun changed() {
        Widgets.updateAll(appContext)
    }

    // endregion

    // region Дневник

    data class JournalEntry(val item: Item, val completion: Completion)

    fun journalEntries(state: UserState): List<JournalEntry> = state.completions
        .mapNotNull { (id, completion) -> item(id)?.let { JournalEntry(it, completion) } }
        .sortedByDescending { it.completion.date }

    fun currentStreak(state: UserState): Int =
        Streaks.current(state.completions.values.map { Format.dateOf(it.date) }, today.value)

    fun bestStreak(state: UserState): Int =
        Streaks.best(state.completions.values.map { Format.dateOf(it.date) })

    /** Дневник в Markdown — для экспорта. */
    fun journalMarkdown(state: UserState): String {
        val lines = mutableListOf("# Дневник «Квартета»", "")
        var currentMonth = ""
        val entries = journalEntries(state)
        for (entry in entries) {
            val date = Format.dateOf(entry.completion.date)
            val month = Format.monthYear(date)
            if (month != currentMonth) {
                currentMonth = month
                lines += "## $month"
                lines += ""
            }
            val item = entry.item
            var line = "- ${Format.dayMonth(date)} — ${item.kind.title}: «${item.title}», ${item.metaLine}"
            entry.completion.rating?.let { line += " " + "★".repeat(it) + "☆".repeat(maxOf(0, 5 - it)) }
            lines += line
            entry.completion.note?.let { lines += "  > ${it.replace('\n', ' ')}" }
        }
        if (entries.isEmpty()) lines += "Пока пусто."
        return lines.joinToString("\n")
    }

    // endregion

    /** Заранее находим и скачиваем изображения на сегодня и завтра — для виджета и работы без сети. */
    private fun prefetchUpcomingArtwork() {
        val today = today.value
        scope.launch {
            Artwork.prefetch(appContext, issueFor(today).items)
            delay(20_000)
            Artwork.prefetch(appContext, issueFor(today.plusDays(1)).items)
            Widgets.updateAll(appContext)
        }
    }
}
