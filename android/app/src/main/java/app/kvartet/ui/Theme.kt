package app.kvartet.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import app.kvartet.data.ItemKind

/** Цвета «Квартета»: тёплая бумага, чёрные чернила и по одному акценту на тип. */
object Palette {
    val paper: Color @Composable get() = if (isSystemInDarkTheme()) Color(0xFF111113) else Color(0xFFFAF8F4)
    val card: Color @Composable get() = if (isSystemInDarkTheme()) Color(0xFF1C1C1F) else Color.White
    val ink: Color @Composable get() = if (isSystemInDarkTheme()) Color(0xFFF2EFEA) else Color(0xFF1C1B1A)
    val muted: Color @Composable get() = if (isSystemInDarkTheme()) Color(0xFF9C988F) else Color(0xFF6F6A62)
    val hairline: Color @Composable get() = if (isSystemInDarkTheme()) Color(0xFF2C2C30) else Color(0xFFE6E1D8)
}

fun ItemKind.color(dark: Boolean): Color = when (this) {
    ItemKind.PAINTING -> if (dark) Color(0xFFE3B35A) else Color(0xFFA8741A)
    ItemKind.ARTICLE -> if (dark) Color(0xFF6CC79A) else Color(0xFF2F7A5A)
    ItemKind.ALBUM -> if (dark) Color(0xFF8FA8F0) else Color(0xFF3B5BA9)
    ItemKind.FILM -> if (dark) Color(0xFFEE7B70) else Color(0xFFB23B32)
}

val ItemKind.color: Color @Composable get() = color(isSystemInDarkTheme())

val Serif = FontFamily.Serif

@Composable
fun KvartetTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val paper = if (dark) Color(0xFF111113) else Color(0xFFFAF8F4)
    val ink = if (dark) Color(0xFFF2EFEA) else Color(0xFF1C1B1A)
    val card = if (dark) Color(0xFF1C1C1F) else Color.White
    val scheme = if (dark) {
        darkColorScheme(
            primary = ink, onPrimary = paper, background = paper, onBackground = ink,
            surface = paper, onSurface = ink, surfaceVariant = card, onSurfaceVariant = Color(0xFF9C988F),
            surfaceContainer = card, surfaceContainerHigh = card, secondaryContainer = Color(0xFF2C2C30),
            outline = Color(0xFF3A3A3F), outlineVariant = Color(0xFF2C2C30),
        )
    } else {
        lightColorScheme(
            primary = ink, onPrimary = paper, background = paper, onBackground = ink,
            surface = paper, onSurface = ink, surfaceVariant = card, onSurfaceVariant = Color(0xFF6F6A62),
            surfaceContainer = card, surfaceContainerHigh = card, secondaryContainer = Color(0xFFEDE8DE),
            outline = Color(0xFFCFC8BB), outlineVariant = Color(0xFFE6E1D8),
        )
    }
    val base = Typography()
    val typography = base.copy(
        displaySmall = TextStyle(fontFamily = Serif, fontWeight = FontWeight.Bold, fontSize = 36.sp, lineHeight = 40.sp),
        headlineMedium = TextStyle(fontFamily = Serif, fontWeight = FontWeight.Bold, fontSize = 28.sp, lineHeight = 34.sp),
        titleLarge = TextStyle(fontFamily = Serif, fontWeight = FontWeight.SemiBold, fontSize = 22.sp, lineHeight = 28.sp),
        titleMedium = TextStyle(fontFamily = Serif, fontWeight = FontWeight.SemiBold, fontSize = 18.sp, lineHeight = 24.sp),
    )
    MaterialTheme(colorScheme = scheme, typography = typography, content = content)
}
