@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package dev.rustmodforge.app.ui

import android.graphics.BitmapFactory
import android.media.MediaPlayer
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.rustmodforge.app.ForgeViewModel
import dev.rustmodforge.app.ProjectDetail
import dev.rustmodforge.core.archive.SafeArchive
import dev.rustmodforge.core.bytecode.Disassembler
import dev.rustmodforge.core.geo.GeoParser
import dev.rustmodforge.core.model.ResourceKind
import dev.rustmodforge.core.model.ResourceRef
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

private enum class AssetTab(val label: String, val kinds: Set<ResourceKind>) {
    MODELS("Models", setOf(ResourceKind.GEO_MODEL, ResourceKind.BLOCK_MODEL, ResourceKind.ITEM_MODEL_DEFINITION, ResourceKind.BLOCKSTATE)),
    TEXTURES("Textures", setOf(ResourceKind.TEXTURE)),
    ANIMATIONS("Animations", setOf(ResourceKind.GECKO_ANIMATION, ResourceKind.BEDROCK_ANIMATION_CONTROLLER)),
    SOUNDS("Sounds", setOf(ResourceKind.SOUND, ResourceKind.SOUND_DEFINITIONS)),
    PARTICLES("Particles", setOf(ResourceKind.PARTICLE_DEFINITION)),
    OTHER("Other", emptySet()),
}

private fun jarOf(vm: ForgeViewModel, d: ProjectDetail, index: Int): File = File(vm.project(d.state.id).input, d.state.sources[index].fileName)

@Composable
fun LibraryScreen(vm: ForgeViewModel) {
    val projects by vm.projects.collectAsState()
    var selected by remember { mutableStateOf<String?>(null) }
    var detail by remember { mutableStateOf<ProjectDetail?>(null) }
    var source by remember { mutableStateOf(0) }
    var tab by remember { mutableStateOf(AssetTab.TEXTURES) }
    var open by remember { mutableStateOf<ResourceRef?>(null) }
    LaunchedEffect(selected) { detail = selected?.let { vm.detail(it) }; source = 0; open = null }
    LaunchedEffect(projects) { if (selected == null) selected = projects.firstOrNull()?.state?.id }

    Column(Modifier.fillMaxSize()) {
        Text("Asset library", style = MaterialTheme.typography.headlineSmall, color = Palette.Text, modifier = Modifier.padding(16.dp))
        if (projects.isEmpty()) { Text("Import a mod to browse its models, textures, animations and sounds.", color = Palette.Muted, modifier = Modifier.padding(16.dp)); return@Column }
        Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            projects.forEach { p -> FilterChip(selected = selected == p.state.id, onClick = { selected = p.state.id }, label = { Text(p.state.name) }) }
        }
        val d = detail ?: return@Column
        if (d.analyses.isEmpty()) { Text("This project has not been analysed yet.", color = Palette.Muted, modifier = Modifier.padding(16.dp)); return@Column }
        if (d.analyses.size > 1) Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            d.analyses.forEachIndexed { i, a -> FilterChip(selected = source == i, onClick = { source = i; open = null }, label = { Text(a.metadata.name) }) }
        }
        val a = d.analyses[source.coerceIn(0, d.analyses.lastIndex)]
        Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            AssetTab.entries.forEach { t -> FilterChip(selected = tab == t, onClick = { tab = t; open = null }, label = { Text(t.label) }) }
        }
        val known = AssetTab.entries.flatMap { it.kinds }.toSet()
        val list = a.resources.filter { r ->
            if (tab == AssetTab.OTHER) (r.path.startsWith("assets/") || r.path.startsWith("data/")) && r.kind !in known else r.kind in tab.kinds
        }
        val jar = jarOf(vm, d, source)
        val o = open
        if (o != null) {
            AssetDetail(jar, o, onClose = { open = null })
        } else {
            Text("${list.size} files", color = Palette.Muted, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
            LazyColumn(Modifier.weight(1f)) {
                items(list, key = { it.path }) { r ->
                    Row(Modifier.fillMaxWidth().clickable { open = r }.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        if (r.kind == ResourceKind.TEXTURE) Thumb(jar, r.path, 40)
                        Spacer(Modifier.size(10.dp))
                        Column(Modifier.weight(1f)) {
                            Text(r.path.substringAfterLast('/'), color = Palette.Text)
                            Text(r.path.substringBeforeLast('/') + " · " + bytes(r.size), color = Palette.Muted, fontSize = 11.sp)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun Thumb(jar: File, path: String, sizeDp: Int) {
    val image by produceState<ImageBitmap?>(null, jar, path) {
        value = withContext(Dispatchers.IO) {
            runCatching {
                SafeArchive.open(jar).use { a ->
                    val bytes = a.readBytes(path)
                    val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
                    // Bounded decode: never more than 1024 px a side in memory.
                    var sample = 1
                    while (opts.outWidth / sample > 1024 || opts.outHeight / sample > 1024) sample *= 2
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })?.asImageBitmap()
                }
            }.getOrNull()
        }
    }
    val img = image
    if (img != null) Image(img, null, Modifier.size(sizeDp.dp).background(Palette.SurfaceHigh), contentScale = ContentScale.Fit, filterQuality = FilterQuality.None)
    else Spacer(Modifier.size(sizeDp.dp).background(Palette.SurfaceHigh))
}

@Composable
private fun AssetDetail(jar: File, r: ResourceRef, onClose: () -> Unit) {
    val context = LocalContext.current
    var player by remember { mutableStateOf<MediaPlayer?>(null) }
    DisposableEffect(r.path) { onDispose { player?.release() } }
    val text by produceState("", jar, r.path) {
        value = withContext(Dispatchers.IO) {
            runCatching {
                SafeArchive.open(jar).use { a ->
                    when (r.kind) {
                        ResourceKind.GEO_MODEL -> GeoParser.parseGeometry(a.readText(r.path), r.path).joinToString("\n\n") { m ->
                            "${m.identifier} · texture ${m.textureWidth}×${m.textureHeight} · ${m.bones.size} bones · ${m.cubeCount} cubes\n" +
                                m.bones.joinToString("\n") { b -> "  ${b.name}${b.parent?.let { " ← $it" } ?: ""} · pivot ${b.pivot} · ${b.cubes.size} cubes" } +
                                m.warnings.joinToString("") { "\n  ⚠ $it" }
                        }
                        ResourceKind.GECKO_ANIMATION -> GeoParser.parseAnimations(a.readText(r.path)).joinToString("\n") { an ->
                            "${an.name.substringAfterLast('.')}: ${an.length}s ${an.loop.name.lowercase()} · ${an.bones.size} bones" +
                                (if (an.sounds.isNotEmpty()) " · sounds ${an.sounds.joinToString { it.effect }}" else "")
                        }
                        ResourceKind.TEXTURE, ResourceKind.SOUND -> ""
                        else -> if (r.size < 200_000) a.readText(r.path) else "(${bytes(r.size)}: too large to show)"
                    }
                }
            }.getOrElse { "Could not read: ${it.message}" }
        }
    }
    Column(Modifier.fillMaxSize().padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(r.path.substringAfterLast('/'), color = Palette.Ember, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
            androidx.compose.material3.TextButton(onClick = onClose) { Text("Back") }
        }
        Text(r.path, color = Palette.Muted, fontSize = 11.sp)
        Spacer(Modifier.height(10.dp))
        when (r.kind) {
            ResourceKind.TEXTURE -> Thumb(jar, r.path, 256)
            ResourceKind.SOUND -> IconButton(onClick = {
                runCatching {
                    player?.release()
                    val tmp = File(context.cacheDir, "preview." + r.path.substringAfterLast('.'))
                    SafeArchive.open(jar).use { a -> tmp.writeBytes(a.readBytes(r.path)) }
                    player = MediaPlayer().apply { setDataSource(tmp.path); prepare(); start() }
                }
            }) { Icon(Icons.Filled.PlayArrow, "Play", tint = Palette.Ember) }
            else -> {}
        }
        SelectionContainer(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            Text(text, fontFamily = FontFamily.Monospace, fontSize = 11.sp, color = Palette.Text)
        }
    }
}

@Composable
fun ClassViewerScreen(vm: ForgeViewModel, id: String, source: Int, onBack: () -> Unit) {
    var detail by remember { mutableStateOf<ProjectDetail?>(null) }
    LaunchedEffect(id) { detail = vm.detail(id) }
    var query by remember { mutableStateOf("") }
    var open by remember { mutableStateOf<String?>(null) }
    val d = detail
    Column(Modifier.fillMaxSize()) {
        ProjectTopBar(open?.substringAfterLast('.') ?: "Classes", onBack = { if (open != null) open = null else onBack() })
        if (d == null || d.analyses.size <= source) return@Column
        val a = d.analyses[source]
        val o = open
        if (o != null) {
            val jar = jarOf(vm, d, source)
            val text by produceState("Disassembling…", o) {
                value = withContext(Dispatchers.IO) { runCatching { SafeArchive.open(jar).use { Disassembler.disassemble(it, o.replace('.', '/')) } }.getOrElse { "Could not read: ${it.message}" } }
            }
            SelectionContainer(Modifier.weight(1f).verticalScroll(rememberScrollState()).horizontalScroll(rememberScrollState()).padding(12.dp)) {
                Text(text, fontFamily = FontFamily.Monospace, fontSize = 11.sp, color = Palette.Text)
            }
            return@Column
        }
        OutlinedTextField(query, { query = it }, label = { Text("Search classes") }, singleLine = true, modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp))
        val list = a.classes.filter { query.isBlank() || it.name.contains(query, ignoreCase = true) }.sortedBy { it.name }
        LazyColumn(Modifier.weight(1f)) {
            items(list.take(2000), key = { it.name }) { c ->
                Column(Modifier.fillMaxWidth().clickable { open = c.name }.padding(horizontal = 16.dp, vertical = 8.dp)) {
                    Text(c.name.substringAfterLast('.'), color = Palette.Text)
                    Text(c.name.substringBeforeLast('.') + (c.vanillaBase?.let { " · extends $it" } ?: "") + " · ${c.methodCount} methods",
                        color = Palette.Muted, fontSize = 11.sp)
                }
            }
        }
    }
}
