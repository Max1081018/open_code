@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package dev.rustmodforge.app.ui

import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.unit.dp
import dev.rustmodforge.app.ForgeViewModel
import dev.rustmodforge.core.ai.AiAssistant
import dev.rustmodforge.core.ai.AiConfig
import dev.rustmodforge.core.compat.HorizonCompat
import dev.rustmodforge.core.pipeline.Quality
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun SettingsScreen(vm: ForgeViewModel) {
    val s by vm.settings.state.collectAsState()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var testing by remember { mutableStateOf(false) }
    var storage by remember { mutableStateOf<Long?>(null) }
    val pickTree = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) {
            runCatching {
                context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            }
            vm.settings.update { it.copy(horizonModsTree = uri.toString()) }
            vm.say("Exports will go to this folder")
        }
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        Text("Settings", style = MaterialTheme.typography.headlineSmall, color = Palette.Text, modifier = Modifier.padding(16.dp))

        SectionCard("AI provider", subtitle = "Optional. Used only at Maximum fidelity, one class or one compiler error per request. Analysis and extraction never need it.") {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Use an AI provider", color = Palette.Text, modifier = Modifier.weight(1f))
                Switch(checked = s.aiEnabled, onCheckedChange = { v -> vm.settings.update { it.copy(aiEnabled = v) } })
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(selected = s.aiKind == AiConfig.Kind.OPENAI_COMPATIBLE, onClick = {
                    vm.settings.update { it.copy(aiKind = AiConfig.Kind.OPENAI_COMPATIBLE, aiBaseUrl = if (it.aiKind != AiConfig.Kind.OPENAI_COMPATIBLE) "https://api.openai.com/v1" else it.aiBaseUrl) }
                }, label = { Text("OpenAI-compatible") })
                FilterChip(selected = s.aiKind == AiConfig.Kind.ANTHROPIC, onClick = {
                    vm.settings.update { it.copy(aiKind = AiConfig.Kind.ANTHROPIC, aiBaseUrl = if (it.aiKind != AiConfig.Kind.ANTHROPIC) "https://api.anthropic.com" else it.aiBaseUrl) }
                }, label = { Text("Anthropic") })
            }
            Field("Base URL", s.aiBaseUrl) { v -> vm.settings.update { it.copy(aiBaseUrl = v) } }
            Field("Model", s.aiModel, hint = "the model id your provider documents") { v -> vm.settings.update { it.copy(aiModel = v) } }
            Field("API key", s.aiKey, secret = true) { v -> vm.settings.update { it.copy(aiKey = v) } }
            Field("Token budget per conversion", s.aiTokenBudget.toString(), number = true) { v -> v.toIntOrNull()?.let { n -> vm.settings.update { it.copy(aiTokenBudget = n) } } }
            if (!vm.settings.secretsPersistent) Text("Secure storage is unavailable on this device: keys are kept until the app closes.", color = Palette.Partial, style = MaterialTheme.typography.bodySmall)
            Spacer(Modifier.height(6.dp))
            OutlinedButton(enabled = !testing && s.aiConfig() != null, onClick = {
                testing = true
                scope.launch {
                    val result = withContext(Dispatchers.IO) {
                        runCatching { AiAssistant.providerFor(s.aiConfig()!!).complete("Reply with OK.", "ping", 8) }
                    }
                    testing = false
                    vm.say(result.fold({ "Provider answered (${it.inputTokens + it.outputTokens} tokens)" }, { "Provider failed: ${it.message}" }))
                }
            }) { Text(if (testing) "Testing…" else "Test connection") }
        }

        SectionCard("Build", subtitle = "A phone cannot compile Horizon. Native (desktop) mods compile on a build server you run: tools/forge-build-server.py in RustMod Forge's repository.") {
            Field("Build server URL", s.buildServerUrl, hint = "https://… (empty: compilation is reported as not run)") { v -> vm.settings.update { it.copy(buildServerUrl = v) } }
            Field("Build server token", s.buildServerToken, secret = true) { v -> vm.settings.update { it.copy(buildServerToken = v) } }
            Field("Automatic repair attempts", s.maxRepairs.toString(), number = true) { v -> v.toIntOrNull()?.let { n -> vm.settings.update { it.copy(maxRepairs = n.coerceIn(0, 10)) } } }
        }

        SectionCard("Target launcher", subtitle = "Horizon Android has no import intent. Pick its Mods folder once (Files › Horizon Android › Mods) and exports go straight there.") {
            Field("Launcher package", s.launcherPackage) { v -> vm.settings.update { it.copy(launcherPackage = v) } }
            Text(if (s.horizonModsTree.isBlank()) "No folder chosen" else "Folder: " + Uri.decode(s.horizonModsTree).substringAfterLast(':'),
                color = Palette.Muted, style = MaterialTheme.typography.bodySmall)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = {
                    // Start the picker in Horizon Android's provider when it is installed.
                    val hint = runCatching { DocumentsContract.buildRootsUri(HorizonCompat.ANDROID_DOCUMENTS_AUTHORITY) }.getOrNull()
                    pickTree.launch(hint)
                }) { Text("Choose Mods folder") }
                if (s.horizonModsTree.isNotBlank()) OutlinedButton(onClick = { vm.settings.update { it.copy(horizonModsTree = "") } }) { Text("Forget") }
            }
        }

        SectionCard("Conversion quality") {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Quality.entries.forEach { q -> FilterChip(selected = s.defaultQuality == q, onClick = { vm.settings.update { it.copy(defaultQuality = q) } }, label = { Text(q.label) }) }
            }
            Quality.entries.forEach { q -> Text("${q.label}: ${q.description}", color = Palette.Muted, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 4.dp)) }
        }

        SectionCard("Horizon versions", subtitle = "The compatibility database is built from these sources; generated files target them") {
            KeyValue("Minecraft", HorizonCompat.MINECRAFT)
            KeyValue("Android port", HorizonCompat.ANDROID_REVISION.take(12), mono = true)
            KeyValue("Upstream", HorizonCompat.UPSTREAM_REVISION.take(12), mono = true)
            KeyValue("horizon-mixins", HorizonCompat.MIXINS_REVISION.take(12), mono = true)
            KeyValue("Hook API", "${HorizonCompat.NATIVE_HOOKS_API} (${HorizonCompat.hookCatalog.hooks.size} hook points)")
        }

        SectionCard("Storage") {
            KeyValue("Projects", storage?.let { bytes(it) } ?: "—")
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = { scope.launch { storage = withContext(Dispatchers.IO) { vm.storageBytes() } } }) { Text("Measure") }
                OutlinedButton(onClick = { vm.clearCaches() }) { Text("Clear caches") }
            }
        }

        SectionCard("Debug") {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Keep error logs in each project folder", color = Palette.Text, modifier = Modifier.weight(1f))
                Switch(checked = s.debugLogging, onCheckedChange = { v -> vm.settings.update { it.copy(debugLogging = v) } })
            }
        }
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun Field(label: String, value: String, hint: String? = null, secret: Boolean = false, number: Boolean = false, onChange: (String) -> Unit) {
    OutlinedTextField(
        value = value, onValueChange = onChange, label = { Text(label) }, singleLine = true,
        supportingText = hint?.let { { Text(it) } },
        visualTransformation = if (secret) PasswordVisualTransformation() else androidx.compose.ui.text.input.VisualTransformation.None,
        keyboardOptions = if (number) KeyboardOptions(keyboardType = KeyboardType.Number) else KeyboardOptions.Default,
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
    )
}
