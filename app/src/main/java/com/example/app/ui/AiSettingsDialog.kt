@file:OptIn(ExperimentalMaterial3Api::class)

package com.example.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.example.app.data.AiProvider
import com.example.app.data.CoachConfig

/**
 * Provider, key, base URL and model management. The free tier is the default and
 * needs no key at all; the others need a free key from the provider.
 */
@Composable
fun AiSettingsDialog(
    vm: WingmanViewModel,
    onDismiss: () -> Unit
) {
    val config by vm.coachConfig.collectAsStateWithLifecycle()
    val testState by vm.aiTest.collectAsStateWithLifecycle()
    var selectedProvider by remember { mutableStateOf(config.provider) }
    var apiKey by remember { mutableStateOf(config.apiKey) }
    var baseUrl by remember { mutableStateOf(config.baseUrl) }
    var model by remember { mutableStateOf(config.model) }
    var myVoice by remember { mutableStateOf(config.myVoice) }
    var revealKey by remember { mutableStateOf(false) }

    val candidate = CoachConfig(
        provider = selectedProvider,
        apiKey = apiKey,
        baseUrl = baseUrl,
        model = model,
        myVoice = myVoice
    )

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .fillMaxHeight(0.92f)
                .padding(12.dp)
                .imePadding(),
            shape = RoundedCornerShape(26.dp),
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
                    text = "AI settings",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.SemiBold
                )

                Text(
                    text = "The free AI works out of the box and needs no key. Add a free key from " +
                        "Google AI Studio or Groq for a sharper and faster read.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )

                SectionLabel("Provider")

                Column(
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    AiProvider.values().forEach { provider ->
                        FilterChip(
                            selected = selectedProvider == provider,
                            onClick = {
                                selectedProvider = provider
                                apiKey = ""
                                baseUrl = provider.baseUrl
                                model = provider.model
                            },
                            label = { Text(provider.label) }
                        )
                    }
                }

                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(18.dp),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.surfaceVariant
                    )
                ) {
                    Column(
                        modifier = Modifier.padding(14.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text(
                            text = selectedProvider.hint,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Text(
                            text = "The free tier is a shared queue, so one chat can take up to about a " +
                                "minute. If it ever answers with a rate limit, Wingman falls back to an " +
                                "on-device read and tells you.",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }

                if (selectedProvider.requiresKey) {
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
                            Text(
                                text = "Stored encrypted on this phone. Never leaves it except in the request itself.",
                                style = MaterialTheme.typography.labelSmall
                            )
                        }
                    )
                }

                OutlinedTextField(
                    value = baseUrl,
                    onValueChange = { baseUrl = it },
                    label = { Text("Base URL") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    supportingText = {
                        Text("Must be https:// and end with /chat/completions for most providers.")
                    }
                )

                OutlinedTextField(
                    value = model,
                    onValueChange = { model = it },
                    label = { Text("Model") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    supportingText = {
                        Text("For example openai, gemini-flash-latest or llama-3.3-70b-versatile.")
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

                Button(
                    onClick = { vm.testAi(candidate) },
                    enabled = !testState.running,
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(14.dp)
                ) {
                    if (testState.running) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(18.dp),
                            strokeWidth = 2.dp,
                            color = MaterialTheme.colorScheme.onPrimary
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Testing…")
                    } else {
                        Text("Test connection")
                    }
                }

                Text(
                    text = if (testState.ok) {
                        testState.message
                    } else if (testState.message.isNotBlank()) {
                        testState.message
                    } else {
                        "No test run yet."
                    },
                    style = MaterialTheme.typography.labelSmall,
                    color = if (testState.ok) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    }
                )

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    TextButton(onClick = onDismiss) { Text("Cancel") }
                    Spacer(modifier = Modifier.width(8.dp))
                    Button(
                        onClick = {
                            vm.saveCoachConfig(candidate)
                            onDismiss()
                        },
                        shape = RoundedCornerShape(14.dp)
                    ) { Text("Save") }
                }
            }
        }
    }
}
