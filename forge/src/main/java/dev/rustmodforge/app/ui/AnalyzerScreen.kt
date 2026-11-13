@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package dev.rustmodforge.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import dev.rustmodforge.app.ForgeViewModel
import dev.rustmodforge.app.ProjectDetail
import dev.rustmodforge.core.compat.TargetId
import dev.rustmodforge.core.model.DependencyKind
import dev.rustmodforge.core.model.GoalSelectorKind
import dev.rustmodforge.core.model.ModAnalysis
import dev.rustmodforge.core.model.RegistryKind
import dev.rustmodforge.core.model.ResourceKind
import dev.rustmodforge.core.pipeline.Quality

@Composable
fun ProjectTopBar(title: String, onBack: () -> Unit) {
    TopAppBar(
        title = { Text(title, maxLines = 1) },
        navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.Filled.ArrowBack, "Back") } },
        colors = TopAppBarDefaults.topAppBarColors(containerColor = Palette.Bg, titleContentColor = Palette.Text, navigationIconContentColor = Palette.Text),
    )
}

@Composable
fun AnalyzerScreen(vm: ForgeViewModel, id: String, onBack: () -> Unit, onConvert: () -> Unit, onClasses: (Int) -> Unit) {
    val work by vm.work(id).collectAsState(initial = null)
    var detail by remember { mutableStateOf<ProjectDetail?>(null) }
    LaunchedEffect(id, work?.finished, work?.failed) { detail = vm.detail(id) }
    var tab by remember { mutableIntStateOf(0) }
    val d = detail

    Column(Modifier.fillMaxSize()) {
        ProjectTopBar(d?.state?.name ?: "Mod analyzer", onBack)
        val w = work
        if (d == null || (d.analyses.size < d.state.sources.size && w?.failed != true)) {
            Column(Modifier.fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                CircularProgressIndicator(color = Palette.Ember)
                Spacer(Modifier.height(16.dp))
                Text(w?.stage?.ifEmpty { "Analysing" } ?: "Analysing", color = Palette.Text)
                Text(w?.detail ?: "", color = Palette.Muted, style = MaterialTheme.typography.bodySmall)
                if (w != null) LinearProgressIndicator(progress = { w.fraction }, modifier = Modifier.fillMaxWidth().padding(top = 12.dp), color = Palette.Ember)
                Spacer(Modifier.height(16.dp))
                OutlinedButton(onClick = { vm.cancel(id) }) { Text("Cancel") }
            }
            return@Column
        }
        if (d.analyses.isEmpty()) {
            SectionCard("Analysis did not finish", subtitle = w?.error ?: d.state.lastError ?: "") {
                Button(onClick = { vm.reanalyze(id) }) { Text("Analyse again") }
            }
            return@Column
        }
        if (d.analyses.size > 1) {
            LazyRow(Modifier.padding(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items(d.analyses.size) { i -> FilterChip(selected = tab == i, onClick = { tab = i }, label = { Text(d.analyses[i].metadata.name) }) }
            }
        }
        val a = d.analyses[tab.coerceIn(0, d.analyses.lastIndex)]
        LazyColumn(Modifier.weight(1f)) {
            item { Overview(a) }
            item { Dependencies(a) }
            item { Entities(a) }
            item { Registered(a) }
            item { Assets(a) }
            item {
                SectionCard("Java classes", subtitle = "${a.classes.size} classes, parsed with ASM and never executed") {
                    a.classes.groupBy { it.vanillaBase ?: "other" }.entries.sortedByDescending { it.value.size }.take(8).forEach { (k, v) -> KeyValue(k, "${v.size}") }
                    Spacer(Modifier.height(8.dp))
                    OutlinedButton(onClick = { onClasses(d.analyses.indexOf(a)) }) { Text("Browse classes and bytecode") }
                }
            }
            item { Unsupported(a) }
            if (a.warnings.isNotEmpty()) item { SectionCard("Warnings") { a.warnings.forEach { Bullet(it, Palette.Partial) } } }
            item { ConvertPanel(vm, d, onConvert) }
            item { Spacer(Modifier.height(24.dp)) }
        }
    }
}

@Composable
private fun Overview(a: ModAnalysis) {
    val m = a.metadata
    SectionCard(m.name, subtitle = m.description.take(240)) {
        KeyValue("Mod id", m.modId, mono = true)
        KeyValue("Version", m.version)
        KeyValue("Loader", m.loader.name.lowercase().replace('_', ' '))
        KeyValue("Minecraft", m.minecraftVersion.ifEmpty { "not declared" })
        if (m.loaderVersion.isNotEmpty()) KeyValue("Loader version", m.loaderVersion)
        if (m.authors.isNotEmpty()) KeyValue("Authors", m.authors.joinToString())
        if (m.license.isNotEmpty()) KeyValue("Licence", m.license)
        KeyValue("File", "${a.sourceFile} (${bytes(a.resources.sumOf { it.size })} unpacked)")
        KeyValue("SHA-256", a.sha256.take(24) + "…", mono = true)
        Spacer(Modifier.height(6.dp))
        Text("Horizon runs Minecraft 26.3. Java code never runs there: RustMod Forge rebuilds what it can from the code's behaviour.",
            color = Palette.Muted, style = MaterialTheme.typography.bodySmall)
    }
}

@Composable
private fun Dependencies(a: ModAnalysis) {
    SectionCard("Dependencies", subtitle = "${a.metadata.dependencies.size} declared, ${a.nested.size} nested jars") {
        if (a.metadata.dependencies.isEmpty()) Text("None declared", color = Palette.Muted)
        a.metadata.dependencies.forEach { dep ->
            val color = when (dep.kind) {
                DependencyKind.REQUIRED -> Palette.Steel; DependencyKind.OPTIONAL -> Palette.Muted
                DependencyKind.INCOMPATIBLE -> Palette.Bad; DependencyKind.EMBEDDED -> Palette.Good
            }
            Row(Modifier.fillMaxWidth().padding(vertical = 3.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(dep.id, color = Palette.Text, modifier = Modifier.weight(1f))
                Text(dep.versionRange, color = Palette.Muted, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(end = 8.dp))
                Pill(dep.kind.name.lowercase(), color)
            }
        }
        a.nested.forEach { n -> Bullet("Nested: ${n.metadata.name} ${n.metadata.version} (${n.metadata.loader.name.lowercase()})") }
    }
}

@Composable
private fun Entities(a: ModAnalysis) {
    if (a.entities.isEmpty()) return
    SectionCard("Entities", subtitle = "${a.entities.size} found from registrations and class hierarchy") {
        a.entities.forEach { e ->
            Text(e.id, color = Palette.Ember, fontWeight = FontWeight.SemiBold)
            KeyValue("Class", e.className.substringAfterLast('.'))
            KeyValue("Extends", e.vanillaBase + if (e.usesGeckoLib) " · GeckoLib" else "")
            if (e.width != null) KeyValue("Size", "${e.width} × ${e.height} blocks")
            if (e.attributes.isNotEmpty()) KeyValue("Attributes", e.attributes.entries.joinToString { "${it.key.removePrefix("minecraft:")} ${it.value}" })
            if (e.goals.isNotEmpty()) {
                Text("AI goals", color = Palette.Muted, style = MaterialTheme.typography.labelMedium, modifier = Modifier.padding(top = 6.dp))
                e.goals.forEach { g ->
                    val sel = if (g.selector == GoalSelectorKind.TARGET) "target" else "goal"
                    Bullet("$sel ${g.priority}: ${g.goal.substringAfterLast('.')}${if (g.args.isNotEmpty()) "(${g.args.joinToString()})" else ""}${if (g.custom) " · custom" else ""}")
                }
            }
            if (e.traits.isNotEmpty()) {
                Text("Behaviours recognised", color = Palette.Muted, style = MaterialTheme.typography.labelMedium, modifier = Modifier.padding(top = 6.dp))
                e.traits.forEach { t ->
                    Bullet("${t.kind.name.lowercase().replace('_', ' ')}${if (t.params.isNotEmpty()) " " + t.params.entries.joinToString { "${it.key}=${it.value}" } else ""}")
                    t.evidence.take(2).forEach { ev -> Text("   $ev", color = Palette.Muted, style = MaterialTheme.typography.bodySmall) }
                }
            }
            val s = e.sounds
            val sounds = listOfNotNull(s.ambient?.let { "ambient $it" }, s.hurt?.let { "hurt $it" }, s.death?.let { "death $it" }) + s.other
            if (sounds.isNotEmpty()) KeyValue("Sounds", sounds.distinct().joinToString())
            listOfNotNull(e.geoModel, e.animationFile, e.texture, e.javaModelLayer).forEach { KeyValue("Asset", it.substringAfterLast('/')) }
            e.spawn?.let { KeyValue("Spawns", "weight ${it.weight ?: "?"} in ${it.biomes.joinToString()}") }
            e.unresolved.forEach { Bullet(it, Palette.Partial) }
            Spacer(Modifier.height(12.dp))
        }
    }
}

@Composable
private fun Registered(a: ModAnalysis) {
    val byKind = a.registrations.groupBy { it.kind }
    if (byKind.isEmpty()) return
    SectionCard("Registrations", subtitle = "Read from DeferredRegister / Registry.register calls") {
        for (k in listOf(RegistryKind.ITEM, RegistryKind.BLOCK, RegistryKind.SOUND_EVENT, RegistryKind.BLOCK_ENTITY, RegistryKind.PARTICLE_TYPE, RegistryKind.MOB_EFFECT, RegistryKind.OTHER)) {
            val list = byKind[k] ?: continue
            Text("${k.name.lowercase().replace('_', ' ')} (${list.size})", color = Palette.Muted, style = MaterialTheme.typography.labelMedium)
            list.take(40).forEach { MonoLine(it.id) }
            if (list.size > 40) Text("… ${list.size - 40} more", color = Palette.Muted)
        }
    }
}

@Composable
private fun Assets(a: ModAnalysis) {
    SectionCard("Assets and data") {
        val kinds = a.resources.groupBy { it.kind }
        for ((k, label) in listOf(ResourceKind.TEXTURE to "Textures", ResourceKind.BLOCK_MODEL to "Models", ResourceKind.GEO_MODEL to "GeckoLib models",
            ResourceKind.GECKO_ANIMATION to "Animations", ResourceKind.SOUND to "Sounds", ResourceKind.PARTICLE_DEFINITION to "Particles",
            ResourceKind.LANG to "Languages", ResourceKind.RECIPE to "Recipes", ResourceKind.LOOT_TABLE to "Loot tables", ResourceKind.TAG to "Tags",
            ResourceKind.ADVANCEMENT to "Advancements", ResourceKind.WORLDGEN to "World generation", ResourceKind.STRUCTURE_NBT to "Structures",
            ResourceKind.BIOME_MODIFIER to "Biome modifiers", ResourceKind.SHADER to "Shaders")) {
            val n = kinds[k]?.size ?: 0
            if (n > 0) KeyValue(label, "$n")
        }
        KeyValue("Sound events", "${a.sounds.size}")
    }
}

@Composable
private fun Unsupported(a: ModAnalysis) {
    if (a.unsupportedApis.isEmpty() && a.mixins.isEmpty()) return
    SectionCard("Unsupported features", subtitle = "These have no Horizon equivalent and are reported, not dropped silently") {
        a.unsupportedApis.forEach { u ->
            Text(u.api, color = Palette.Bad, fontWeight = FontWeight.Medium)
            Text(u.why, color = Palette.Muted, style = MaterialTheme.typography.bodySmall)
            Text(u.classes.take(3).joinToString { it.substringAfterLast('.') } + if (u.classes.size > 3) " +${u.classes.size - 3}" else "", color = Palette.Text, style = MaterialTheme.typography.bodySmall)
            Spacer(Modifier.height(6.dp))
        }
        a.mixins.forEach { m -> Bullet("Mixin ${m.mixinClass.substringAfterLast('.')} → ${m.targets.joinToString { it.substringAfterLast('.') }}", Palette.Partial) }
    }
}

@Composable
private fun ConvertPanel(vm: ForgeViewModel, d: ProjectDetail, onConvert: () -> Unit) {
    var quality by remember(d.state.id) { mutableStateOf(d.state.quality) }
    var android by remember(d.state.id) { mutableStateOf(TargetId.HORIZON_ANDROID in d.state.targets) }
    var desktop by remember(d.state.id) { mutableStateOf(TargetId.HORIZON_DESKTOP in d.state.targets) }
    SectionCard("Convert", subtitle = "Choose how far to go and for which Horizon") {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Quality.entries.forEach { q -> FilterChip(selected = quality == q, onClick = { quality = q }, label = { Text(q.label) }) }
        }
        Text(quality.description, color = Palette.Muted, style = MaterialTheme.typography.bodySmall)
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(selected = android, onClick = { android = !android }, label = { Text("Horizon Android (.hmod)") })
            FilterChip(selected = desktop, onClick = { desktop = !desktop }, label = { Text("Desktop (.hmod + .hnmod)") })
        }
        Text("Horizon Android imports .hmod files only. The desktop native mod is Rust source that the desktop launcher compiles.",
            color = Palette.Muted, style = MaterialTheme.typography.bodySmall)
        Spacer(Modifier.height(12.dp))
        Button(
            onClick = {
                vm.convert(d.state.id, quality, buildList { if (android) add(TargetId.HORIZON_ANDROID); if (desktop) add(TargetId.HORIZON_DESKTOP) })
                onConvert()
            },
            enabled = android || desktop,
            colors = ButtonDefaults.buttonColors(containerColor = Palette.Ember),
            modifier = Modifier.fillMaxWidth(),
        ) { Text("Start conversion") }
    }
}
