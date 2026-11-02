package app.kvartet.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.kvartet.Kvartet
import app.kvartet.data.Format
import app.kvartet.data.Item
import app.kvartet.data.ItemKind
import java.time.LocalDate

@Composable
private fun ScreenTitle(text: String, actions: @Composable () -> Unit = {}) {
    Row(Modifier.fillMaxWidth().padding(top = 20.dp, bottom = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(text, style = MaterialTheme.typography.displaySmall, modifier = Modifier.weight(1f))
        actions()
    }
}

// region Архив

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ArchiveScreen(onOpenDay: (LocalDate) -> Unit, onOpenItem: (Item) -> Unit) {
    val state by Kvartet.store.state.collectAsState()
    val today by Kvartet.today.collectAsState()
    var segment by rememberSaveable { mutableIntStateOf(0) }
    val days = remember(today, state.startDay) { Kvartet.archiveDays() }
    val saved = state.bookmarks.entries.sortedByDescending { it.value }.mapNotNull { Kvartet.item(it.key) }

    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 20.dp, end = 20.dp, bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        item {
            ScreenTitle("Архив")
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(bottom = 8.dp)) {
                listOf("Выпуски", "Отложенное").forEachIndexed { index, title ->
                    SegmentedButton(
                        selected = segment == index,
                        onClick = { segment = index },
                        shape = SegmentedButtonDefaults.itemShape(index, 2),
                    ) { Text(title) }
                }
            }
        }
        if (segment == 0) {
            var lastMonth = ""
            days.forEach { date ->
                val month = Format.monthYear(date)
                if (month != lastMonth) {
                    lastMonth = month
                    item(key = "month-$month") {
                        SectionTitle(month, Modifier.padding(top = 12.dp, bottom = 4.dp))
                    }
                }
                item(key = date.toString()) {
                    DayRow(date, isToday = date == today, done = state.completions.keys, onClick = { onOpenDay(date) })
                }
            }
            if (days.size == 1) {
                item {
                    Text(
                        "Каждый день здесь будет появляться новый выпуск. Пропущенные дни никуда не денутся — их можно открыть в архиве.",
                        color = Palette.muted,
                        modifier = Modifier.padding(top = 12.dp),
                    )
                }
            }
        } else if (saved.isEmpty()) {
            item {
                Column(Modifier.fillMaxWidth().padding(top = 48.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("Ничего не отложено", style = MaterialTheme.typography.titleMedium)
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "Нажмите на сердечко на экране рекомендации, чтобы вернуться к ней позже.",
                        color = Palette.muted,
                        textAlign = TextAlign.Center,
                    )
                }
            }
        } else {
            items(saved, key = { "saved-${it.id}" }) { item -> ItemRow(item, onClick = { onOpenItem(item) }) }
        }
    }
}

@Composable
private fun DayRow(date: LocalDate, isToday: Boolean, done: Set<String>, onClick: () -> Unit) {
    val issue = Kvartet.issueFor(date)
    val items = Kvartet.visibleItems(issue)
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Palette.card).clickable(onClick = onClick).padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.width(44.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text("${date.dayOfMonth}", fontFamily = Serif, fontSize = 24.sp, fontWeight = FontWeight.SemiBold)
            Text(Format.shortWeekday(date), color = Palette.muted, fontSize = 12.sp)
        }
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(issue.theme, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Spacer(Modifier.height(4.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                ProgressDots(items, done, size = 8)
                if (isToday) {
                    Spacer(Modifier.width(8.dp))
                    Text("сегодня", color = Palette.muted, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}

@Composable
private fun ItemRow(item: Item, onClick: () -> Unit, trailing: @Composable () -> Unit = {}) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Palette.card).clickable(onClick = onClick).padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (item.kind == ItemKind.ARTICLE) {
            Box(Modifier.size(52.dp).clip(RoundedCornerShape(8.dp)).background(item.kind.color.copy(alpha = 0.15f)))
        } else {
            Artwork(item, Modifier.size(52.dp).clip(RoundedCornerShape(8.dp)), showsTitle = false)
        }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            KindLabel(item)
            Text(item.title, fontFamily = Serif, fontWeight = FontWeight.SemiBold, fontSize = 16.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(item.metaLine, color = Palette.muted, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            trailing()
        }
    }
}

// endregion

// region Дневник

@Composable
fun JournalScreen(onOpenItem: (Item) -> Unit) {
    val context = LocalContext.current
    val state by Kvartet.store.state.collectAsState()
    val entries = Kvartet.journalEntries(state)
    val streak = Kvartet.currentStreak(state)
    val best = Kvartet.bestStreak(state)

    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 20.dp, end = 20.dp, bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item {
            ScreenTitle("Дневник") {
                IconButton(onClick = { shareText(context, Kvartet.journalMarkdown(state), "Дневник «Квартета»") }) {
                    Icon(Icons.Filled.Share, contentDescription = "Экспорт дневника")
                }
            }
            CardSurface(Modifier.fillMaxWidth()) {
                Column {
                    Row(verticalAlignment = Alignment.Bottom) {
                        Column(Modifier.weight(1f)) {
                            Text("$streak", fontFamily = Serif, fontSize = 44.sp, fontWeight = FontWeight.Bold)
                            Text("${Format.plural(streak, "день", "дня", "дней")} подряд", color = Palette.muted)
                        }
                        Column(horizontalAlignment = Alignment.End) {
                            Text("$best", fontFamily = Serif, fontSize = 24.sp, fontWeight = FontWeight.Bold)
                            Text("рекорд", color = Palette.muted)
                        }
                    }
                    Spacer(Modifier.height(14.dp))
                    ItemKind.entries.chunked(2).forEach { pair ->
                        Row(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                            pair.forEach { kind ->
                                val count = entries.count { it.item.kind == kind }
                                Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically) {
                                    Box(Modifier.size(10.dp).clip(CircleShape).background(kind.color))
                                    Spacer(Modifier.width(8.dp))
                                    Text(kind.counted(count))
                                }
                            }
                        }
                    }
                }
            }
        }
        if (entries.isEmpty()) {
            item {
                Column(Modifier.fillMaxWidth().padding(top = 48.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("Дневник пока пуст", style = MaterialTheme.typography.titleMedium)
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "Отмечайте изученное — сюда попадут оценки и заметки, а с ними и ваша личная история открытий.",
                        color = Palette.muted,
                        textAlign = TextAlign.Center,
                    )
                }
            }
        } else {
            var lastMonth = ""
            entries.forEach { entry ->
                val date = Format.dateOf(entry.completion.date)
                val month = Format.monthYear(date)
                if (month != lastMonth) {
                    lastMonth = month
                    item(key = "month-$month") { SectionTitle(month, Modifier.padding(top = 14.dp, bottom = 2.dp)) }
                }
                item(key = entry.item.id) {
                    ItemRow(entry.item, onClick = { onOpenItem(entry.item) }) {
                        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 4.dp)) {
                            Text(Format.dayMonth(date), color = Palette.muted, fontSize = 12.sp)
                            entry.completion.rating?.let {
                                Spacer(Modifier.width(8.dp))
                                Stars(it, entry.item.kind.color, size = 12)
                            }
                        }
                        entry.completion.note?.let {
                            Text("«$it»", fontFamily = Serif, fontStyle = FontStyle.Italic, fontSize = 14.sp, maxLines = 3, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
            }
        }
    }
}

// endregion
