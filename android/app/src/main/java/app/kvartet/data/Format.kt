package app.kvartet.data

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale

/** Даты и склонения по-русски. */
object Format {
    val russian: Locale = Locale.forLanguageTag("ru-RU")

    private val weekdayDayMonth = DateTimeFormatter.ofPattern("EEEE, d MMMM", russian)
    private val dayMonth = DateTimeFormatter.ofPattern("d MMMM", russian)
    private val monthYear = DateTimeFormatter.ofPattern("LLLL yyyy", russian)
    private val shortWeekday = DateTimeFormatter.ofPattern("EE", russian)

    /** «вторник, 20 октября» */
    fun weekdayDayMonth(date: LocalDate): String = weekdayDayMonth.format(date)

    /** «20 октября» */
    fun dayMonth(date: LocalDate): String = dayMonth.format(date)

    /** «Октябрь 2026» */
    fun monthYear(date: LocalDate): String = monthYear.format(date).replaceFirstChar { it.titlecase(russian) }

    /** «Вт» */
    fun shortWeekday(date: LocalDate): String = shortWeekday.format(date).replaceFirstChar { it.titlecase(russian) }

    /** «1 ч 52 мин», «45 мин» */
    fun duration(minutes: Int): String {
        val hours = minutes / 60
        val rest = minutes % 60
        return when {
            hours == 0 -> "$minutes мин"
            rest == 0 -> "$hours ч"
            else -> "$hours ч $rest мин"
        }
    }

    /** Форма слова для числа: plural(5, "день", "дня", "дней") → «дней». */
    fun plural(number: Int, one: String, few: String, many: String): String {
        val n = kotlin.math.abs(number) % 100
        val last = n % 10
        return when {
            n in 11..14 -> many
            last == 1 -> one
            last in 2..4 -> few
            else -> many
        }
    }

    /** «5 дней» */
    fun count(number: Int, one: String, few: String, many: String): String =
        "$number ${plural(number, one, few, many)}"

    fun dateOf(millis: Long): LocalDate = Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()).toLocalDate()
}

/** Серии дней подряд хотя бы с одной отметкой. */
object Streaks {
    /** Текущая серия: если сегодня ещё ничего не отмечено, серия живёт до конца дня. */
    fun current(dates: Collection<LocalDate>, today: LocalDate): Int {
        val days = dates.toSet()
        var day = if (today in days) today else today.minusDays(1)
        var count = 0
        while (day in days) {
            count++
            day = day.minusDays(1)
        }
        return count
    }

    fun best(dates: Collection<LocalDate>): Int {
        var best = 0
        var run = 0
        var previous: LocalDate? = null
        for (day in dates.toSortedSet()) {
            run = if (previous != null && ChronoUnit.DAYS.between(previous, day) == 1L) run + 1 else 1
            best = maxOf(best, run)
            previous = day
        }
        return best
    }
}
