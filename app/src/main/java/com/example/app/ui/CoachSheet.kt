@file:OptIn(ExperimentalMaterial3Api::class)

package com.example.app.ui

import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.example.app.data.CoachConfig
import com.example.app.data.CoachReply
import com.example.app.data.CoachSuggestion
import com.example.app.data.Person
import com.example.app.data.ReplyCoach

@Composable
fun CoachDialog(
    vm: WingmanViewModel,
    person: Person,
    initialTranscript: String,
    onDismiss: () -> Unit,
    onUseReply: (String) -> Unit
) {
    val config by vm.coachConfig.collectAsStateWithLifecycle()
    val state by vm.coachState.collectAsStateWithLifecycle()
    var transcript by remember(person.id) { mutableStateOf(initialTranscript) }
    var showSettings by remember { mutableStateOf(false) }
    val context = LocalContext.current

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .fillMaxHeight(0.94f)
                .padding(10.dp)
                .imePadding(),
            shape = RoundedCornerShape(24.dp),
            tonalElevation = 6.dp
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(18.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = "Reply coach",
                            style = MaterialTheme.typography.headlineSmall,
                            fontWeight = FontWeight.SemiBold
                        )
                        Text(
                            text = "For ${person.displayName.ifBlank { "this chat" }}",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    TextButton(onClick = onDismiss) { Text("Done") }
                }

                if (!config.isReady) {
                    SetupPrompt(onOpenSettings = { showSettings = true })
                } else {
                    Text(
                        text = "The chat so far",
                        style = MaterialTheme.typography.labelLarge
                    )
                    OutlinedTextField(
                        value = transcript,
                        onValueChange = { transcript = it },
                        modifier = Modifier.fillMaxWidth(),
                        placeholder = { Text("Them: hey\nMe: hey, how was the exam?") },
                        minLines = 6,
                        maxLines = 12,
                        shape = RoundedCornerShape(16.dp),
                        supportingText = {
                            Text(
                                text = "Lines starting with \"Me:\" are yours. Everything else counts as theirs.",
                                style = MaterialTheme.typography.labelSmall
                            )
                        }
                    )

                    if (!person.consentStatus.allowsContact) {
                        Surface(
                            color = MaterialTheme.colorScheme.surfaceVariant,
                            shape = RoundedCornerShape(12.dp),
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(
                                text = "This chat is marked ${person.consentStatus.label.lowercase()}. " +
                                    "The coach will factor that in, and so should you.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.padding(12.dp)
                            )
                        }
                    }

                    Button(
                        onClick = { vm.askCoach(ReplyCoach.parseTranscript(transcript)) },
                        enabled = transcript.isNotBlank() && state != CoachUiState.Loading,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        if (state == CoachUiState.Loading) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(18.dp),
                                strokeWidth = 2.dp,
                                color = MaterialTheme.colorScheme.onPrimary
                            )
                            Spacer(modifier = Modifier.width(10.dp))
                            Text("Reading the room…")
                        } else {
                            Icon(Icons.Filled.PlayArrow, contentDescription = null)
                            Spacer(modifier = Modifier.width(8.dp))
                            Text("Read the room")
                        }
                    }

                    when (val current = state) {
                        CoachUiState.Idle -> Unit
                        CoachUiState.Loading -> Unit
                        is CoachUiState.Failed -> Surface(
                            color = MaterialTheme.colorScheme.errorContainer,
                            shape = RoundedCornerShape(14.dp),
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(
                                text = current.message,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onErrorContainer,
                                modifier = Modifier.padding(12.dp)
                            )
                        }
                        is CoachUiState.Ready -> CoachResult(
                            reply = current.reply,
                            onUse = { text ->
                                onUseReply(text)
                                onDismiss()
                            },
                            onCopy = { text ->
                                val clipboard = context.getSystemService(android.content.ClipboardManager::class.java)
                                clipboard?.setPrimaryClip(
                                    android.content.ClipData.newPlainText("reply", text)
                                )
                                Toast.makeText(context, "Copied", Toast.LENGTH_SHORT).show()
                            }
                        )
                    }
                }

                Spacer(modifier = Modifier.height(2.dp))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = if (config.isReady) {
                            "Sends the transcript and both style notes to your provider only."
                        } else {
                            "No key configured yet."
                        },
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.weight(1f)
                    )
                    TextButton(onClick = { showSettings = true }) {
                        Icon(
                            imageVector = Icons.Filled.Settings,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp)
                        )
                        Spacer(modifier = Modifier.width(6.dp))
                        Text("Settings")
                    }
                }
            }
        }
    }

    if (showSettings) {
        CoachSettingsDialog(
            config = config,
            personStyle = person.communicationStyle,
            persistent = vm.coachStoragePersistent,
            onDismiss = { showSettings = false },
            onSave = { updated ->
                vm.saveCoachConfig(updated)
                showSettings = false
            },
            onClearKey = {
                vm.clearCoachKey()
                showSettings = false
            }
        )
    }
}

@Composable
private fun SetupPrompt(onOpenSettings: () -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer)
    ) {
        Column(
            modifier = Modifier.padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = "One-time setup",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onPrimaryContainer
            )
            Text(
                text = "The coach needs your own API key. It goes in encrypted storage on this " +
                    "phone, is used only when you press the button, and nothing about your " +
                    "friends is uploaded unless you ask for a reply.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onPrimaryContainer
            )
            Button(onClick = onOpenSettings) { Text("Add API key") }
        }
    }
}

@Composable
private fun CoachResult(
    reply: CoachReply,
    onUse: (String) -> Unit,
    onCopy: (String) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(16.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
        ) {
            Column(
                modifier = Modifier.padding(14.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Text(
                    text = "Where this is at",
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.SemiBold
                )
                Text(text = reply.read, style = MaterialTheme.typography.bodyMedium)
                reply.signals.forEach { signal ->
                    Row {
                        Text(
                            text = "•",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(
                            text = signal,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }

        reply.suggestions.forEachIndexed { index, suggestion ->
            SuggestionCard(
                index = index + 1,
                suggestion = suggestion,
                onUse = { onUse(suggestion.text) },
                onCopy = { onCopy(suggestion.text) }
            )
        }

        if (reply.caution.isNotBlank()) {
            Surface(
                color = MaterialTheme.colorScheme.errorContainer,
                shape = RoundedCornerShape(14.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text(
                        text = "Worth knowing",
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onErrorContainer
                    )
                    Text(
                        text = reply.caution,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onErrorContainer
                    )
                }
            }
        }
    }
}

@Composable
private fun SuggestionCard(
    index: Int,
    suggestion: CoachSuggestion,
    onUse: () -> Unit,
    onCopy: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .size(22.dp)
                        .background(MaterialTheme.colorScheme.primary, CircleShape),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = "$index",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onPrimary
                    )
                }
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = suggestion.style.replaceFirstChar { it.uppercase() },
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Text(text = suggestion.text, style = MaterialTheme.typography.bodyLarge)

            if (suggestion.why.isNotBlank()) {
                Text(
                    text = suggestion.why,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = onUse) {
                    Icon(
                        imageVector = Icons.Filled.Send,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp)
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Text("Use")
                }
                OutlinedButton(onClick = onCopy) { Text("Copy") }
            }
        }
    }
}

@Composable
private fun CoachSettingsDialog(
    config: CoachConfig,
    personStyle: String,
    persistent: Boolean,
    onDismiss: () -> Unit,
    onSave: (CoachConfig) -> Unit,
    onClearKey: () -> Unit
) {
    var apiKey by remember { mutableStateOf(config.apiKey) }
    var baseUrl by remember { mutableStateOf(config.baseUrl) }
    var model by remember { mutableStateOf(config.model) }
    var myVoice by remember { mutableStateOf(config.myVoice) }
    var revealKey by remember { mutableStateOf(false) }

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .fillMaxHeight(0.92f)
                .padding(12.dp)
                .imePadding(),
            shape = RoundedCornerShape(24.dp),
            tonalElevation = 6.dp
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                Text(
                    text = "Coach settings",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.SemiBold
                )

                OutlinedTextField(
                    value = apiKey,
                    onValueChange = { apiKey = it },
                    label = { Text("API key") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    visualTransformation = if (revealKey) {
                        VisualTransformation.None
                    } else {
                        PasswordVisualTransformation()
                    },
                    trailingIcon = {
                        TextButton(onClick = { revealKey = !revealKey }) {
                            Text(if (revealKey) "Hide" else "Show")
                        }
                    },
                    supportingText = {
                        Text("Stored encrypted on this phone. Never leaves it except in the request itself.")
                    }
                )

                if (!persistent) {
                    Text(
                        text = "Secure storage is unavailable on this device, so the key is kept " +
                            "only until you close the app.",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.error
                    )
                }

                OutlinedTextField(
                    value = baseUrl,
                    onValueChange = { baseUrl = it },
                    label = { Text("Base URL") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    supportingText = {
                        Text("Must be https. Any OpenAI-compatible endpoint works.")
                    }
                )

                OutlinedTextField(
                    value = model,
                    onValueChange = { model = it },
                    label = { Text("Model") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    supportingText = {
                        Text("For example ${CoachConfig.DEFAULT_MODEL} or another chat model.")
                    }
                )

                OutlinedTextField(
                    value = myVoice,
                    onValueChange = { myVoice = it },
                    label = { Text("How you text") },
                    minLines = 2,
                    maxLines = 4,
                    modifier = Modifier.fillMaxWidth(),
                    supportingText = {
                        Text("Lowercase, short, no emoji, a bit dry — whatever you actually sound like.")
                    }
                )

                if (personStyle.isNotBlank()) {
                    Text(
                        text = "Their style comes from their profile: \"$personStyle\"",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    if (config.apiKey.isNotBlank()) {
                        TextButton(onClick = onClearKey) { Text("Remove key") }
                        Spacer(modifier = Modifier.width(4.dp))
                    }
                    TextButton(onClick = onDismiss) { Text("Cancel") }
                    Spacer(modifier = Modifier.width(4.dp))
                    Button(
                        onClick = {
                            onSave(
                                config.copy(
                                    apiKey = apiKey,
                                    baseUrl = baseUrl,
                                    model = model,
                                    myVoice = myVoice
                                )
                            )
                        }
                    ) { Text("Save") }
                }
            }
        }
    }
}
