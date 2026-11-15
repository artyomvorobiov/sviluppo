package app.kvartet.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.kvartet.Kvartet
import app.kvartet.data.DayNote
import app.kvartet.data.Format
import app.kvartet.data.Item
import java.time.LocalDate

/** Карточка рубрики «В этот день» на экране выпуска. */
@Composable
fun DayNoteCard(note: DayNote, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Palette.card)
            .border(1.dp, Palette.hairline, RoundedCornerShape(16.dp))
            .clickable(onClick = onClick)
            .padding(14.dp),
    ) {
        note.artworkItem?.let {
            Artwork(it, Modifier.size(64.dp).clip(RoundedCornerShape(10.dp)), showsTitle = false)
            Spacer(Modifier.width(14.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(
                note.label.uppercase(Format.russian),
                color = Palette.muted,
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = 0.8.sp,
                maxLines = 1,
            )
            Spacer(Modifier.height(3.dp))
            Text(note.title, fontFamily = Serif, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
            Text(note.text, color = Palette.muted, fontSize = 13.sp, lineHeight = 18.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** Полный текст рубрики «В этот день». */
@Composable
fun DayNoteDialog(note: DayNote, date: LocalDate, onOpenItem: (Item) -> Unit, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val wrapper = note.artworkItem
    val moreUrl by produceState<String?>(null, note.date) {
        value = wrapper?.takeIf { it.wiki != null }?.let { Kvartet.media.readMoreUrl(it) }
    }
    val linked = note.item?.let { Kvartet.item(it) }

    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Palette.paper,
        title = {
            Column {
                Text(
                    "${Format.dayMonth(date)} · ${note.label}".uppercase(Format.russian),
                    color = Palette.muted,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    letterSpacing = 1.sp,
                )
                Spacer(Modifier.height(6.dp))
                Text(note.title, fontFamily = Serif, fontWeight = FontWeight.SemiBold, fontSize = 24.sp, lineHeight = 30.sp)
            }
        },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                wrapper?.let {
                    Artwork(
                        it,
                        Modifier.fillMaxWidth().height(220.dp).clip(RoundedCornerShape(12.dp)),
                        contentScale = ContentScale.Fit,
                        showsTitle = false,
                    )
                    Spacer(Modifier.height(14.dp))
                }
                Text(note.text, fontSize = 16.sp, lineHeight = 24.sp, color = Palette.ink)
                note.tip?.takeIf { it.isNotEmpty() }?.let { tip ->
                    Spacer(Modifier.height(16.dp))
                    SectionTitle("Чем отметить")
                    Spacer(Modifier.height(6.dp))
                    Text(tip, fontSize = 16.sp, lineHeight = 24.sp, color = Palette.ink)
                }
                linked?.let {
                    Spacer(Modifier.height(12.dp))
                    TextButton(onClick = { onOpenItem(it) }) { Text("${it.kind.title}: ${it.title}") }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Готово") } },
        dismissButton = {
            Row {
                TextButton(onClick = {
                    val body = listOfNotNull(
                        "${Format.dayMonth(date)} — ${note.label.lowercase(Format.russian)}. ${note.title}", "", note.text,
                        note.tip?.takeIf { it.isNotEmpty() }?.let { "\n$it" }, "", "Из приложения «Квартет»",
                    ).joinToString("\n")
                    shareText(context, body)
                }) { Text("Поделиться") }
                moreUrl?.let { url -> TextButton(onClick = { openInApp(context, url) }) { Text("Википедия") } }
            }
        },
    )
}
