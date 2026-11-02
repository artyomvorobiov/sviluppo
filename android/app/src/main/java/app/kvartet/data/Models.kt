package app.kvartet.data

import android.net.Uri
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Тип рекомендации. Порядок в выпуске — от самого быстрого к самому долгому. */
@Serializable
enum class ItemKind {
    @SerialName("painting") PAINTING,
    @SerialName("article") ARTICLE,
    @SerialName("album") ALBUM,
    @SerialName("film") FILM;

    val key: String get() = name.lowercase()

    val title: String
        get() = when (this) {
            PAINTING -> "Картина"
            ARTICLE -> "Статья"
            ALBUM -> "Альбом"
            FILM -> "Фильм"
        }

    val pluralTitle: String
        get() = when (this) {
            PAINTING -> "Картины"
            ARTICLE -> "Статьи"
            ALBUM -> "Альбомы"
            FILM -> "Фильмы"
        }

    /** «1 картина», «2 картины», «5 картин». */
    fun counted(number: Int): String = when (this) {
        PAINTING -> Format.count(number, "картина", "картины", "картин")
        ARTICLE -> Format.count(number, "статья", "статьи", "статей")
        ALBUM -> Format.count(number, "альбом", "альбома", "альбомов")
        FILM -> Format.count(number, "фильм", "фильма", "фильмов")
    }

    val doneTitle: String
        get() = when (this) {
            PAINTING -> "Рассмотрено"
            ARTICLE -> "Прочитано"
            ALBUM -> "Прослушано"
            FILM -> "Просмотрено"
        }

    val markActionTitle: String
        get() = when (this) {
            PAINTING -> "Отметить как рассмотренное"
            ARTICLE -> "Отметить как прочитанное"
            ALBUM -> "Отметить как прослушанное"
            FILM -> "Отметить как просмотренное"
        }

    val lookForTitle: String
        get() = when (this) {
            PAINTING -> "На что смотреть"
            ALBUM -> "Как слушать"
            ARTICLE, FILM -> "На что обратить внимание"
        }

    val onboardingLine: String
        get() = when (this) {
            PAINTING -> "Рассмотреть не спеша — за пару минут"
            ARTICLE -> "Прочитать прямо в приложении"
            ALBUM -> "Послушать целиком, от первого трека до последнего"
            FILM -> "Оставить на вечер"
        }
}

/** Одна рекомендация. Формат описан в docs/catalog.md (общий с iOS). */
@Serializable
data class Item(
    val id: String,
    val kind: ItemKind,
    val title: String,
    val originalTitle: String? = null,
    val creator: String,
    val originalCreator: String? = null,
    val year: String? = null,
    val minutes: Int? = null,
    val details: List<String>? = null,
    val summary: String,
    val why: String? = null,
    val lookFor: List<String>? = null,
    val fact: String? = null,
    val more: List<String>? = null,
    val keyTrack: String? = null,
    val url: String? = null,
    val source: String? = null,
    val wiki: String? = null,
    val image: String? = null,
    val search: String? = null,
) {
    /** Год числом (первая группа из четырёх цифр). */
    val yearValue: Int?
        get() = year?.let { Regex("\\d{4}").find(it)?.value?.toIntOrNull() }

    /** «Питер Брейгель Старший, 1565» / «Nils Frahm · 2011» / «Arzamas · автор». */
    val metaLine: String
        get() = when (kind) {
            ItemKind.ARTICLE -> {
                val source = source.orEmpty()
                if (source.isEmpty() || source == creator) creator else "$source · $creator"
            }
            ItemKind.PAINTING -> listOfNotNull(creator, year).joinToString(", ")
            ItemKind.ALBUM, ItemKind.FILM -> listOfNotNull(creator, year).joinToString(" · ")
        }

    /** Страница Википедии из поля `wiki` ("ru:Название_статьи"). */
    val wikipediaUrl: String?
        get() {
            val parts = wiki?.split(":", limit = 2) ?: return null
            if (parts.size != 2) return null
            val path = Uri.encode(parts[1].replace(' ', '_'), "_(),'!:-.")
            return "https://${parts[0]}.wikipedia.org/wiki/$path"
        }

    val isWikipediaArticle: Boolean
        get() = url?.let { Uri.parse(it).host?.endsWith("wikipedia.org") } == true

    /** Русскоязычное ли произведение (для поиска обложек в российском iTunes). */
    val isRussianWork: Boolean
        get() = ((originalTitle ?: title) + " " + (originalCreator ?: creator)).any { it in 'Ѐ'..'ӿ' }

    val deepLink: String get() = "kvartet://item/$id"
}

@Serializable
data class Issue(
    val id: String,
    val theme: String,
    val intro: String,
    val items: List<Item>,
)

@Serializable
data class Catalog(
    val schemaVersion: Int,
    val updated: String? = null,
    val issues: List<Issue>,
)

/** Отметка «изучено»: когда, оценка 1–5 и заметка. */
@Serializable
data class Completion(
    val date: Long,
    val rating: Int? = null,
    val note: String? = null,
)

/** Всё, что пользователь отметил. Хранится в файле, общем для приложения и виджетов. */
@Serializable
data class UserState(
    /** День первого запуска ("2026-11-02") — с него начинается выпуск № 1. */
    val startDay: String? = null,
    val completions: Map<String, Completion> = emptyMap(),
    /** Отложенное: id → когда отложили. */
    val bookmarks: Map<String, Long> = emptyMap(),
)
