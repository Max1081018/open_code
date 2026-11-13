package dev.rustmodforge.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.List
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import dev.rustmodforge.app.ui.AnalyzerScreen
import dev.rustmodforge.app.ui.ClassViewerScreen
import dev.rustmodforge.app.ui.ConversionScreen
import dev.rustmodforge.app.ui.HomeScreen
import dev.rustmodforge.app.ui.LibraryScreen
import dev.rustmodforge.app.ui.Palette
import dev.rustmodforge.app.ui.ReportScreen
import dev.rustmodforge.app.ui.ResultScreen
import dev.rustmodforge.app.ui.SettingsScreen
import dev.rustmodforge.app.ui.ForgeTheme

/** Where the app is. Project screens carry the project's id. */
sealed class Route {
    object Home : Route()
    object Library : Route()
    object Settings : Route()
    data class Analyzer(val id: String) : Route()
    data class Conversion(val id: String) : Route()
    data class Result(val id: String) : Route()
    data class Report(val id: String, val index: Int) : Route()
    data class Classes(val id: String, val source: Int) : Route()
}

class MainActivity : ComponentActivity() {
    private val vm: ForgeViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= 33) requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 1)
        val shared = sharedUris(intent)
        setContent { ForgeTheme { App(vm, shared) } }
    }

    private fun sharedUris(i: Intent?): List<Uri> = when (i?.action) {
        Intent.ACTION_VIEW -> listOfNotNull(i.data)
        Intent.ACTION_SEND -> listOfNotNull(if (Build.VERSION.SDK_INT >= 33) i.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            else @Suppress("DEPRECATION") i.getParcelableExtra(Intent.EXTRA_STREAM))
        else -> emptyList()
    }
}

@Composable
fun App(vm: ForgeViewModel, shared: List<Uri>) {
    val stack = remember { mutableStateListOf<Route>(Route.Home) }
    val route = stack.last()
    fun go(r: Route) { stack.add(r) }
    fun back() { if (stack.size > 1) stack.removeAt(stack.lastIndex) }
    fun tab(r: Route) { stack.clear(); stack.add(r) }
    BackHandler(enabled = stack.size > 1) { back() }

    val snackbar = remember { SnackbarHostState() }
    val message by vm.message.collectAsState()
    LaunchedEffect(message) { message?.let { snackbar.showSnackbar(it); vm.say(null) } }
    LaunchedEffect(Unit) { if (shared.isNotEmpty()) vm.import(shared) { id -> go(Route.Analyzer(id)) } }

    val topLevel = route is Route.Home || route is Route.Library || route is Route.Settings
    Scaffold(
        containerColor = Palette.Bg,
        snackbarHost = { SnackbarHost(snackbar) },
        bottomBar = {
            if (topLevel) NavigationBar(containerColor = Palette.Surface) {
                val colors = NavigationBarItemDefaults.colors(selectedIconColor = Palette.Ember, selectedTextColor = Palette.Ember, indicatorColor = Palette.SurfaceHigh)
                NavigationBarItem(route is Route.Home, { tab(Route.Home) }, { Icon(Icons.Filled.Home, null) }, label = { Text("Home") }, colors = colors)
                NavigationBarItem(route is Route.Library, { tab(Route.Library) }, { Icon(Icons.Filled.List, null) }, label = { Text("Assets") }, colors = colors)
                NavigationBarItem(route is Route.Settings, { tab(Route.Settings) }, { Icon(Icons.Filled.Settings, null) }, label = { Text("Settings") }, colors = colors)
            }
        },
    ) { pad ->
        Box(Modifier.fillMaxSize().padding(pad)) {
            when (val r = route) {
                Route.Home -> HomeScreen(vm, open = { id, done -> go(if (done) Route.Result(id) else Route.Analyzer(id)) })
                Route.Library -> LibraryScreen(vm)
                Route.Settings -> SettingsScreen(vm)
                is Route.Analyzer -> AnalyzerScreen(vm, r.id, onBack = ::back, onConvert = { go(Route.Conversion(r.id)) },
                    onClasses = { go(Route.Classes(r.id, it)) })
                is Route.Conversion -> ConversionScreen(vm, r.id, onBack = ::back, onDone = { stack.removeAt(stack.lastIndex); go(Route.Result(r.id)) })
                is Route.Result -> ResultScreen(vm, r.id, onBack = ::back, onReport = { go(Route.Report(r.id, it)) },
                    onReconvert = { go(Route.Analyzer(r.id)) })
                is Route.Report -> ReportScreen(vm, r.id, r.index, onBack = ::back)
                is Route.Classes -> ClassViewerScreen(vm, r.id, r.source, onBack = ::back)
            }
        }
    }
}

@Composable
fun BuildIcon() = Icon(Icons.Filled.Build, null)
