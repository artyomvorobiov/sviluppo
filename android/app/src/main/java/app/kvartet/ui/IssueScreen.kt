package app.kvartet.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.kvartet.Kvartet
import app.kvartet.data.DayNote
import app.kvartet.data.Format
import app.kvartet.data.Item
import app.kvartet.data.ItemKind
import java.time.LocalDate

/** Выпуск дня: тема, вступление и четыре карточки. */
@Composable
fun IssueScreen(
    date: LocalDate,
    isToday: Boolean,
    onOpenItem: (Item) -> Unit,
    onOpenSettings: (() -> Unit)?,
    onBack: (() -> Unit)?,
) {
    val state by Kvartet.store.state.collectAsState()
    val settings by Kvartet.settings.state.collectAsState()
    val issue = Kvartet.issueFor(date)
    val items = remember(issue, settings.enabledKinds) { Kvartet.visibleItems(issue) }
    val done = state.completions.keys
    val doneCount = items.count { it.id in done }
    val streak = Kvartet.currentStreak(state)
    val dayNote = remember(date) { Kvartet.dayNote(date) }
    var shownNote by remember { mutableStateOf<DayNote?>(null) }

    shownNote?.let { note ->
        DayNoteDialog(note, date, onOpenItem = { shownNote = null; onOpenItem(it) }, onDismiss = { shownNote = null })
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 20.dp, end = 20.dp, bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(22.dp),
    ) {
        item {
            Column {
                Row(Modifier.fillMaxWidth().height(52.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (onBack != null) {
                        TopBar(onBack = onBack)
                    } else {
                        Spacer(Modifier.weight(1f))
                        onOpenSettings?.let {
                            IconButton(onClick = it) { Icon(Icons.Filled.Settings, contentDescription = "Настройки") }
                        }
                    }
                }
                Text(
                    "${Format.weekdayDayMonth(date).uppercase(Format.russian)} · № ${Kvartet.issueNumber(date)}",
                    color = Palette.muted,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    letterSpacing = 1.sp,
                )
                Spacer(Modifier.height(6.dp))
                Text(issue.theme, style = MaterialTheme.typography.displaySmall)
                Spacer(Modifier.height(10.dp))
                Text(issue.intro, color = Palette.muted, fontSize = 17.sp, lineHeight = 25.sp)
                Spacer(Modifier.height(14.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    ProgressDots(items, done)
                    Spacer(Modifier.width(10.dp))
                    var line = "$doneCount из ${items.size}"
                    if (isToday && streak > 1) line += "  ·  ${Format.count(streak, "день", "дня", "дней")} подряд"
                    Text(line, color = Palette.muted, fontSize = 13.sp)
                }
            }
        }
        // «В этот день» привязано к календарю, а не к номеру выпуска.
        dayNote?.let { note ->
            item(key = "day-note") { DayNoteCard(note, onClick = { shownNote = note }) }
        }
        items(items, key = { it.id }) { item ->
            ItemCard(item, isDone = item.id in done, onClick = { onOpenItem(item) })
        }
        item {
            Text(
                if (items.isNotEmpty() && doneCount == items.size) "Квартет собран. До завтра!" else "Завтра — новая тема.",
                modifier = Modifier.fillMaxWidth(),
                color = Palette.muted,
                fontFamily = Serif,
                fontSize = 15.sp,
                textAlign = TextAlign.Center,
            )
        }
    }
}

@Composable
fun ItemCard(item: Item, isDone: Boolean, onClick: () -> Unit) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).clickable(onClick = onClick)) {
        when (item.kind) {
            ItemKind.PAINTING -> {
                Artwork(item, Modifier.fillMaxWidth().height(240.dp).clip(RoundedCornerShape(18.dp)), showsTitle = false)
                Spacer(Modifier.height(12.dp))
                CardCaption(item, isDone)
            }
            ItemKind.ARTICLE -> {
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(Palette.card).padding(18.dp),
                ) {
                    Box(Modifier.width(4.dp).height(96.dp).clip(RoundedCornerShape(2.dp)).background(item.kind.color))
                    Spacer(Modifier.width(14.dp))
                    Column {
                        CardCaption(item, isDone)
                        Spacer(Modifier.height(8.dp))
                        Text(item.summary, color = Palette.muted, fontSize = 14.sp, maxLines = 3, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
            ItemKind.ALBUM, ItemKind.FILM -> {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    val artModifier = if (item.kind == ItemKind.ALBUM) {
                        Modifier.size(120.dp)
                    } else {
                        Modifier.width(96.dp).aspectRatio(2f / 3f)
                    }
                    Artwork(item, artModifier.clip(RoundedCornerShape(12.dp)))
                    Spacer(Modifier.width(16.dp))
                    Column(Modifier.weight(1f)) {
                        CardCaption(item, isDone)
                        item.why?.let {
                            Spacer(Modifier.height(6.dp))
                            Text(it, color = Palette.muted, fontSize = 13.sp, maxLines = 3, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun CardCaption(item: Item, isDone: Boolean) {
    Column {
        Row(verticalAlignment = Alignment.CenterVertically) {
            KindLabel(item, Modifier.weight(1f, fill = false))
            if (isDone) {
                Spacer(Modifier.width(8.dp))
                Icon(Icons.Filled.CheckCircle, contentDescription = item.kind.doneTitle, tint = item.kind.color, modifier = Modifier.size(16.dp))
            }
        }
        Spacer(Modifier.height(4.dp))
        Text(item.title, style = MaterialTheme.typography.titleLarge, maxLines = 3, overflow = TextOverflow.Ellipsis)
        Text(item.metaLine, color = Palette.muted, fontSize = 14.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}
