@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package dev.rustmodforge.app.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import dev.rustmodforge.app.ForgeViewModel
import dev.rustmodforge.app.ProjectSummary
import dev.rustmodforge.core.compat.TargetId
import dev.rustmodforge.core.pipeline.Quality
import dev.rustmodforge.core.pipeline.Stage
import dev.rustmodforge.core.pipeline.StageState
import java.text.DateFormat
import java.util.Date

private val mimeTypes = arrayOf("application/java-archive", "application/x-java-archive", "application/zip", "application/octet-stream")

@Composable
fun HomeScreen(vm: ForgeViewModel, open: (id: String, done: Boolean) -> Unit) {
    val projects by vm.projects.collectAsState()
    val busy by vm.busy.collectAsState()
    val settings by vm.settings.state.collectAsState()
    val one = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri -> if (uri != null) vm.import(listOf(uri)) { open(it, false) } }
    val many = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris -> if (uris.isNotEmpty()) vm.import(uris) { open(it, false) } }
    var deleting by remember { mutableStateOf<ProjectSummary?>(null) }

    LazyColumn(Modifier.fillMaxWidth()) {
        item {
            Box(
                Modifier.fillMaxWidth().padding(16.dp).clip(RoundedCornerShape(20.dp))
                    .background(Brush.linearGradient(listOf(Palette.SurfaceHigh, androidx.compose.ui.graphics.Color(0xFF2A1A0E))))
                    .padding(20.dp),
            ) {
                Column {
                    Text("RustMod Forge", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold, color = Palette.Ember)
                    Text("Rebuild Minecraft Java mods for Horizon", style = MaterialTheme.typography.bodyLarge, color = Palette.Text)
                    Spacer(Modifier.height(4.dp))
                    Text("Inspects the jar's bytecode and assets on your phone (nothing is run), reconstructs what Horizon can load, validates it and tells you exactly what differs.",
                        style = MaterialTheme.typography.bodySmall, color = Palette.Muted)
                    Spacer(Modifier.height(16.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Button(onClick = { one.launch(mimeTypes) }, enabled = !busy, colors = ButtonDefaults.buttonColors(containerColor = Palette.Ember)) {
                            Icon(Icons.Filled.Add, null); Spacer(Modifier.size(6.dp)); Text("Import Java mod")
                        }
                        OutlinedButton(onClick = { many.launch(mimeTypes) }, enabled = !busy) { Text("Import several") }
                    }
                    if (busy) { Spacer(Modifier.height(12.dp)); LinearProgressIndicator(Modifier.fillMaxWidth(), color = Palette.Ember) }
                }
            }
        }
        item {
            SectionCard("Conversion defaults", subtitle = "Used for new imports; each project can be converted again with other choices.") {
                Text("Quality", color = Palette.Muted, style = MaterialTheme.typography.labelMedium)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Quality.entries.forEach { q ->
                        FilterChip(selected = settings.defaultQuality == q, onClick = { vm.settings.update { it.copy(defaultQuality = q) } }, label = { Text(q.label) })
                    }
                }
                Text(settings.defaultQuality.description, color = Palette.Muted, style = MaterialTheme.typography.bodySmall)
                Spacer(Modifier.height(8.dp))
                Text("Targets", color = Palette.Muted, style = MaterialTheme.typography.labelMedium)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(selected = settings.targetAndroid, onClick = { vm.settings.update { it.copy(targetAndroid = !it.targetAndroid) } }, label = { Text("Horizon Android") })
                    FilterChip(selected = settings.targetDesktop, onClick = { vm.settings.update { it.copy(targetDesktop = !it.targetDesktop) } }, label = { Text("Desktop (native)") })
                }
            }
        }
        val recent = projects.filter { p -> p.state.outputs.isEmpty() }
        val history = projects.filter { p -> p.state.outputs.isNotEmpty() }
        item { Header("Recent projects", if (recent.isEmpty()) "Nothing in progress" else null) }
        items(recent, key = { it.state.id }) { p -> ProjectRow(p, onClick = { open(p.state.id, false) }, onDelete = { deleting = p }) }
        item { Header("Conversion history", if (history.isEmpty()) "Finished conversions appear here" else null) }
        items(history, key = { "h" + it.state.id }) { p -> ProjectRow(p, onClick = { open(p.state.id, true) }, onDelete = { deleting = p }) }
        item { Spacer(Modifier.height(24.dp)) }
    }

    deleting?.let { p ->
        AlertDialog(
            onDismissRequest = { deleting = null },
            title = { Text("Delete ${p.state.name}?") },
            text = { Text("Removes the project's copy of the jar, its analysis and outputs from this app. Your original file is not touched.") },
            confirmButton = { TextButton({ vm.delete(p.state.id); deleting = null }) { Text("Delete", color = Palette.Bad) } },
            dismissButton = { TextButton({ deleting = null }) { Text("Keep") } },
        )
    }
}

@Composable
private fun Header(text: String, hint: String?) {
    Column(Modifier.padding(start = 20.dp, end = 20.dp, top = 16.dp, bottom = 4.dp)) {
        Text(text, style = MaterialTheme.typography.titleMedium, color = Palette.Text, fontWeight = FontWeight.SemiBold)
        if (hint != null) Text(hint, style = MaterialTheme.typography.bodySmall, color = Palette.Muted)
    }
}

@Composable
private fun ProjectRow(p: ProjectSummary, onClick: () -> Unit, onDelete: () -> Unit) {
    val s = p.state
    val running = s.stages.firstOrNull { it.state == StageState.RUNNING }
    val failed = s.stages.any { it.state == StageState.FAILED }
    val (label, color) = when {
        s.lastError != null -> "Stopped" to Palette.Bad
        s.outputs.isNotEmpty() -> (if (failed) "Done, with failed checks" else "Done") to (if (failed) Palette.Partial else Palette.Good)
        running != null -> running.stage.label to Palette.Steel
        s.stages.first { it.stage == Stage.ANALYZE }.state == StageState.DONE -> "Analysed" to Palette.Steel
        else -> "Imported" to Palette.Muted
    }
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp).clip(RoundedCornerShape(14.dp)).background(Palette.Surface)
            .clickable(onClick = onClick).padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(s.name, color = Palette.Text, fontWeight = FontWeight.Medium)
            Text("${s.sources.size} file(s) · ${s.quality.label} · ${s.targets.joinToString { if (it == TargetId.HORIZON_ANDROID) "Android" else "Desktop" }} · " +
                DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(s.updatedAt)),
                color = Palette.Muted, style = MaterialTheme.typography.bodySmall)
            Spacer(Modifier.height(6.dp))
            Pill(label, color)
        }
        IconButton(onClick = onDelete) { Icon(Icons.Filled.Delete, "Delete", tint = Palette.Muted) }
        Icon(Icons.Filled.KeyboardArrowRight, null, tint = Palette.Muted)
    }
}
