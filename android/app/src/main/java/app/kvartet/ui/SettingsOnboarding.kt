package app.kvartet.ui

import android.Manifest
import android.app.TimePickerDialog
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.kvartet.Kvartet
import app.kvartet.data.FilmService
import app.kvartet.data.ItemKind
import app.kvartet.data.MusicService
import app.kvartet.data.ReaderTheme
import app.kvartet.reader.ArticleCache
import app.kvartet.reminders.Reminders
import coil.imageLoader

/** Разрешение на уведомления (Android 13+): включает напоминание, только если пользователь согласился. */
@Composable
private fun rememberReminderSwitch(): (Boolean) -> Unit {
    val context = LocalContext.current
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        Kvartet.settings.update { it.copy(reminderEnabled = granted) }
        Reminders.reschedule(context)
    }
    return { enabled ->
        if (enabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !Reminders.canNotify(context)) {
            launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            Kvartet.settings.update { it.copy(reminderEnabled = enabled) }
            Reminders.reschedule(context)
        }
    }
}

private fun timeText(hour: Int, minute: Int) = "%d:%02d".format(hour, minute)

@OptIn(coil.annotation.ExperimentalCoilApi::class)
@Composable
fun SettingsScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val settings by Kvartet.settings.state.collectAsState()
    val setReminder = rememberReminderSwitch()
    var confirmReset by remember { mutableStateOf(false) }

    Column(Modifier.fillMaxSize()) {
        TopBar(title = "Настройки", onBack = onBack)
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 40.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            SectionTitle("Что показывать", Modifier.padding(top = 8.dp))
            Group {
                ItemKind.entries.forEachIndexed { index, kind ->
                    if (index > 0) HorizontalDivider(color = Palette.hairline)
                    SwitchRow(kind.pluralTitle, settings.enabledKinds.contains(kind), dot = kind.color) { on ->
                        Kvartet.settings.update {
                            it.copy(enabledKinds = if (on) it.enabledKinds + kind else it.enabledKinds - kind)
                        }
                        app.kvartet.widget.Widgets.updateAll(context)
                    }
                }
            }
            Hint("Выключенные типы не появятся ни в выпусках, ни в виджетах.")

            SectionTitle("Напоминание", Modifier.padding(top = 16.dp))
            Group {
                SwitchRow("Ежедневное напоминание", settings.reminderEnabled) { setReminder(it) }
                if (settings.reminderEnabled) {
                    HorizontalDivider(color = Palette.hairline)
                    ValueRow("Время", timeText(settings.reminderHour, settings.reminderMinute)) {
                        TimePickerDialog(context, { _, hour, minute ->
                            Kvartet.settings.update { it.copy(reminderHour = hour, reminderMinute = minute) }
                            Reminders.reschedule(context)
                        }, settings.reminderHour, settings.reminderMinute, true).show()
                    }
                }
            }
            Hint("Утром придёт тема дня и первая рекомендация.")

            SectionTitle("Сервисы", Modifier.padding(top = 16.dp))
            Group {
                ChoiceRow("Музыка", settings.musicService.title, MusicService.entries.map { it.title }) { index ->
                    Kvartet.settings.update { it.copy(musicService = MusicService.entries[index]) }
                }
                HorizontalDivider(color = Palette.hairline)
                ChoiceRow("Фильмы", settings.filmService.title, FilmService.entries.map { it.title }) { index ->
                    Kvartet.settings.update { it.copy(filmService = FilmService.entries[index]) }
                }
            }

            SectionTitle("Чтение", Modifier.padding(top = 16.dp))
            Group {
                ChoiceRow("Оформление", settings.readerTheme.title, ReaderTheme.entries.map { it.title }) { index ->
                    Kvartet.settings.update { it.copy(readerTheme = ReaderTheme.entries[index]) }
                }
                HorizontalDivider(color = Palette.hairline)
                Column(Modifier.padding(vertical = 12.dp)) {
                    Row {
                        Text("Размер текста", modifier = Modifier.weight(1f))
                        Text("${Math.round(settings.readerTextScale * 100)} %", color = Palette.muted)
                    }
                    Slider(
                        value = settings.readerTextScale,
                        onValueChange = { value -> Kvartet.settings.update { it.copy(readerTextScale = value) } },
                        valueRange = 0.8f..1.6f,
                        steps = 7,
                    )
                }
            }

            SectionTitle("Данные", Modifier.padding(top = 16.dp))
            Group {
                ValueRow("Очистить кэш изображений и статей", "") {
                    context.imageLoader.memoryCache?.clear()
                    context.imageLoader.diskCache?.clear()
                    ArticleCache.clearAll(context)
                    Kvartet.media.clear()
                }
                HorizontalDivider(color = Palette.hairline)
                ValueRow("Начать заново", "", color = Color(0xFFB23B32)) { confirmReset = true }
            }

            SectionTitle("О приложении", Modifier.padding(top = 16.dp))
            Hint(
                "Изображения картин — Wikimedia Commons. Обложки, фрагменты и трейлеры — iTunes Search API, " +
                    "запасной источник постеров — Википедия. Режим чтения — Mozilla Readability (Apache 2.0).",
            )
        }
    }

    if (confirmReset) {
        AlertDialog(
            onDismissRequest = { confirmReset = false },
            title = { Text("Начать заново?") },
            text = { Text("Отметки, оценки, заметки и закладки будут удалены, выпуски начнутся с первого.") },
            confirmButton = {
                TextButton(onClick = {
                    Kvartet.resetProgress()
                    confirmReset = false
                }) { Text("Удалить всё", color = Color(0xFFB23B32)) }
            },
            dismissButton = { TextButton(onClick = { confirmReset = false }) { Text("Отмена") } },
        )
    }
}

@Composable
private fun Group(content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Palette.card).padding(horizontal = 16.dp)) {
        content()
    }
}

@Composable
private fun Hint(text: String) {
    Text(text, color = Palette.muted, fontSize = 13.sp, modifier = Modifier.padding(horizontal = 4.dp))
}

@Composable
private fun SwitchRow(title: String, checked: Boolean, dot: Color? = null, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        dot?.let {
            Box(Modifier.size(10.dp).clip(CircleShape).background(it))
            Spacer(Modifier.width(12.dp))
        }
        Text(title, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

@Composable
private fun ValueRow(title: String, value: String, color: Color = Color.Unspecified, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, modifier = Modifier.weight(1f), color = color)
        Text(value, color = Palette.muted)
    }
}

@Composable
private fun ChoiceRow(title: String, value: String, options: List<String>, onSelect: (Int) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        ValueRow(title, value) { expanded = true }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            options.forEachIndexed { index, option ->
                DropdownMenuItem(text = { Text(option) }, onClick = {
                    expanded = false
                    onSelect(index)
                })
            }
        }
    }
}

/** Приветственный экран при первом запуске. */
@Composable
fun OnboardingScreen() {
    val context = LocalContext.current
    val settings by Kvartet.settings.state.collectAsState()
    val setReminder = rememberReminderSwitch()

    Column(Modifier.fillMaxSize().systemBarsPadding()) {
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 28.dp).padding(top = 40.dp),
        ) {
            QuartetMark()
            Spacer(Modifier.height(20.dp))
            Text("Квартет", fontFamily = Serif, fontWeight = FontWeight.Bold, fontSize = 48.sp)
            Spacer(Modifier.height(8.dp))
            Text("Каждый день — четыре открытия, связанные одной темой.", fontFamily = Serif, color = Palette.muted, fontSize = 22.sp, lineHeight = 29.sp)
            Spacer(Modifier.height(28.dp))
            ItemKind.entries.forEach { kind ->
                Row(Modifier.padding(vertical = 8.dp), verticalAlignment = Alignment.Top) {
                    Box(Modifier.padding(top = 6.dp).size(12.dp).clip(RoundedCornerShape(3.dp)).background(kind.color))
                    Spacer(Modifier.width(14.dp))
                    Column {
                        Text(kind.title, fontWeight = FontWeight.SemiBold, fontSize = 18.sp)
                        Text(kind.onboardingLine, color = Palette.muted)
                    }
                }
            }
            Spacer(Modifier.height(16.dp))
            Text(
                "Отмечайте изученное, ставьте оценки и пишите пару слов — так получится дневник ваших открытий. " +
                    "Виджет покажет выпуск дня прямо на главном экране.",
                color = Palette.muted,
            )
            Spacer(Modifier.height(20.dp))
            Group {
                SwitchRow("Напоминать каждый день в ${timeText(settings.reminderHour, settings.reminderMinute)}", settings.reminderEnabled) {
                    setReminder(it)
                }
            }
            Spacer(Modifier.height(24.dp))
        }
        Button(
            onClick = {
                Kvartet.settings.update { it.copy(onboarded = true) }
                Reminders.reschedule(context)
            },
            modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 12.dp).height(54.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Palette.ink, contentColor = Palette.paper),
        ) { Text("Начать", fontSize = 17.sp, fontWeight = FontWeight.SemiBold) }
    }
}

@Composable
private fun QuartetMark() {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        listOf(listOf(ItemKind.PAINTING, ItemKind.ARTICLE), listOf(ItemKind.ALBUM, ItemKind.FILM)).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                row.forEach { kind -> Box(Modifier.size(30.dp).clip(RoundedCornerShape(7.dp)).background(kind.color)) }
            }
        }
    }
}
