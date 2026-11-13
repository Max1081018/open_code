package dev.rustmodforge.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import dev.rustmodforge.app.ForgeViewModel
import dev.rustmodforge.core.pipeline.ProjectState
import dev.rustmodforge.core.pipeline.Stage
import dev.rustmodforge.core.pipeline.StageState
import kotlinx.coroutines.delay

@Composable
fun ConversionScreen(vm: ForgeViewModel, id: String, onBack: () -> Unit, onDone: () -> Unit) {
    val work by vm.work(id).collectAsState(initial = null)
    var state by remember { mutableStateOf<ProjectState?>(null) }
    LaunchedEffect(id) {
        while (true) {
            state = vm.detail(id)?.state
            delay(700)
        }
    }
    val w = work
    val reported = state?.stages?.any { it.stage == Stage.REPORT && it.state == StageState.DONE } == true
    LaunchedEffect(w?.finished, reported) { if (w?.finished == true && reported) { vm.refresh(); onDone() } }

    Column(Modifier.fillMaxSize()) {
        ProjectTopBar(state?.name ?: "Conversion", onBack)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            SectionCard(if (w?.running == true) "Converting" else if (w?.failed == true) "Stopped" else "Conversion",
                subtitle = state?.let { "${it.quality.label} · ${it.sources.size} file(s)" }) {
                if (w?.running == true) {
                    Text(w.stage.ifEmpty { "Starting" }, color = Palette.Ember, fontWeight = FontWeight.SemiBold)
                    Text(w.detail, color = Palette.Muted, style = MaterialTheme.typography.bodySmall)
                    // While the agent works, name the operation it is really performing.
                    if (w.agentTool.isNotEmpty()) {
                        Spacer(Modifier.height(6.dp))
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Pill(w.agentTool, if (w.agentOk) Palette.Steel else Palette.Bad)
                            Text("AI engine operation", color = Palette.Muted, style = MaterialTheme.typography.bodySmall)
                        }
                    }
                    Spacer(Modifier.height(8.dp))
                    LinearProgressIndicator(progress = { w.fraction.coerceIn(0f, 1f) }, modifier = Modifier.fillMaxWidth(), color = Palette.Ember)
                    Spacer(Modifier.height(12.dp))
                    OutlinedButton(onClick = { vm.cancel(id) }) { Icon(Icons.Filled.Close, null); Spacer(Modifier.size(6.dp)); Text("Cancel") }
                    Text("Cancelling stops between steps. Finished steps are kept; resuming continues from there.", color = Palette.Muted, style = MaterialTheme.typography.bodySmall)
                } else if (w?.failed == true || state?.lastError != null) {
                    Text(w?.error ?: state?.lastError ?: "Stopped", color = Palette.Bad)
                    Spacer(Modifier.height(12.dp))
                    Button(onClick = { state?.let { vm.convert(id, it.quality, it.targets) } }, colors = ButtonDefaults.buttonColors(containerColor = Palette.Ember)) {
                        Icon(Icons.Filled.Refresh, null); Spacer(Modifier.size(6.dp)); Text("Resume")
                    }
                } else {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(Modifier.size(20.dp), color = Palette.Ember, strokeWidth = 2.dp)
                        Spacer(Modifier.size(10.dp))
                        Text("Waiting to start", color = Palette.Muted)
                    }
                }
            }
            SectionCard("Pipeline") {
                val stages = state?.stages ?: Stage.entries.map { dev.rustmodforge.core.pipeline.StageRecord(it) }
                stages.forEach { s ->
                    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        when (s.state) {
                            StageState.DONE -> Icon(Icons.Filled.CheckCircle, null, tint = Palette.Good)
                            StageState.FAILED -> Icon(Icons.Filled.Warning, null, tint = Palette.Bad)
                            StageState.RUNNING -> CircularProgressIndicator(Modifier.size(22.dp), color = Palette.Ember, strokeWidth = 2.dp)
                            StageState.SKIPPED -> Icon(Icons.Filled.Close, null, tint = Palette.Muted)
                            StageState.PENDING -> Icon(Icons.Filled.CheckCircle, null, tint = Palette.SurfaceHigh)
                        }
                        Column(Modifier.weight(1f)) {
                            Text(s.stage.label, color = if (s.state == StageState.PENDING) Palette.Muted else Palette.Text)
                            if (s.detail.isNotEmpty()) Text(s.detail, color = Palette.Muted, style = MaterialTheme.typography.bodySmall)
                        }
                    }
                }
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}
