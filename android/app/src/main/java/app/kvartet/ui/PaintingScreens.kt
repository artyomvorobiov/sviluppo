package app.kvartet.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.rememberTransformableState
import androidx.compose.foundation.gestures.transformable
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
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.kvartet.Kvartet
import app.kvartet.data.Item
import coil.compose.AsyncImage
import kotlinx.coroutines.delay

private const val PROMPT_SECONDS = 20

/** Медленный просмотр: подсказки по 20 секунд, чтобы смотреть, а не пролистывать. */
@Composable
fun SlowLookingScreen(item: Item, onClose: () -> Unit) {
    val prompts = remember(item.id) {
        buildList {
            add("Не спешите читать подписи. Просто посмотрите на картину целиком — около полуминуты.")
            addAll(item.lookFor.orEmpty())
            add("Теперь посмотрите туда, куда не смотрели. Края, фон, тени, пустоты.")
            add("Закройте глаза и попробуйте вспомнить картину. Что всплывает первым?")
        }
    }
    var index by remember { mutableIntStateOf(0) }
    var elapsed by remember { mutableFloatStateOf(0f) }
    var running by remember { mutableStateOf(true) }
    var finished by remember { mutableStateOf(false) }
    var showCompletion by remember { mutableStateOf(false) }

    LaunchedEffect(index, running, finished) {
        while (running && !finished) {
            delay(100)
            elapsed += 0.1f
            if (elapsed >= PROMPT_SECONDS) {
                elapsed = 0f
                if (index < prompts.lastIndex) index++ else finished = true
            }
        }
    }

    Box(Modifier.fillMaxSize().background(Color.Black).systemBarsPadding()) {
        Column(Modifier.fillMaxSize()) {
            Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onClose) { Icon(Icons.Filled.Close, contentDescription = "Закрыть", tint = Color.White) }
                LinearProgressIndicator(
                    progress = { if (finished) 1f else (index + elapsed / PROMPT_SECONDS) / prompts.size },
                    modifier = Modifier.weight(1f).padding(horizontal = 8.dp),
                    color = Color.White,
                    trackColor = Color.White.copy(alpha = 0.2f),
                )
            }
            ArtworkImage(item, Modifier.weight(1f).fillMaxWidth())
            Column(
                Modifier.fillMaxWidth().padding(16.dp).clip(RoundedCornerShape(20.dp))
                    .background(Color(0xFF1E1E20)).padding(20.dp),
            ) {
                Text(
                    if (finished) "ЧТО ВЫ УВИДЕЛИ?" else "ПОДСКАЗКА ${index + 1} ИЗ ${prompts.size}",
                    color = Color.White.copy(alpha = 0.6f),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    letterSpacing = 1.sp,
                )
                Spacer(Modifier.height(10.dp))
                Text(
                    if (finished) "Запишите одну мысль — так картина запомнится надолго." else prompts[index],
                    color = Color.White,
                    fontFamily = Serif,
                    fontSize = 22.sp,
                    lineHeight = 29.sp,
                )
                Spacer(Modifier.height(16.dp))
                if (finished) {
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Button(
                            onClick = { showCompletion = true },
                            colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = Color.Black),
                        ) { Text("Записать в дневник") }
                        RoundButton(Icons.Filled.Refresh, "Ещё раз") {
                            index = 0
                            elapsed = 0f
                            finished = false
                            running = true
                        }
                    }
                } else {
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        RoundButton(
                            if (running) null else Icons.Filled.PlayArrow,
                            if (running) "Пауза" else "Продолжить",
                            label = if (running) "❚❚" else null,
                        ) { running = !running }
                        RoundButton(Icons.AutoMirrored.Filled.KeyboardArrowRight, "Следующая подсказка") {
                            elapsed = 0f
                            if (index < prompts.lastIndex) index++ else finished = true
                        }
                        Spacer(Modifier.weight(1f))
                        val left = ((prompts.size - index) * PROMPT_SECONDS - elapsed.toInt()).coerceAtLeast(0)
                        Text("%d:%02d".format(left / 60, left % 60), color = Color.White.copy(alpha = 0.6f))
                    }
                }
            }
        }
    }

    if (showCompletion) {
        CompletionDialog(item, onDismiss = {
            showCompletion = false
            onClose()
        })
    }
}

@Composable
private fun RoundButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector?,
    description: String,
    label: String? = null,
    onClick: () -> Unit,
) {
    IconButton(
        onClick = onClick,
        modifier = Modifier.size(52.dp).clip(CircleShape),
        colors = IconButtonDefaults.iconButtonColors(containerColor = Color.White.copy(alpha = 0.12f), contentColor = Color.White),
    ) {
        if (icon != null) Icon(icon, contentDescription = description) else Text(label.orEmpty(), color = Color.White, fontWeight = FontWeight.Bold)
    }
}

/** Изображение картины целиком (без обрезки). */
@Composable
private fun ArtworkImage(item: Item, modifier: Modifier = Modifier) {
    val url by produceState(Kvartet.media.cachedArtworkUrl(item), item.id) {
        if (value == null) value = Kvartet.media.artworkUrl(item)
    }
    Box(modifier, contentAlignment = Alignment.Center) {
        url?.let {
            AsyncImage(model = it, contentDescription = item.title, contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize())
        }
    }
}

/** Увеличение: щипок и двойное касание. */
@Composable
fun ZoomScreen(item: Item, onClose: () -> Unit) {
    var scale by remember { mutableFloatStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }
    val transform = rememberTransformableState { zoom, pan, _ ->
        scale = (scale * zoom).coerceIn(1f, 8f)
        offset = if (scale == 1f) Offset.Zero else offset + pan
    }
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        Box(
            Modifier.fillMaxSize()
                .pointerInput(Unit) {
                    detectTapGestures(onDoubleTap = {
                        if (scale > 1f) {
                            scale = 1f
                            offset = Offset.Zero
                        } else {
                            scale = 2.5f
                        }
                    })
                }
                .transformable(transform)
                .graphicsLayer(scaleX = scale, scaleY = scale, translationX = offset.x, translationY = offset.y),
        ) {
            ArtworkImage(item, Modifier.fillMaxSize())
        }
        IconButton(
            onClick = onClose,
            modifier = Modifier.systemBarsPadding().padding(8.dp).align(Alignment.TopEnd),
        ) { Icon(Icons.Filled.Close, contentDescription = "Закрыть", tint = Color.White) }
        Text(
            item.title,
            color = Color.White.copy(alpha = 0.7f),
            fontFamily = Serif,
            modifier = Modifier.systemBarsPadding().padding(20.dp).align(Alignment.BottomStart).width(300.dp),
        )
    }
}
