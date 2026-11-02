package app.kvartet.ui

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.kvartet.Kvartet
import app.kvartet.data.Format
import app.kvartet.data.Item
import coil.compose.AsyncImage

/** Обложка, постер или картина; пока не загрузилась — цветная заглушка с названием. */
@Composable
fun Artwork(
    item: Item,
    modifier: Modifier = Modifier,
    contentScale: ContentScale = ContentScale.Crop,
    showsTitle: Boolean = true,
) {
    val url by produceState(Kvartet.media.cachedArtworkUrl(item), item.id) {
        if (value == null) value = Kvartet.media.artworkUrl(item)
    }
    Box(modifier) {
        Placeholder(item, showsTitle, Modifier.fillMaxSize())
        url?.let {
            AsyncImage(
                model = it,
                contentDescription = item.title,
                contentScale = contentScale,
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}

@Composable
fun Placeholder(item: Item, showsTitle: Boolean, modifier: Modifier = Modifier) {
    val base = item.kind.color(dark = false)
    val shift = (item.id.hashCode() % 20) / 100f
    val top = lerp(base, Color.Black, 0.05f + shift.coerceIn(0f, 0.15f))
    val bottom = lerp(base, Color.Black, 0.45f)
    Box(
        modifier.background(Brush.linearGradient(listOf(top, bottom))),
        contentAlignment = Alignment.BottomStart,
    ) {
        if (showsTitle) {
            Column(Modifier.padding(12.dp)) {
                Text(
                    item.title,
                    color = Color.White,
                    fontFamily = Serif,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 15.sp,
                    maxLines = 3,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(item.creator, color = Color.White.copy(alpha = 0.8f), fontSize = 11.sp, maxLines = 1)
            }
        }
    }
}

/** «КАРТИНА · 3 МИН» */
@Composable
fun KindLabel(item: Item, modifier: Modifier = Modifier) {
    val parts = mutableListOf(item.kind.title.uppercase(Format.russian))
    item.minutes?.let { parts += Format.duration(it).uppercase(Format.russian) }
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(7.dp).clip(CircleShape).background(item.kind.color))
        Spacer(Modifier.width(6.dp))
        Text(
            parts.joinToString(" · "),
            color = item.kind.color,
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
            letterSpacing = 1.sp,
        )
    }
}

/** Четыре точки прогресса цветов типов. */
@Composable
fun ProgressDots(items: List<Item>, done: Set<String>, size: Int = 10) {
    Row(horizontalArrangement = Arrangement.spacedBy((size * 0.6).dp)) {
        items.forEach { item ->
            val color = item.kind.color
            val dot = Modifier.size(size.dp).clip(CircleShape)
            Box(if (item.id in done) dot.background(color) else dot.border(1.5.dp, color, CircleShape))
        }
    }
}

@Composable
fun Stars(rating: Int, color: Color, size: Int = 14) {
    Row {
        repeat(5) { index ->
            Icon(
                Icons.Filled.Star,
                contentDescription = null,
                tint = if (index < rating) color else color.copy(alpha = 0.2f),
                modifier = Modifier.size(size.dp),
            )
        }
    }
}

@Composable
fun SectionTitle(text: String, modifier: Modifier = Modifier) {
    Text(
        text.uppercase(Format.russian),
        modifier = modifier,
        color = Palette.muted,
        fontSize = 12.sp,
        fontWeight = FontWeight.SemiBold,
        letterSpacing = 1.sp,
    )
}

/** Верхняя панель с кнопкой «назад» и действиями справа. */
@Composable
fun TopBar(
    title: String? = null,
    onBack: (() -> Unit)?,
    actions: @Composable () -> Unit = {},
) {
    Row(
        Modifier.fillMaxWidth().height(56.dp).padding(horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (onBack != null) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Назад")
            }
        } else {
            Spacer(Modifier.width(12.dp))
        }
        Text(
            title.orEmpty(),
            modifier = Modifier.weight(1f).padding(horizontal = 4.dp),
            style = MaterialTheme.typography.titleMedium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        actions()
    }
}

/** Карточка-подложка в цвет «бумаги». */
@Composable
fun CardSurface(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(modifier.clip(RoundedCornerShape(16.dp)).background(Palette.card).padding(16.dp)) {
        content()
    }
}

/** Открыть ссылку во встроенной вкладке браузера. */
fun openInApp(context: Context, url: String) {
    try {
        CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(context, Uri.parse(url))
    } catch (e: ActivityNotFoundException) {
        openExternal(context, url)
    }
}

/** Открыть ссылку в приложении сервиса (Яндекс Музыка, Кинопоиск) или в браузере. */
fun openExternal(context: Context, url: String) {
    try {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    } catch (e: ActivityNotFoundException) {
        // Нечем открыть — ничего не делаем.
    }
}

fun shareText(context: Context, text: String, title: String = "Поделиться") {
    val intent = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
    context.startActivity(Intent.createChooser(intent, title).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
}
