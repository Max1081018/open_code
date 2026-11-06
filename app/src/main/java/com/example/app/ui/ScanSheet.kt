@file:OptIn(ExperimentalMaterial3Api::class)

package com.example.app.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.example.app.data.CoachConfig
import com.example.app.data.CoachSuggestion
import com.example.app.data.PersonaDraft
import com.example.app.data.ScanStore
import com.example.app.data.ScreenAnalysis
import com.example.app.data.WingmanBrain

@Composable
fun ScanSheet(
    vm: WingmanViewModel,
    session: ScanSession,
    onDismiss: () -> Unit,
    onOpenAiSettings: () -> Unit
) {
    val context = LocalContext.current
    val config by vm.coachConfig.collectAsStateWithLifecycle()
    val connected by ScanStore.connected.collectAsStateWithLifecycle()
    val storedSnapshot by ScanStore.snapshot.collectAsStateWithLifecycle()
    var manual by remember { mutableStateOf(false) }
    var manualText by remember(session.snapshot) {
        mutableStateOf(session.snapshot?.transcript.orEmpty())
    }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .fillMaxHeight(0.95f)
                .padding(10.dp)
                .imePadding(),
            shape = RoundedCornerShape(26.dp),
            tonalElevation = 6.dp
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(18.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = when (session.stage) {
                                ScanStage.ARMING -> "Scan a chat"
                                ScanStage.REVIEW -> "Review the chat"
                                ScanStage.RESULT -> "The read"
                            },
                            style = MaterialTheme.typography.headlineSmall,
                            fontWeight = FontWeight.SemiBold
                        )
                        Text(
                            text = session.targetPerson?.displayName
                                ?.takeIf { it.isNotBlank() }
                                ?.let { "Saving to $it" }
                                ?: "A new person",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    TextButton(onClick = onDismiss) { Text("Close") }
                }

                when (session.stage) {
                    ScanStage.ARMING -> ArmingStep(
                        connected = connected,
                        storedSnapshot = storedSnapshot,
                        manual = manual,
                        manualText = manualText,
                        onManualText = { manualText = it },
                        onToggleManual = {
                            manual = !manual
                            if (manual && manualText.isBlank()) {
                                manualText = storedSnapshot?.transcript.orEmpty()
                            }
                        },
                        onOpenAccessibility = { openAccessibilitySettings(context) },
                        onOpenDiscord = { openDiscord(context) },
                        onUseSnapshot = { vm.reviewCapturedSnapshot() },
                        onReviewManual = { vm.reviewManually(manualText) }
                    )
                    ScanStage.REVIEW -> ReviewStep(
                        session = session,
                        config = config,
                        onName = vm::updateScanName,
                        onTranscript = vm::updateTranscript,
                        onAnalyze = vm::analyzeScan,
                        onCaptureAgain = { vm.openScan(session.targetPerson) },
                        onOpenAiSettings = onOpenAiSettings
                    )
                    ScanStage.RESULT -> ResultStep(
                        session = session,
                        onCopy = { copyText(context, it) },
                        onSave = vm::saveScanResult,
                        onScanAgain = { vm.openScan(session.targetPerson) },
                        onOpenAiSettings = onOpenAiSettings
                    )
                }
            }
        }
    }
}

@Composable
private fun ArmingStep(
    connected: Boolean,
    storedSnapshot: com.example.app.data.ScanSnapshot?,
    manual: Boolean,
    manualText: String,
    onManualText: (String) -> Unit,
    onToggleManual: () -> Unit,
    onOpenAccessibility: () -> Unit,
    onOpenDiscord: () -> Unit,
    onUseSnapshot: () -> Unit,
    onReviewManual: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.cardColors(
            containerColor = if (connected) {
                MaterialTheme.colorScheme.secondaryContainer
            } else {
                MaterialTheme.colorScheme.errorContainer
            }
        )
    ) {
        Row(
            modifier = Modifier.padding(14.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.Top
        ) {
            Icon(
                imageVector = if (connected) Icons.Filled.Check else Icons.Filled.Warning,
                contentDescription = null,
                tint = if (connected) {
                    MaterialTheme.colorScheme.onSecondaryContainer
                } else {
                    MaterialTheme.colorScheme.onErrorContainer
                }
            )
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    text = if (connected) "Screen reading is on" else "Screen reading is off",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = if (connected) {
                        MaterialTheme.colorScheme.onSecondaryContainer
                    } else {
                        MaterialTheme.colorScheme.onErrorContainer
                    }
                )
                Text(
                    text = if (connected) {
                        "Wingman only reads while a scan is armed, and turns off again after one capture."
                    } else {
                        "Turn on Wingman chat reader in Accessibility. It is only active during a scan. You can also paste the chat by hand."
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = if (connected) {
                        MaterialTheme.colorScheme.onSecondaryContainer
                    } else {
                        MaterialTheme.colorScheme.onErrorContainer
                    }
                )
                if (!connected) {
                    TextButton(onClick = onOpenAccessibility) { Text("Enable screen reading") }
                }
            }
        }
    }

    StepBlock(
        number = "1",
        title = "Open the chat",
        detail = "Go to the conversation you want to read. Keep it on screen."
    ) {
        Button(onClick = onOpenDiscord, shape = RoundedCornerShape(14.dp)) {
            Icon(Icons.Filled.Search, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(modifier = Modifier.width(7.dp))
            Text("Open Discord")
        }
    }

    StepBlock(
        number = "2",
        title = "Come back to Wingman",
        detail = if (connected) {
            "The capture happens by itself. You will come back to an editable transcript."
        } else {
            "Screen reading is off, so use the paste option below instead."
        }
    )

    if (storedSnapshot != null) {
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(18.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
        ) {
            Column(
                modifier = Modifier.padding(14.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Text(
                    text = "Last capture · ${storedSnapshot.appLabel}",
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = storedSnapshot.transcript,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 4,
                    overflow = TextOverflow.Ellipsis
                )
                OutlinedButton(onClick = onUseSnapshot, shape = RoundedCornerShape(14.dp)) {
                    Text("Review this capture")
                }
            }
        }
    }

    OutlinedButton(
        onClick = onToggleManual,
        shape = RoundedCornerShape(14.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Text(if (manual) "Hide manual paste" else "Paste the chat instead")
    }

    if (manual) {
        OutlinedTextField(
            value = manualText,
            onValueChange = onManualText,
            modifier = Modifier.fillMaxWidth(),
            placeholder = { Text("Them: hey, how was your day\nMe: long, but good") },
            minLines = 6,
            maxLines = 12,
            shape = RoundedCornerShape(16.dp),
            supportingText = {
                Text(
                    "Lines starting with \"Me:\" are yours. Everything else is theirs.",
                    style = MaterialTheme.typography.labelSmall
                )
            }
        )
        Button(
            onClick = onReviewManual,
            enabled = manualText.isNotBlank(),
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(14.dp)
        ) {
            Text("Review this text")
        }
    }
}

@Composable
private fun StepBlock(
    number: String,
    title: String,
    detail: String,
    action: (@Composable () -> Unit)? = null
) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(
            modifier = Modifier
                .size(28.dp)
                .background(MaterialTheme.colorScheme.primaryContainer, CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = number,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onPrimaryContainer
            )
        }
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            Text(
                text = detail,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            action?.invoke()
        }
    }
}

@Composable
private fun ReviewStep(
    session: ScanSession,
    config: CoachConfig,
    onName: (String) -> Unit,
    onTranscript: (String) -> Unit,
    onAnalyze: () -> Unit,
    onCaptureAgain: () -> Unit,
    onOpenAiSettings: () -> Unit
) {
    OutlinedTextField(
        value = session.name,
        onValueChange = onName,
        label = { Text("Who is this?") },
        placeholder = { Text("Their name or handle") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp)
    )

    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Pill(
            text = session.snapshot?.appLabel ?: "Pasted text",
            container = MaterialTheme.colorScheme.secondaryContainer,
            content = MaterialTheme.colorScheme.onSecondaryContainer
        )
        Pill(
            text = "${session.transcript.lines().count { it.isNotBlank() }} lines",
            container = MaterialTheme.colorScheme.surfaceVariant,
            content = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }

    OutlinedTextField(
        value = session.transcript,
        onValueChange = onTranscript,
        modifier = Modifier.fillMaxWidth(),
        label = { Text("Captured chat") },
        minLines = 8,
        maxLines = 16,
        shape = RoundedCornerShape(16.dp),
        supportingText = {
            Text(
                "Fix anything the scan got wrong. Lines starting with \"Me:\" are yours, everything else is theirs.",
                style = MaterialTheme.typography.labelSmall
            )
        }
    )

    if (session.error != null) {
        ErrorCard(session.error)
    }

    Button(
        onClick = onAnalyze,
        enabled = !session.busy && session.transcript.isNotBlank(),
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp)
    ) {
        if (session.busy) {
            CircularProgressIndicator(
                modifier = Modifier.size(18.dp),
                strokeWidth = 2.dp,
                color = MaterialTheme.colorScheme.onPrimary
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text("Reading the chat…")
        } else {
            Icon(Icons.Filled.PlayArrow, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(modifier = Modifier.width(6.dp))
            Text("Analyse and write replies")
        }
    }

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        TextButton(onClick = onCaptureAgain) {
            Icon(Icons.Filled.Refresh, contentDescription = null, modifier = Modifier.size(16.dp))
            Spacer(modifier = Modifier.width(4.dp))
            Text("Capture again")
        }
        Text(
            text = if (config.isReady) "Uses ${config.provider.shortLabel}" else "On-device fallback",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }

    if (!config.isReady) {
        TextButton(onClick = onOpenAiSettings) { Text("Add a free key for a sharper read") }
    }
}

@Composable
private fun ResultStep(
    session: ScanSession,
    onCopy: (String) -> Unit,
    onSave: () -> Unit,
    onScanAgain: () -> Unit,
    onOpenAiSettings: () -> Unit
) {
    val analysis = session.analysis ?: return
    val draft = analysis.person

    Row(verticalAlignment = Alignment.CenterVertically) {
        InitialAvatar(
            name = session.name.ifBlank { draft.name },
            color = 0xFF7C3AED,
            size = 54.dp
        )
        Spacer(modifier = Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = session.name.ifBlank { draft.name }.ifBlank { "This person" },
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold
            )
            Text(
                text = "Confidence ${(draft.confidence * 100).toInt()}% · ${session.snapshot?.appLabel ?: "captured chat"}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        SourcePill(analysis.source.label)
    }

    if (analysis.notice.isNotBlank()) {
        Surface(
            color = MaterialTheme.colorScheme.tertiaryContainer,
            shape = RoundedCornerShape(14.dp),
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(modifier = Modifier.padding(12.dp)) {
                Text(
                    text = analysis.notice,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onTertiaryContainer
                )
                if (!analysis.source.label.contains("AI")) {
                    TextButton(onClick = onOpenAiSettings) { Text("Open AI settings") }
                }
            }
        }
    }

    PersonaBlock(draft = draft)

    if (draft.greenFlags.isNotEmpty() || draft.redFlags.isNotEmpty()) {
        if (draft.greenFlags.isNotEmpty()) {
            ScanFlagList("Green flags", draft.greenFlags, Color(0xFF059669), "+")
        }
        if (draft.redFlags.isNotEmpty()) {
            ScanFlagList("Watch for", draft.redFlags, Color(0xFFD97706), "!")
        }
    }

    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
    ) {
        Column(
            modifier = Modifier.padding(15.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Text(
                text = "Where this is at",
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold
            )
            Text(text = analysis.coach.read, style = MaterialTheme.typography.bodyMedium)
            analysis.coach.signals.take(4).forEach { signal ->
                Row {
                    Text(
                        text = "•",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary
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

    if (analysis.coach.caution.isNotBlank()) {
        Surface(
            color = MaterialTheme.colorScheme.errorContainer,
            shape = RoundedCornerShape(14.dp),
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(
                text = analysis.coach.caution,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onErrorContainer,
                modifier = Modifier.padding(12.dp)
            )
        }
    }

    Text("Pick a reply", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
    analysis.coach.suggestions.forEachIndexed { index, suggestion ->
        ScanSuggestion(
            index = index + 1,
            suggestion = suggestion,
            onCopy = { onCopy(suggestion.text) }
        )
    }

    if (session.error != null) ErrorCard(session.error)

    Button(
        onClick = onSave,
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp)
    ) {
        Icon(Icons.Filled.Check, contentDescription = null, modifier = Modifier.size(18.dp))
        Spacer(modifier = Modifier.width(7.dp))
        Text(
            if (session.targetPerson == null) {
                "Save this person's profile"
            } else {
                "Save to ${session.targetPerson.displayName}"
            }
        )
    }
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        TextButton(onClick = onScanAgain) { Text("Scan again") }
        Text(
            text = "Copy puts the message on your clipboard",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun PersonaBlock(draft: PersonaDraft) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
    ) {
        Column(
            modifier = Modifier.padding(15.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = draft.summary.ifBlank { "Not enough chat to describe them yet." },
                style = MaterialTheme.typography.bodyMedium
            )
            ChipRow(items = listOf(draft.vibe, draft.interests).filter { it.isNotBlank() })
            if (draft.communicationStyle.isNotBlank()) {
                Text(
                    text = "Writes: ${draft.communicationStyle}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            if (draft.opener.isNotBlank()) {
                Surface(
                    color = MaterialTheme.colorScheme.primaryContainer,
                    shape = RoundedCornerShape(12.dp),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column(modifier = Modifier.padding(12.dp)) {
                        Text(
                            text = "Next opener",
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.onPrimaryContainer
                        )
                        Text(
                            text = draft.opener,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onPrimaryContainer
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ScanSuggestion(
    index: Int,
    suggestion: CoachSuggestion,
    onCopy: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(18.dp),
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
            OutlinedButton(onClick = onCopy, shape = RoundedCornerShape(12.dp)) {
                Text("Copy reply")
            }
        }
    }
}

@Composable
private fun ScanFlagList(title: String, items: List<String>, color: Color, marker: String) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        SectionLabel(title)
        items.forEach { item ->
            Row(verticalAlignment = Alignment.Top) {
                Text(
                    text = marker,
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Bold,
                    color = color
                )
                Spacer(modifier = Modifier.width(7.dp))
                Text(
                    text = item,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun ErrorCard(message: String) {
    Surface(
        color = MaterialTheme.colorScheme.errorContainer,
        shape = RoundedCornerShape(14.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Text(
            text = message,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onErrorContainer,
            modifier = Modifier.padding(12.dp)
        )
    }
}

private fun openAccessibilitySettings(context: Context) {
    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    runCatching { context.startActivity(intent) }
        .onFailure { Toast.makeText(context, "Open Settings › Accessibility", Toast.LENGTH_LONG).show() }
}

private fun openDiscord(context: Context) {
    val intent = context.packageManager.getLaunchIntentForPackage("com.discord")
    if (intent == null) {
        Toast.makeText(
            context,
            "Discord is not installed. Open any chat app, or paste the chat instead.",
            Toast.LENGTH_LONG
        ).show()
        return
    }
    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    runCatching { context.startActivity(intent) }
        .onFailure { Toast.makeText(context, "Could not open Discord.", Toast.LENGTH_SHORT).show() }
}

private fun copyText(context: Context, text: String) {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
    clipboard?.setPrimaryClip(ClipData.newPlainText("Wingman reply", text))
    Toast.makeText(context, "Copied. Paste it in the chat.", Toast.LENGTH_SHORT).show()
}
