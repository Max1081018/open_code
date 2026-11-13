@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package dev.rustmodforge.app.ui

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.rustmodforge.app.ForgeViewModel
import dev.rustmodforge.app.data.AiPreset
import dev.rustmodforge.app.data.OPENROUTER_BASE
import dev.rustmodforge.core.agent.AgentStep
import dev.rustmodforge.core.ai.AiRequestRecord
import dev.rustmodforge.core.ai.OpenRouterProvider
import dev.rustmodforge.core.compat.HorizonApiIndex
import dev.rustmodforge.core.report.StepStatus
import kotlinx.coroutines.launch
import java.text.DateFormat
import java.util.Date

/**
 * The AI engine: the OpenRouter connection, which free models exist right now, what the agent
 * did step by step, the requests it made and what they cost, and the build and repair logs. Every
 * line here is a record of an operation the engine actually performed.
 */
@Composable
fun AiEngineScreen(vm: ForgeViewModel) {
    val s by vm.settings.state.collectAsState()
    val projects by vm.projects.collectAsState()
    val scope = rememberCoroutineScope()
    var catalogNote by remember { mutableStateOf("") }
    var availability by remember { mutableStateOf<List<Pair<String, String>>>(emptyList()) }
    var checking by remember { mutableStateOf(false) }
    var selected by remember { mutableStateOf<String?>(null) }
    var steps by remember { mutableStateOf<List<AgentStep>>(emptyList()) }
    var requests by remember { mutableStateOf<List<AiRequestRecord>>(emptyList()) }
    var buildLogs by remember { mutableStateOf<List<Pair<String, String>>>(emptyList()) }

    val project = selected ?: projects.firstOrNull()?.state?.id
    LaunchedEffectKey(project) {
        if (project != null) {
            steps = vm.agentSteps(project)
            requests = vm.aiHistory(project)
            buildLogs = vm.detail(project)?.reports?.flatMap { r ->
                r.build.filter { it.log.isNotBlank() && (it.name.contains("compil", true) || it.name.contains("repair", true) || it.name.contains("agent", true)) }
                    .map { it.name + " · " + it.status.name.lowercase() to it.log }
            } ?: emptyList()
        }
    }

    LazyColumn(Modifier.fillMaxSize()) {
        item {
            Text("AI engine", style = MaterialTheme.typography.headlineSmall, color = Palette.Text, modifier = Modifier.padding(16.dp))
        }
        item {
            SectionCard("OpenRouter", subtitle = "Your own key, free models only. The agent drives the conversion through the engine's tools; it never runs the mod's Java code.") {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Use the AI engine", color = Palette.Text, modifier = Modifier.weight(1f))
                    Switch(checked = s.aiEnabled, onCheckedChange = { v -> vm.settings.update { it.copy(aiEnabled = v) } })
                }
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    AiPreset.entries.forEach { preset ->
                        FilterChip(selected = s.aiBaseUrl.trimEnd('/') == preset.baseUrl.trimEnd('/'), onClick = {
                            vm.settings.update { it.copy(aiKind = preset.kind, aiBaseUrl = preset.baseUrl, aiModel = preset.model) }
                        }, label = { Text(preset.label) })
                    }
                }
                OutlinedTextField(
                    value = s.aiKey, onValueChange = { v -> vm.settings.update { it.copy(aiKey = v) } },
                    label = { Text("OpenRouter API key") }, singleLine = true,
                    visualTransformation = if (s.aiKey.isBlank()) VisualTransformation.None else PasswordVisualTransformation(),
                    supportingText = { Text("Free key from openrouter.ai/keys. Kept in the Android keystore" + if (vm.settings.secretsPersistent) "." else "; secure storage is unavailable here, so it lasts this session only.") },
                    modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("Allow paid models", color = Palette.Text)
                        Text("Off: when every free model is rate-limited the conversion pauses and keeps its progress instead of spending money.",
                            color = Palette.Muted, style = MaterialTheme.typography.bodySmall)
                    }
                    Switch(checked = s.aiAllowPaid, onCheckedChange = { v -> vm.settings.update { it.copy(aiAllowPaid = v) } })
                }
                Spacer(Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = {
                        checking = true
                        scope.launch {
                            val (note, list) = vm.checkModels()
                            catalogNote = note; availability = list; checking = false
                        }
                    }, enabled = !checking && s.aiKey.isNotBlank(), colors = ButtonDefaults.buttonColors(containerColor = Palette.Ember)) {
                        Text(if (checking) "Checking…" else "Test connection and models")
                    }
                }
                if (catalogNote.isNotEmpty()) Text(catalogNote, color = Palette.Muted, style = MaterialTheme.typography.bodySmall)
            }
        }
        item {
            SectionCard("Models", subtitle = "Tried in this order; the first one that answers is used. Edit the list to change it.") {
                if (availability.isEmpty()) {
                    s.aiModelPreference.forEachIndexed { i, m -> KeyValue("${i + 1}.", m, mono = true) }
                    Text("Press Test connection to see which of these OpenRouter has right now.", color = Palette.Muted, style = MaterialTheme.typography.bodySmall)
                } else {
                    availability.forEach { (model, state) ->
                        Row(Modifier.fillMaxWidth().padding(vertical = 3.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(model, color = Palette.Text, fontFamily = FontFamily.Monospace, fontSize = 12.sp, modifier = Modifier.weight(1f))
                            Pill(
                                if (state.startsWith("available, free")) "free" else if (state.startsWith("not in")) "missing" else if (state.contains("paid")) "paid" else "check",
                                if (state.startsWith("available, free")) Palette.Good else if (state.startsWith("not in")) Palette.Bad else Palette.Partial,
                            )
                        }
                        Text(state, color = Palette.Muted, style = MaterialTheme.typography.bodySmall)
                    }
                }
                Spacer(Modifier.height(8.dp))
                var text by remember(s.aiModelPreference) { mutableStateOf(s.aiModelPreference.joinToString("\n")) }
                OutlinedTextField(
                    value = text, onValueChange = { text = it }, label = { Text("Model order, one per line") },
                    supportingText = { Text("Model names change on OpenRouter; anything the catalog does not list is skipped and reported above.") },
                    modifier = Modifier.fillMaxWidth(),
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = { vm.settings.update { it.copy(aiModelPreference = text.lines().map { l -> l.trim() }.filter { l -> l.isNotEmpty() }) } }) { Text("Save order") }
                    OutlinedButton(onClick = {
                        vm.settings.update { it.copy(aiModelPreference = OpenRouterProvider.DEFAULT_PREFERRED) }
                        text = OpenRouterProvider.DEFAULT_PREFERRED.joinToString("\n")
                    }) { Text("Reset") }
                }
            }
        }
        item {
            SectionCard("Budget per conversion", subtitle = "Free models have small context windows and hard rate limits, so the agent works in small steps.") {
                NumberField("Agent steps", s.agentMaxSteps) { n -> vm.settings.update { it.copy(agentMaxSteps = n.coerceIn(1, 200)) } }
                NumberField("Token budget", s.agentTokenBudget) { n -> vm.settings.update { it.copy(agentTokenBudget = n.coerceIn(1000, 5_000_000)) } }
            }
        }
        item {
            SectionCard("Horizon API knowledge base", subtitle = "What the agent is allowed to cite. Built from Horizon's own source; anything absent does not exist.") {
                val d = HorizonApiIndex.data
                KeyValue("Revision", d.source.revision.take(12), mono = true)
                KeyValue("Hook API", d.source.native_hooks_api?.toString() ?: "?")
                KeyValue("Indexed", "${d.hooks.size} hooks, ${d.helpers.size} helpers, ${d.goals.size} goals, ${d.docs.size} doc sections")
            }
        }
        if (projects.isNotEmpty()) item {
            SectionCard("Project", subtitle = "Whose agent log and requests are shown below") {
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    projects.take(12).forEach { p ->
                        FilterChip(selected = project == p.state.id, onClick = { selected = p.state.id }, label = { Text(p.state.name) })
                    }
                }
            }
        }
        item {
            val tokens = requests.sumOf { it.inputTokens + it.outputTokens }
            SectionCard("Token usage", subtitle = if (requests.isEmpty()) "No requests yet" else "${requests.size} requests, $tokens tokens") {
                if (requests.isEmpty()) Text("Nothing has been sent to a model for this project.", color = Palette.Muted)
                else {
                    requests.groupBy { it.model }.forEach { (model, list) ->
                        KeyValue(model.ifEmpty { "?" }, "${list.size} calls, ${list.sumOf { it.inputTokens }} in / ${list.sumOf { it.outputTokens }} out")
                    }
                }
            }
        }
        item {
            SectionCard("What the agent did", subtitle = if (steps.isEmpty()) "No agent run for this project" else "${steps.size} operations, newest last") {
                if (steps.isEmpty()) Text("Convert a mod at Maximum fidelity with the engine on to see each operation here.", color = Palette.Muted)
                steps.takeLast(80).forEach { st ->
                    Row(Modifier.fillMaxWidth().padding(vertical = 3.dp), verticalAlignment = Alignment.Top) {
                        Pill(if (st.ok) "ok" else "fail", if (st.ok) Palette.Good else Palette.Bad)
                        Spacer(Modifier.height(2.dp))
                        Column(Modifier.padding(start = 8.dp)) {
                            Text("${st.phase} · ${st.tool}", color = Palette.Text, style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.Medium)
                            Text(st.detail, color = Palette.Muted, style = MaterialTheme.typography.bodySmall)
                        }
                    }
                }
            }
        }
        item {
            SectionCard("Requests", subtitle = "Every call, its model and how it ended") {
                if (requests.isEmpty()) Text("None yet.", color = Palette.Muted)
                requests.takeLast(60).reversed().forEach { r ->
                    Row(Modifier.fillMaxWidth().padding(vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text("${r.model} · ${r.purpose}", color = Palette.Text, style = MaterialTheme.typography.bodySmall, fontFamily = FontFamily.Monospace, fontSize = 11.sp)
                            Text(DateFormat.getTimeInstance(DateFormat.MEDIUM).format(Date(r.time)) +
                                (if (r.inputTokens + r.outputTokens > 0) " · ${r.inputTokens}+${r.outputTokens} tokens" else "") +
                                (if (r.millis > 0) " · ${r.millis} ms" else "") + (if (r.note.isNotEmpty()) " · ${r.note}" else ""),
                                color = Palette.Muted, style = MaterialTheme.typography.bodySmall)
                        }
                        Pill(r.status, when (r.status) {
                            "ok" -> Palette.Good
                            "rate-limited", "timeout" -> Palette.Partial
                            else -> Palette.Bad
                        })
                    }
                }
            }
        }
        item {
            SectionCard("Build and repair logs", subtitle = "The compiler's own output, kept as it came") {
                if (buildLogs.isEmpty()) Text("No compilation or repair has run for this project.", color = Palette.Muted)
                buildLogs.forEach { (name, log) ->
                    Text(name, color = Palette.Steel, fontWeight = FontWeight.Medium, style = MaterialTheme.typography.bodySmall)
                    Text(log.takeLast(2000), color = Palette.Muted, fontFamily = FontFamily.Monospace, fontSize = 10.sp)
                    Spacer(Modifier.height(8.dp))
                }
            }
        }
        item { Spacer(Modifier.height(24.dp)) }
    }
}

@Composable
private fun NumberField(label: String, value: Int, onChange: (Int) -> Unit) {
    var text by remember(value) { mutableStateOf(value.toString()) }
    OutlinedTextField(
        value = text, onValueChange = { v -> text = v; v.toIntOrNull()?.let(onChange) },
        label = { Text(label) }, singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Number),
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
    )
}

/** `LaunchedEffect` with a nullable key, kept separate so the screen reads cleanly. */
@Composable
private fun LaunchedEffectKey(key: Any?, block: suspend () -> Unit) {
    androidx.compose.runtime.LaunchedEffect(key) { block() }
}
