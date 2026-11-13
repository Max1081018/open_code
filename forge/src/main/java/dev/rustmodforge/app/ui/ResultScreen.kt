@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package dev.rustmodforge.app.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.rustmodforge.app.ForgeViewModel
import dev.rustmodforge.app.ProjectDetail
import dev.rustmodforge.app.data.Exports
import dev.rustmodforge.core.compat.HorizonCompat
import dev.rustmodforge.core.compat.Support
import dev.rustmodforge.core.report.ConversionReport
import dev.rustmodforge.core.report.FeatureStatus
import java.io.File

@Composable
fun ResultScreen(vm: ForgeViewModel, id: String, onBack: () -> Unit, onReport: (Int) -> Unit, onReconvert: () -> Unit) {
    var detail by remember { mutableStateOf<ProjectDetail?>(null) }
    LaunchedEffect(id) { detail = vm.detail(id) }
    var tab by remember { mutableIntStateOf(0) }
    val d = detail
    Column(Modifier.fillMaxSize()) {
        ProjectTopBar(d?.state?.name ?: "Result", onBack)
        if (d == null) return@Column
        if (d.reports.isEmpty()) {
            SectionCard("No result yet", subtitle = d.state.lastError ?: "This project has not finished a conversion.") {
                Button(onClick = onReconvert) { Text("Open the analyzer") }
            }
            return@Column
        }
        if (d.reports.size > 1) {
            LazyRow(Modifier.padding(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items(d.reports.size) { i -> FilterChip(selected = tab == i, onClick = { tab = i }, label = { Text(d.reports[i].modName) }) }
            }
        }
        val r = d.reports[tab.coerceIn(0, d.reports.lastIndex)]
        LazyColumn(Modifier.weight(1f)) {
            item { Summary(r) }
            item { Outputs(vm, r, d) }
            item { BuildSteps(r) }
            item { Features(r) }
            if (r.dependencies.isNotEmpty()) item {
                SectionCard("Dependencies") { r.dependencies.forEach { KeyValue(it.id, "${it.status}: ${it.note}") } }
            }
            item { Compatibility() }
            if (r.warnings.isNotEmpty()) item {
                SectionCard("Warnings", subtitle = "${r.warnings.size}") { r.warnings.take(60).forEach { Bullet(it, Palette.Partial) } }
            }
            item {
                Row(Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    OutlinedButton(onClick = { onReport(tab) }) { Text("Full report") }
                    OutlinedButton(onClick = onReconvert) { Text("Convert again") }
                }
            }
        }
    }
}

@Composable
private fun Summary(r: ConversionReport) {
    val counts = FeatureStatus.entries.associateWith { s -> r.features.count { it.status == s } }
    SectionCard(r.modName, subtitle = "${r.loader.lowercase()} · Minecraft ${r.minecraftVersion.ifEmpty { "?" }} → Horizon 26.3 · ${r.quality}") {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Pill("${counts[FeatureStatus.IMPLEMENTED]} implemented", Palette.Good)
            Pill("${counts[FeatureStatus.PARTIAL]} partial", Palette.Partial)
            Pill("${counts[FeatureStatus.UNSUPPORTED]} unsupported", Palette.Bad)
        }
        Spacer(Modifier.height(8.dp))
        r.analysis.forEach { Bullet(it) }
        if (r.aiUsage.isNotEmpty()) { Spacer(Modifier.height(6.dp)); Text("AI: " + r.aiUsage.lines().first(), color = Palette.Muted, style = MaterialTheme.typography.bodySmall) }
    }
}

@Composable
private fun Outputs(vm: ForgeViewModel, r: ConversionReport, d: ProjectDetail) {
    val context = LocalContext.current
    val settings by vm.settings.state.collectAsState()
    var pending by remember { mutableStateOf<File?>(null) }
    val save = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/octet-stream")) { uri ->
        val f = pending
        if (uri != null && f != null) vm.exportToUri(f, uri)
        pending = null
    }
    SectionCard("Export", subtitle = "Files are checked before they are offered. A passed check is not an in-game test.") {
        val files = r.outputs.map { File(it.path) }.filter { it.exists() }
        if (files.isEmpty()) Text("No output files", color = Palette.Muted)
        files.forEach { f ->
            val out = r.outputs.first { it.path == f.path }
            Text(f.name, color = Palette.Text, fontWeight = FontWeight.Medium)
            Text("${out.kind} · ${out.target} · ${bytes(f.length())}", color = Palette.Muted, style = MaterialTheme.typography.bodySmall)
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (f.name.endsWith("-android.hmod")) {
                    Button(onClick = { vm.exportToHorizon(f) }, colors = ButtonDefaults.buttonColors(containerColor = Palette.Ember)) { Text("To Horizon Mods") }
                }
                OutlinedButton(onClick = { pending = f; save.launch(f.name) }) { Text("Save as…") }
                OutlinedButton(onClick = { runCatching { Exports.share(context, f) }.onFailure { vm.say("Share failed: ${it.message}") } }) { Text("Share") }
            }
            Spacer(Modifier.height(10.dp))
        }
        val reportFile = d.outputs.firstOrNull { it.name.endsWith("-report.md") }
        if (reportFile != null) TextButton(onClick = { pending = reportFile; save.launch(reportFile.name) }) { Text("Save the report (Markdown)") }
        Spacer(Modifier.height(6.dp))
        val installed = Exports.launcherIntent(context, settings.launcherPackage) != null
        if (installed) {
            OutlinedButton(onClick = { Exports.openLauncher(context, settings.launcherPackage) }) { Text("Open Horizon Android") }
        } else {
            Text("Horizon Android is not installed on this phone.", color = Palette.Muted, style = MaterialTheme.typography.bodySmall)
        }
        Spacer(Modifier.height(8.dp))
        Text("Import into Horizon Android", color = Palette.Steel, fontWeight = FontWeight.Medium)
        HorizonCompat.android.importGuide.forEachIndexed { i, line -> Text("${i + 1}. $line", color = Palette.Text, style = MaterialTheme.typography.bodySmall) }
    }
}

@Composable
private fun BuildSteps(r: ConversionReport) {
    SectionCard("Build and validation") {
        r.build.forEach { s ->
            Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.Top) {
                Column(Modifier.weight(1f)) {
                    Text(s.name + if (s.target.isNotEmpty()) " (${s.target})" else "", color = Palette.Text)
                    if (s.detail.isNotEmpty()) Text(s.detail, color = Palette.Muted, style = MaterialTheme.typography.bodySmall)
                }
                Pill(s.status.name.lowercase().replace('_', ' '), s.status.color())
            }
        }
    }
}

@Composable
private fun Features(r: ConversionReport) {
    var filter by remember { mutableStateOf<FeatureStatus?>(null) }
    SectionCard("Reconstruction", subtitle = "Every feature with its status and the reason it is not complete") {
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(selected = filter == null, onClick = { filter = null }, label = { Text("All") })
            listOf(FeatureStatus.IMPLEMENTED, FeatureStatus.PARTIAL, FeatureStatus.UNSUPPORTED).forEach { s ->
                FilterChip(selected = filter == s, onClick = { filter = s }, label = { Text(s.label()) })
            }
        }
        val list = r.features.filter { filter == null || it.status == filter }
        list.groupBy { it.category }.forEach { (category, items) ->
            Text(category, color = Palette.Steel, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 10.dp))
            items.forEach { f ->
                Column(Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(f.name + if (f.target.isNotEmpty()) " · ${f.target}" else "", color = Palette.Text, modifier = Modifier.weight(1f))
                        Pill(f.status.label(), f.status.color())
                    }
                    if (f.route.isNotEmpty()) Text("How: ${f.route}", color = Palette.Muted, style = MaterialTheme.typography.bodySmall)
                    if (f.reason.isNotEmpty()) Text("Why: ${f.reason}", color = Palette.Partial.copy(alpha = 0.9f), style = MaterialTheme.typography.bodySmall)
                }
            }
        }
    }
}

@Composable
private fun Compatibility() {
    SectionCard("Compatibility check", subtitle = "What each Horizon can load, from its source at the pinned revision") {
        for (p in listOf(HorizonCompat.android, HorizonCompat.desktop)) {
            Text(p.name, color = Palette.Ember, fontWeight = FontWeight.Medium)
            Text("${p.repository} @ ${p.revision.take(10)}", color = Palette.Muted, fontFamily = FontFamily.Monospace, fontSize = 11.sp)
            p.capabilities.forEach { c ->
                val color = when (c.support) { Support.SUPPORTED -> Palette.Good; Support.PARTIAL -> Palette.Partial; Support.UNSUPPORTED -> Palette.Bad }
                Row(Modifier.fillMaxWidth().padding(vertical = 2.dp)) {
                    Text(c.key, color = Palette.Text, style = MaterialTheme.typography.bodySmall, modifier = Modifier.weight(1f))
                    Pill(c.support.name.lowercase(), color)
                }
                Text(c.note, color = Palette.Muted, style = MaterialTheme.typography.bodySmall)
            }
            Spacer(Modifier.height(10.dp))
        }
    }
}

@Composable
fun ReportScreen(vm: ForgeViewModel, id: String, index: Int, onBack: () -> Unit) {
    var text by remember { mutableStateOf("") }
    LaunchedEffect(id, index) { text = vm.detail(id)?.reports?.getOrNull(index)?.toMarkdown() ?: "No report" }
    Column(Modifier.fillMaxSize()) {
        ProjectTopBar("Report", onBack)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(16.dp)) {
            text.lines().forEach { line ->
                when {
                    line.startsWith("# ") -> Text(line.removePrefix("# "), style = MaterialTheme.typography.headlineSmall, color = Palette.Ember)
                    line.startsWith("## ") -> Text(line.removePrefix("## "), style = MaterialTheme.typography.titleLarge, color = Palette.Text, modifier = Modifier.padding(top = 12.dp))
                    line.startsWith("### ") -> Text(line.removePrefix("### "), style = MaterialTheme.typography.titleMedium, color = Palette.Steel, modifier = Modifier.padding(top = 8.dp))
                    line.startsWith("|") -> Text(line.trim('|').split(" | ").joinToString("  ·  ").replace("\\|", "|"), fontSize = 12.sp, color = Palette.Text)
                    else -> Text(line, style = MaterialTheme.typography.bodySmall, color = Palette.Text)
                }
            }
        }
    }
}
