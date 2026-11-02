package app.kvartet

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Create
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Home
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import app.kvartet.reader.ReaderScreen
import app.kvartet.ui.ArchiveScreen
import app.kvartet.ui.IssueScreen
import app.kvartet.ui.ItemScreen
import app.kvartet.ui.JournalScreen
import app.kvartet.ui.KvartetTheme
import app.kvartet.ui.OnboardingScreen
import app.kvartet.ui.OpenAction
import app.kvartet.ui.Palette
import app.kvartet.ui.SettingsScreen
import app.kvartet.ui.SlowLookingScreen
import app.kvartet.ui.ZoomScreen
import kotlinx.coroutines.flow.MutableStateFlow
import java.time.LocalDate

class MainActivity : ComponentActivity() {
    /** Ссылка kvartet://…, которую нужно открыть (из виджета, уведомления или браузера). */
    private val pendingLink = MutableStateFlow<Uri?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        Kvartet.init(this)
        pendingLink.value = intent?.data
        setContent {
            KvartetTheme {
                KvartetRoot(pendingLink)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        pendingLink.value = intent.data
    }

    override fun onResume() {
        super.onResume()
        Kvartet.refreshDay()
    }
}

private data class Tab(val route: String, val title: String, val icon: ImageVector)

private val tabs = listOf(
    Tab("today", "Сегодня", Icons.Filled.Home),
    Tab("archive", "Архив", Icons.Filled.DateRange),
    Tab("journal", "Дневник", Icons.Filled.Create),
)

@Composable
private fun KvartetRoot(pendingLink: MutableStateFlow<Uri?>) {
    val settings by Kvartet.settings.state.collectAsState()
    if (!settings.onboarded) {
        Box(Modifier.fillMaxSize()) { OnboardingScreen() }
        return
    }
    val nav = rememberNavController()
    val link by pendingLink.collectAsState()
    LaunchedEffect(link) {
        link?.let {
            handleLink(nav, it)
            pendingLink.value = null
        }
    }
    val backStack by nav.currentBackStackEntryAsState()
    val route = backStack?.destination?.route
    val immersive = route?.startsWith("look") == true || route?.startsWith("zoom") == true

    Scaffold(
        containerColor = Palette.paper,
        bottomBar = {
            if (tabs.any { it.route == route }) {
                NavigationBar(containerColor = Palette.paper) {
                    tabs.forEach { tab ->
                        NavigationBarItem(
                            selected = route == tab.route,
                            onClick = { switchTab(nav, tab.route) },
                            icon = { Icon(tab.icon, contentDescription = null) },
                            label = { Text(tab.title) },
                            colors = NavigationBarItemDefaults.colors(indicatorColor = Palette.hairline),
                        )
                    }
                }
            }
        },
    ) { padding ->
        NavHost(
            navController = nav,
            startDestination = "today",
            modifier = if (immersive) Modifier.fillMaxSize() else Modifier.fillMaxSize().padding(padding),
        ) {
            composable("today") {
                val today by Kvartet.today.collectAsState()
                IssueScreen(
                    date = today,
                    isToday = true,
                    onOpenItem = { nav.navigate("item/${it.id}") },
                    onOpenSettings = { nav.navigate("settings") },
                    onBack = null,
                )
            }
            composable("archive") {
                ArchiveScreen(
                    onOpenDay = { nav.navigate("day/$it") },
                    onOpenItem = { nav.navigate("item/${it.id}") },
                )
            }
            composable("journal") {
                JournalScreen(onOpenItem = { nav.navigate("item/${it.id}") })
            }
            composable("day/{date}", arguments = listOf(navArgument("date") { type = NavType.StringType })) { entry ->
                val date = entry.arguments?.getString("date")?.let { runCatching { LocalDate.parse(it) }.getOrNull() } ?: LocalDate.now()
                IssueScreen(
                    date = date,
                    isToday = date == LocalDate.now(),
                    onOpenItem = { nav.navigate("item/${it.id}") },
                    onOpenSettings = null,
                    onBack = { nav.popBackStack() },
                )
            }
            composable(
                "item/{id}?open={open}",
                arguments = listOf(
                    navArgument("id") { type = NavType.StringType },
                    navArgument("open") {
                        type = NavType.StringType
                        nullable = true
                        defaultValue = null
                    },
                ),
            ) { entry ->
                val item = entry.arguments?.getString("id")?.let { Kvartet.item(it) }
                if (item == null) {
                    LaunchedEffect(Unit) { nav.popBackStack() }
                    return@composable
                }
                val open = entry.arguments?.getString("open")?.let { value ->
                    OpenAction.entries.firstOrNull { it.name.equals(value, ignoreCase = true) }
                }
                // Отложенное действие выполняется один раз — потом стираем его из аргументов.
                entry.arguments?.remove("open")
                ItemScreen(
                    item = item,
                    openAction = open,
                    onBack = { nav.popBackStack() },
                    onRead = { nav.navigate("reader/${item.id}") },
                    onSlowLook = { nav.navigate("look/${item.id}") },
                    onZoom = { nav.navigate("zoom/${item.id}") },
                )
            }
            composable("reader/{id}") { entry ->
                Kvartet.item(entry.arguments?.getString("id").orEmpty())?.let { ReaderScreen(it, onBack = { nav.popBackStack() }) }
            }
            composable("look/{id}") { entry ->
                Kvartet.item(entry.arguments?.getString("id").orEmpty())?.let { SlowLookingScreen(it, onClose = { nav.popBackStack() }) }
            }
            composable("zoom/{id}") { entry ->
                Kvartet.item(entry.arguments?.getString("id").orEmpty())?.let { ZoomScreen(it, onClose = { nav.popBackStack() }) }
            }
            composable("settings") {
                SettingsScreen(onBack = { nav.popBackStack() })
            }
        }
    }
}

private fun switchTab(nav: NavHostController, route: String) {
    nav.navigate(route) {
        popUpTo(nav.graph.findStartDestination().id) { saveState = true }
        launchSingleTop = true
        restoreState = true
    }
}

/** kvartet://today, kvartet://archive, kvartet://journal, kvartet://settings, kvartet://item/<id>[?open=reader|look|zoom]. */
private fun handleLink(nav: NavHostController, uri: Uri) {
    if (uri.scheme != "kvartet") return
    when (uri.host) {
        "item" -> {
            val id = uri.pathSegments.firstOrNull() ?: return
            if (Kvartet.item(id) == null) return
            switchTab(nav, "today")
            val open = uri.getQueryParameter("open")
            nav.navigate(if (open != null) "item/$id?open=$open" else "item/$id")
        }
        "archive" -> switchTab(nav, "archive")
        "journal" -> switchTab(nav, "journal")
        "settings" -> {
            switchTab(nav, "today")
            nav.navigate("settings")
        }
        else -> switchTab(nav, "today")
    }
}
