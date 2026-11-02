package app.kvartet.widget

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.ColorFilter
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.background
import androidx.glance.color.ColorProvider
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ContentScale
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontFamily
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import app.kvartet.Artwork
import app.kvartet.Kvartet
import app.kvartet.MainActivity
import app.kvartet.R
import app.kvartet.data.Format
import app.kvartet.data.Item
import app.kvartet.data.ItemKind
import kotlinx.coroutines.launch
import java.time.LocalDate

object Widgets {
    fun updateAll(context: Context) {
        Kvartet.scope.launch {
            runCatching {
                QuartetWidget().updateAll(context)
                PaintingWidget().updateAll(context)
            }
        }
    }
}

private val paper = ColorProvider(day = Color(0xFFFAF8F4), night = Color(0xFF111113))
private val ink = ColorProvider(day = Color(0xFF1C1B1A), night = Color(0xFFF2EFEA))
private val muted = ColorProvider(day = Color(0xFF6F6A62), night = Color(0xFF9C988F))

private fun ItemKind.widgetColor(): ColorProvider = when (this) {
    ItemKind.PAINTING -> ColorProvider(day = Color(0xFFA8741A), night = Color(0xFFE3B35A))
    ItemKind.ARTICLE -> ColorProvider(day = Color(0xFF2F7A5A), night = Color(0xFF6CC79A))
    ItemKind.ALBUM -> ColorProvider(day = Color(0xFF3B5BA9), night = Color(0xFF8FA8F0))
    ItemKind.FILM -> ColorProvider(day = Color(0xFFB23B32), night = Color(0xFFEE7B70))
}

private fun openIntent(context: Context, link: String) =
    Intent(Intent.ACTION_VIEW, Uri.parse(link), context, MainActivity::class.java)

// region «Квартет дня»

/** Тема дня и четыре рекомендации; отмечать изученное можно прямо на экране. */
class QuartetWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        Kvartet.init(context)
        val date = LocalDate.now()
        val issue = Kvartet.issueFor(date)
        val items = Kvartet.visibleItems(issue)
        val done = Kvartet.store.state.value.completions.keys
        provideContent {
            QuartetContent(date, issue.theme, items, done)
        }
    }
}

@Composable
private fun QuartetContent(date: LocalDate, theme: String, items: List<Item>, done: Set<String>) {
    val context = LocalContext.current
    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(paper)
            .cornerRadius(20.dp)
            .padding(16.dp),
    ) {
        Row(
            modifier = GlanceModifier.fillMaxWidth().clickable(actionStartActivity(openIntent(context, "kvartet://today"))),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = Format.weekdayDayMonth(date).uppercase(Format.russian),
                style = TextStyle(color = muted, fontSize = 11.sp, fontWeight = FontWeight.Bold),
                modifier = GlanceModifier.defaultWeight(),
            )
            Text(
                text = "${items.count { it.id in done }} из ${items.size}",
                style = TextStyle(color = muted, fontSize = 11.sp),
            )
        }
        Text(
            text = theme,
            maxLines = 2,
            style = TextStyle(color = ink, fontSize = 22.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Serif),
            modifier = GlanceModifier.padding(top = 2.dp, bottom = 8.dp)
                .clickable(actionStartActivity(openIntent(context, "kvartet://today"))),
        )
        items.forEach { item ->
            val isDone = item.id in done
            Row(
                modifier = GlanceModifier.fillMaxWidth().padding(vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(modifier = GlanceModifier.size(8.dp).cornerRadius(4.dp).background(item.kind.widgetColor())) {}
                Spacer(GlanceModifier.width(10.dp))
                Column(
                    modifier = GlanceModifier.defaultWeight()
                        .clickable(actionStartActivity(openIntent(context, item.deepLink))),
                ) {
                    Text(
                        text = item.title,
                        maxLines = 1,
                        style = TextStyle(color = if (isDone) muted else ink, fontSize = 14.sp, fontWeight = FontWeight.Medium),
                    )
                    Text(
                        text = item.kind.title.uppercase(Format.russian),
                        maxLines = 1,
                        style = TextStyle(color = item.kind.widgetColor(), fontSize = 9.sp, fontWeight = FontWeight.Bold),
                    )
                }
                Image(
                    provider = ImageProvider(if (isDone) R.drawable.ic_check_on else R.drawable.ic_check_off),
                    contentDescription = if (isDone) "Снять отметку" else item.kind.markActionTitle,
                    colorFilter = ColorFilter.tint(if (isDone) item.kind.widgetColor() else muted),
                    modifier = GlanceModifier.size(26.dp).padding(2.dp)
                        .clickable(actionRunCallback<ToggleDoneAction>(actionParametersOf(ToggleDoneAction.ItemId to item.id))),
                )
            }
        }
    }
}

class ToggleDoneAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val id = parameters[ItemId] ?: return
        Kvartet.init(context)
        Kvartet.toggleDone(id)
        QuartetWidget().updateAll(context)
    }

    companion object {
        val ItemId = ActionParameters.Key<String>("itemId")
    }
}

class QuartetWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = QuartetWidget()
}

// endregion

// region «Картина дня»

/** Картина из сегодняшнего выпуска на весь виджет. */
class PaintingWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        Kvartet.init(context)
        val issue = Kvartet.issueFor(LocalDate.now())
        val painting = issue.items.firstOrNull { it.kind == ItemKind.PAINTING } ?: issue.items.firstOrNull()
        val bitmap = painting?.let { runCatching { Artwork.bitmap(context, it) }.getOrNull() }
        provideContent {
            val context = LocalContext.current
            Box(
                modifier = GlanceModifier.fillMaxSize().background(paper).cornerRadius(20.dp)
                    .clickable(actionStartActivity(openIntent(context, painting?.deepLink ?: "kvartet://today"))),
                contentAlignment = Alignment.BottomStart,
            ) {
                if (bitmap != null) {
                    Image(
                        provider = ImageProvider(bitmap),
                        contentDescription = painting?.title,
                        contentScale = ContentScale.Crop,
                        modifier = GlanceModifier.fillMaxSize(),
                    )
                }
                if (painting != null) {
                    Column(
                        modifier = GlanceModifier.fillMaxWidth()
                            .background(ColorProvider(Color(0x99000000)))
                            .padding(horizontal = 12.dp, vertical = 8.dp),
                    ) {
                        Text(
                            text = painting.title,
                            maxLines = 2,
                            style = TextStyle(color = ColorProvider(Color.White), fontSize = 14.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Serif),
                        )
                        Text(
                            text = painting.creator,
                            maxLines = 1,
                            style = TextStyle(color = ColorProvider(Color(0xCCFFFFFF)), fontSize = 11.sp),
                        )
                    }
                }
                if (bitmap == null && painting == null) {
                    Spacer(GlanceModifier.height(1.dp))
                }
            }
        }
    }
}

class PaintingWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = PaintingWidget()
}

// endregion
