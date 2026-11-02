package app.kvartet.ui

import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.kvartet.Kvartet
import app.kvartet.data.FilmService
import app.kvartet.data.Format
import app.kvartet.data.Item
import app.kvartet.data.ItemKind
import app.kvartet.data.MusicService
import coil.compose.AsyncImage
import kotlinx.coroutines.launch

/** Что открыть сразу после перехода по ссылке kvartet://item/<id>?open=… */
enum class OpenAction { READER, LOOK, ZOOM }

@Composable
fun ItemScreen(
    item: Item,
    openAction: OpenAction?,
    onBack: () -> Unit,
    onRead: () -> Unit,
    onSlowLook: () -> Unit,
    onZoom: () -> Unit,
) {
    val context = LocalContext.current
    val state by Kvartet.store.state.collectAsState()
    val settings by Kvartet.settings.state.collectAsState()
    val completion = state.completions[item.id]
    val bookmarked = state.bookmarks.containsKey(item.id)
    var showCompletion by remember { mutableStateOf(false) }
    val readMore by produceState<String?>(null, item.id) { value = Kvartet.media.readMoreUrl(item) }

    // Отложенное действие выполняется один раз: флаг переживает переход в читалку и возврат назад.
    var openHandled by rememberSaveable(item.id) { mutableStateOf(false) }
    LaunchedEffect(item.id, openAction) {
        if (openHandled || openAction == null) return@LaunchedEffect
        openHandled = true
        when (openAction) {
            OpenAction.READER -> if (item.kind == ItemKind.ARTICLE) onRead()
            OpenAction.LOOK -> if (item.kind == ItemKind.PAINTING) onSlowLook()
            OpenAction.ZOOM -> if (item.kind == ItemKind.PAINTING) onZoom()
        }
    }

    Column(Modifier.fillMaxSize()) {
        TopBar(onBack = onBack) {
            IconButton(onClick = { Kvartet.toggleBookmark(item) }) {
                Icon(
                    if (bookmarked) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
                    contentDescription = if (bookmarked) "Убрать из отложенного" else "Отложить",
                )
            }
            IconButton(onClick = {
                val link = item.url ?: item.wikipediaUrl
                shareText(context, "«${item.title}» — ${item.metaLine}" + (link?.let { "\n$it" } ?: ""))
            }) {
                Icon(Icons.Filled.Share, contentDescription = "Поделиться")
            }
        }
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 40.dp),
        ) {
            Hero(item, onZoom)
            Spacer(Modifier.height(18.dp))
            KindLabel(item)
            Spacer(Modifier.height(6.dp))
            Text(item.title, style = MaterialTheme.typography.headlineMedium)
            item.originalTitle?.takeIf { it != item.title }?.let {
                Text(it, color = Palette.muted, fontFamily = Serif, fontStyle = FontStyle.Italic, fontSize = 18.sp)
            }
            Spacer(Modifier.height(4.dp))
            Text(item.metaLine, color = Palette.muted, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
            item.details?.takeIf { it.isNotEmpty() }?.let {
                Text(it.joinToString(" · "), color = Palette.muted, fontSize = 14.sp)
            }
            Spacer(Modifier.height(20.dp))
            Actions(item, settings.musicService, settings.filmService, readMore, onRead, onSlowLook, onZoom)
            Spacer(Modifier.height(28.dp))
            Section("О чём", item.summary)
            item.why?.let { Section("Почему стоит", it) }
            item.lookFor?.takeIf { it.isNotEmpty() }?.let { Bullets(item.kind.lookForTitle, it, item.kind.color) }
            item.fact?.let { fact ->
                Column(
                    Modifier.fillMaxWidth().padding(bottom = 24.dp).clip(RoundedCornerShape(16.dp))
                        .background(item.kind.color.copy(alpha = 0.10f)).padding(16.dp),
                ) {
                    Text("✦ ЛЮБОПЫТНО", color = item.kind.color, fontSize = 12.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.sp)
                    Spacer(Modifier.height(8.dp))
                    Text(fact, fontSize = 16.sp, lineHeight = 23.sp)
                }
            }
            item.more?.takeIf { it.isNotEmpty() }?.let { Bullets("Если понравится", it, item.kind.color) }

            // Отметка «изучено»
            if (completion != null) {
                CardSurface(Modifier.fillMaxWidth()) {
                    Column {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = item.kind.color)
                            Spacer(Modifier.width(8.dp))
                            Text(
                                "${item.kind.doneTitle} ${Format.dayMonth(Format.dateOf(completion.date))}",
                                fontWeight = FontWeight.SemiBold,
                            )
                        }
                        completion.rating?.let {
                            Spacer(Modifier.height(8.dp))
                            Stars(it, item.kind.color, size = 18)
                        }
                        completion.note?.let {
                            Spacer(Modifier.height(8.dp))
                            Text("«$it»", fontFamily = Serif, fontStyle = FontStyle.Italic)
                        }
                        TextButton(onClick = { showCompletion = true }) { Text("Изменить отзыв") }
                    }
                }
            } else {
                Button(
                    onClick = { showCompletion = true },
                    modifier = Modifier.fillMaxWidth().height(52.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = item.kind.color, contentColor = Color.White),
                ) {
                    Text(item.kind.markActionTitle, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }

    if (showCompletion) {
        CompletionDialog(item, onDismiss = { showCompletion = false })
    }
}

/** Картина целиком: рамка принимает пропорции изображения, пока оно не загрузилось — заглушка 4:3. */
@Composable
private fun PaintingHero(item: Item, onZoom: () -> Unit) {
    val url by produceState(Kvartet.media.cachedArtworkUrl(item), item.id) {
        if (value == null) value = Kvartet.media.artworkUrl(item)
    }
    var ratio by remember(item.id) { mutableStateOf<Float?>(null) }
    Box(
        Modifier.fillMaxWidth()
            .aspectRatio((ratio ?: 1.3f).coerceIn(0.65f, 2.4f))
            .clip(RoundedCornerShape(14.dp))
            .background(Palette.hairline)
            .clickable(onClick = onZoom),
    ) {
        if (ratio == null) Placeholder(item, showsTitle = false, Modifier.fillMaxSize())
        url?.let {
            AsyncImage(
                model = it,
                contentDescription = item.title,
                contentScale = ContentScale.Fit,
                modifier = Modifier.fillMaxSize(),
                onSuccess = { success ->
                    val image = success.result.drawable
                    if (image.intrinsicWidth > 0 && image.intrinsicHeight > 0) {
                        ratio = image.intrinsicWidth.toFloat() / image.intrinsicHeight
                    }
                },
            )
        }
    }
}

@Composable
private fun Hero(item: Item, onZoom: () -> Unit) {
    when (item.kind) {
        ItemKind.PAINTING -> PaintingHero(item, onZoom)
        ItemKind.ALBUM -> Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            Artwork(item, Modifier.size(260.dp).clip(RoundedCornerShape(12.dp)))
        }
        ItemKind.FILM -> Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            Artwork(item, Modifier.width(200.dp).aspectRatio(2f / 3f).clip(RoundedCornerShape(12.dp)))
        }
        ItemKind.ARTICLE -> Spacer(Modifier.height(4.dp))
    }
}

@Composable
private fun Actions(
    item: Item,
    music: MusicService,
    film: FilmService,
    readMore: String?,
    onRead: () -> Unit,
    onSlowLook: () -> Unit,
    onZoom: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val primary = ButtonDefaults.buttonColors(containerColor = Palette.ink, contentColor = Palette.paper)
    val buttonModifier = Modifier.fillMaxWidth().height(52.dp)
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        when (item.kind) {
            ItemKind.PAINTING -> {
                Button(onClick = onSlowLook, modifier = buttonModifier, colors = primary) { Text("Медленный просмотр") }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    OutlinedButton(onClick = onZoom, modifier = Modifier.weight(1f)) { Text("Увеличить") }
                    readMore?.let { url ->
                        OutlinedButton(onClick = { openInApp(context, url) }, modifier = Modifier.weight(1f)) { Text("Википедия") }
                    }
                }
            }
            ItemKind.ARTICLE -> {
                Button(onClick = onRead, modifier = buttonModifier, colors = primary) { Text("Читать") }
                item.url?.let { url ->
                    OutlinedButton(onClick = { openInApp(context, url) }, modifier = Modifier.fillMaxWidth()) { Text("Открыть оригинал") }
                }
            }
            ItemKind.ALBUM -> {
                if (item.keyTrack != null) PreviewRow(item)
                Button(onClick = { openExternal(context, music.url(item)) }, modifier = buttonModifier, colors = primary) {
                    Icon(Icons.Filled.PlayArrow, contentDescription = null)
                    Spacer(Modifier.width(6.dp))
                    Text("Слушать в ${music.title}")
                }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    ServicesMenu("Другие сервисы", MusicService.entries.filter { it != music }.map { it.title to it.url(item) }, Modifier.weight(1f))
                    readMore?.let { url ->
                        OutlinedButton(onClick = { openInApp(context, url) }, modifier = Modifier.weight(1f)) { Text("Об альбоме") }
                    }
                }
            }
            ItemKind.FILM -> {
                Button(onClick = { openExternal(context, film.url(item)) }, modifier = buttonModifier, colors = primary) {
                    Text("Где смотреть: ${film.title}")
                }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    var loading by remember { mutableStateOf(false) }
                    OutlinedButton(
                        onClick = {
                            loading = true
                            scope.launch {
                                val trailer = Kvartet.media.previewUrl(item)
                                loading = false
                                if (trailer != null) {
                                    val intent = Intent(Intent.ACTION_VIEW).setDataAndType(Uri.parse(trailer), "video/*")
                                    runCatching { context.startActivity(intent) }
                                        .onFailure { openExternal(context, FilmService.youTubeTrailerUrl(item)) }
                                } else {
                                    openExternal(context, FilmService.youTubeTrailerUrl(item))
                                }
                            }
                        },
                        enabled = !loading,
                        modifier = Modifier.weight(1f),
                    ) { Text(if (loading) "Ищем…" else "Трейлер") }
                    val links = FilmService.entries.filter { it != film }.map { it.title to it.url(item) } +
                        listOfNotNull(readMore?.let { "Википедия" to it })
                    ServicesMenu("Ещё", links, Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
private fun ServicesMenu(title: String, links: List<Pair<String, String>>, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    var expanded by remember { mutableStateOf(false) }
    Box(modifier) {
        OutlinedButton(onClick = { expanded = true }, modifier = Modifier.fillMaxWidth()) { Text(title) }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            links.forEach { (name, url) ->
                DropdownMenuItem(text = { Text(name) }, onClick = {
                    expanded = false
                    if (url.contains("wikipedia.org")) openInApp(context, url) else openExternal(context, url)
                })
            }
        }
    }
}

/** «С чего начать · 30 секунд» — фрагмент ключевого трека. */
@Composable
private fun PreviewRow(item: Item) {
    val scope = rememberCoroutineScope()
    val player = remember { PreviewPlayer() }
    DisposableEffect(item.id) { onDispose { player.release() } }
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(Palette.card)
            .clickable { scope.launch { player.toggle(item) } }.padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier.size(48.dp).clip(CircleShape).background(item.kind.color.copy(alpha = 0.15f)),
            contentAlignment = Alignment.Center,
        ) {
            when (player.state) {
                PreviewPlayer.State.LOADING -> CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp, color = item.kind.color)
                PreviewPlayer.State.PLAYING -> Text("❚❚", color = item.kind.color, fontWeight = FontWeight.Bold)
                else -> Icon(Icons.Filled.PlayArrow, contentDescription = "Слушать фрагмент", tint = item.kind.color)
            }
        }
        Spacer(Modifier.width(14.dp))
        Column {
            Text(
                if (player.state == PreviewPlayer.State.UNAVAILABLE) "Фрагмент не нашёлся" else "С чего начать · 30 секунд",
                color = Palette.muted,
                fontSize = 13.sp,
            )
            Text("«${item.keyTrack}»", fontWeight = FontWeight.SemiBold)
        }
    }
}

/** Проигрыватель 30-секундного фрагмента из iTunes. */
class PreviewPlayer {
    enum class State { IDLE, LOADING, PLAYING, PAUSED, UNAVAILABLE }

    var state by mutableStateOf(State.IDLE)
        private set
    private var player: MediaPlayer? = null

    suspend fun toggle(item: Item) {
        when (state) {
            State.PLAYING -> {
                player?.pause()
                state = State.PAUSED
            }
            State.PAUSED -> {
                player?.start()
                state = State.PLAYING
            }
            State.LOADING -> Unit
            State.IDLE, State.UNAVAILABLE -> {
                state = State.LOADING
                val url = Kvartet.media.previewUrl(item)
                if (url == null) {
                    state = State.UNAVAILABLE
                    return
                }
                release()
                player = MediaPlayer().apply {
                    setAudioAttributes(
                        AudioAttributes.Builder().setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).setUsage(AudioAttributes.USAGE_MEDIA).build(),
                    )
                    setOnPreparedListener {
                        it.start()
                        state = State.PLAYING
                    }
                    setOnCompletionListener { state = State.IDLE }
                    setOnErrorListener { _, _, _ ->
                        state = State.UNAVAILABLE
                        true
                    }
                    try {
                        setDataSource(url)
                        prepareAsync()
                    } catch (e: Exception) {
                        state = State.UNAVAILABLE
                    }
                }
            }
        }
    }

    fun release() {
        player?.release()
        player = null
        if (state != State.UNAVAILABLE) state = State.IDLE
    }
}

@Composable
private fun Section(title: String, text: String) {
    Column(Modifier.padding(bottom = 24.dp)) {
        SectionTitle(title)
        Spacer(Modifier.height(8.dp))
        Text(text, fontSize = 17.sp, lineHeight = 25.sp)
    }
}

@Composable
private fun Bullets(title: String, items: List<String>, color: Color) {
    Column(Modifier.padding(bottom = 24.dp)) {
        SectionTitle(title)
        Spacer(Modifier.height(8.dp))
        items.forEach { line ->
            Row(Modifier.padding(vertical = 4.dp)) {
                Box(Modifier.padding(top = 9.dp).size(6.dp).clip(CircleShape).background(color))
                Spacer(Modifier.width(12.dp))
                Text(line, fontSize = 16.sp, lineHeight = 23.sp)
            }
        }
    }
}

private fun ratingCaption(rating: Int): String = when (rating) {
    1 -> "Не моё"
    2 -> "Так себе"
    3 -> "Неплохо"
    4 -> "Понравилось"
    5 -> "Восторг"
    else -> "Можно без оценки"
}

/** Отметка «изучено»: оценка и заметка для дневника. */
@Composable
fun CompletionDialog(item: Item, onDismiss: () -> Unit) {
    val existing = Kvartet.store.state.value.completions[item.id]
    var rating by remember { mutableIntStateOf(existing?.rating ?: 0) }
    var note by remember { mutableStateOf(existing?.note.orEmpty()) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(item.kind.doneTitle, fontFamily = Serif) },
        text = {
            Column {
                Text("Как вам?", color = Palette.muted)
                Row(Modifier.padding(vertical = 6.dp)) {
                    (1..5).forEach { value ->
                        IconButton(onClick = { rating = if (rating == value) 0 else value }, modifier = Modifier.size(44.dp)) {
                            Icon(
                                Icons.Filled.Star,
                                contentDescription = ratingCaption(value),
                                tint = if (value <= rating) item.kind.color else item.kind.color.copy(alpha = 0.2f),
                                modifier = Modifier.size(32.dp),
                            )
                        }
                    }
                }
                Text(ratingCaption(rating), color = Palette.muted, fontSize = 13.sp)
                Spacer(Modifier.height(12.dp))
                OutlinedTextField(
                    value = note,
                    onValueChange = { note = it },
                    label = { Text("Заметка для дневника") },
                    placeholder = { Text("Мысль, цитата, ассоциация…") },
                    modifier = Modifier.fillMaxWidth().widthIn(min = 200.dp),
                    minLines = 2,
                )
                if (existing != null) {
                    TextButton(onClick = {
                        Kvartet.unmark(item)
                        onDismiss()
                    }) { Text("Снять отметку", color = Color(0xFFB23B32)) }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = {
                Kvartet.markDone(item, rating.takeIf { it > 0 }, note)
                onDismiss()
            }) { Text("Готово") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Отмена") } },
    )
}
