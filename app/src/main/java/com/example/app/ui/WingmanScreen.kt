@file:OptIn(ExperimentalMaterial3Api::class)

package com.example.app.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.example.app.MainActivity
import com.example.app.data.AiProvider
import com.example.app.data.CoachConfig
import com.example.app.data.CoachLine
import com.example.app.data.CoachReply
import com.example.app.data.CoachSuggestion
import com.example.app.data.Person
import com.example.app.data.PersonalityProfile
import com.example.app.data.ReplyCoach
import com.example.app.service.FloatingScanService
import com.example.app.ui.ScanSession
import kotlinx.coroutines.launch

private val HeroGradient = listOf(
    Color(0xFF4338CA),
    Color(0xFF7C3AED),
    Color(0xFFDB2777)
)

@Composable
fun WingmanScreen(
    vm: WingmanViewModel,
    themeMode: ThemeMode,
    onCycleTheme: () -> Unit,
    autoStartScan: Boolean = false
) {
    val selectedPerson = vm.selectedPerson.collectAsStateWithLifecycle().value
    val scan by vm.scan.collectAsStateWithLifecycle()
    val notice by vm.notice.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }
    var showAiSettings by remember { mutableStateOf(false) }

    // Auto-start a scan when launched from the floating bubble (user is in Discord DMs).
    LaunchedEffect(autoStartScan) {
        if (autoStartScan && !scan.visible) {
            vm.openScan(null)
        }
    }

    LaunchedEffect(notice) {
        val message = notice ?: return@LaunchedEffect
        vm.consumeNotice()
        snackbarHostState.showSnackbar(message, duration = SnackbarDuration.Short)
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = {
                    Text("Wingman", fontWeight = FontWeight.SemiBold)
                },
                actions = {
                    IconButton(onClick = { showAiSettings = true }) {
                        Icon(Icons.Filled.Settings, contentDescription = "AI settings")
                    }
                    TextButton(onClick = onCycleTheme) { Text(themeMode.label) }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            // Hero card — just AI Settings and Start.
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(260.dp)
                    .clip(RoundedCornerShape(28.dp))
                    .background(Brush.linearGradient(HeroGradient)),
                elevation = CardDefaults.cardElevation(defaultElevation = 0.dp)
            ) {
                Column(
                    modifier = Modifier.fillMaxSize().padding(24.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    Text(
                        text = "WINGMAN",
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.Bold,
                        color = Color.White.copy(alpha = 0.9f)
                    )
                    Text(
                        text = "Read the room.\nThen say the right thing.",
                        style = MaterialTheme.typography.headlineMedium,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                        lineHeight = 36.sp
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Button(
                            onClick = { showAiSettings = true },
                            modifier = Modifier.weight(1f),
                            shape = RoundedCornerShape(14.dp),
                            colors = ButtonDefaults.buttonColors(
                                containerColor = Color.White.copy(alpha = 0.15f),
                                contentColor = Color.White
                            )
                        ) {
                            Icon(Icons.Filled.Settings, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(modifier = Modifier.width(8.dp))
                            Text("AI settings", fontWeight = FontWeight.SemiBold)
                        }
                        Button(
                            onClick = {
                                val context = LocalContext.current
                                val activity = context as? MainActivity
                                activity?.startFloatingBubble()
                                vm.openScan(null)
                            },
                            modifier = Modifier.weight(1f),
                            shape = RoundedCornerShape(14.dp),
                            colors = ButtonDefaults.buttonColors(
                                containerColor = Color.White,
                                contentColor = Color(0xFF4338CA)
                            )
                        ) {
                            if (scan.busy) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(18.dp),
                                    strokeWidth = 2.dp,
                                    color = Color(0xFF4338CA)
                                )
                                Spacer(modifier = Modifier.width(8.dp))
                                Text("Scanning…", fontWeight = FontWeight.SemiBold)
                            } else {
                                Icon(Icons.Filled.PlayArrow, contentDescription = null, modifier = Modifier.size(18.dp))
                                Spacer(modifier = Modifier.width(8.dp))
                                Text("Start scan", fontWeight = FontWeight.SemiBold)
                            }
                        }
                    }
                    if (scan.busy) {
                        Text(
                            text = "Watch your screen while Wingman reads the chat. You can stop anytime from the floating icon.",
                            style = MaterialTheme.typography.bodySmall,
                            color = Color.White.copy(alpha = 0.8f)
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(20.dp))

            // Scan status / result area.
            if (scan.visible || scan.analysis != null) {
                ScanStatusCard(
                    session = scan,
                    onCopy = { text ->
                        val context = LocalContext.current
                        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
                        clipboard?.setPrimaryClip(ClipData.newPlainText("Wingman reply", text))
                        Toast.makeText(context, "Copied. Paste it in the chat.", Toast.LENGTH_SHORT).show()
                    },
                    onSave = { vm.saveScanResult() },
                    onStop = {
                        vm.closeScan()
                        val context = LocalContext.current
                        val activity = context as? MainActivity
                        activity?.stopFloatingBubble()
                    }
                )
            }

            // Saved people list (minimal — just names with scan status).
            val everyone by vm.people.collectAsStateWithLifecycle()
            val profiles by vm.profiles.collectAsStateWithLifecycle()
            if (everyone.isNotEmpty()) {
                Text(
                    text = "Your people",
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 8.dp)
                )
                LazyColumn(
                    modifier = Modifier.fillMaxWidth().weight(1f).padding(horizontal = 16.dp),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(top = 8.dp, bottom = 80.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    items(everyone, key = { it.id }) { person ->
                        val profile = profiles.firstOrNull { it.personId == person.id }
                        PersonRow(
                            person = person,
                            profile = profile,
                            onScan = { vm.openScan(person) },
                            onStop = {
                                vm.closeScan()
                                val context = LocalContext.current
                                val activity = context as? MainActivity
                                activity?.stopFloatingBubble()
                            }
                        )
                    }
                }
            }
        }
    }

    if (showAiSettings) {
        AiSettingsDialog(
            vm = vm,
            onDismiss = { showAiSettings = false }
        )
    }
}

/** Shows scan progress, the single best AI reply, and stop/save actions. */
@Composable
private fun ScanStatusCard(
    session: ScanSession,
    onCopy: (String) -> Unit,
    onSave: () -> Unit,
    onStop: () -> Unit
) {
    val analysis = session.analysis
    val busy = session.busy
    Card(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Column(
            modifier = Modifier.padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = if (busy) "Watching your screen…" else "Scan complete",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Spacer(modifier = Modifier.width(8.dp))
                if (busy) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
            }

            if (session.error != null) {
                Surface(
                    color = MaterialTheme.colorScheme.errorContainer,
                    shape = RoundedCornerShape(12.dp),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(
                        text = session.error,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onErrorContainer,
                        modifier = Modifier.padding(12.dp)
                    )
                }
            }

            // Single best reply — the AI's top pick.
            if (analysis != null) {
                val reply = analysis.coach.suggestions.firstOrNull()
                if (reply != null) {
                    Card(
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(16.dp),
                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer)
                    ) {
                        Column(
                            modifier = Modifier.padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    text = "Reply to send",
                                    style = MaterialTheme.typography.labelMedium,
                                    fontWeight = FontWeight.SemiBold,
                                    color = MaterialTheme.colorScheme.onPrimaryContainer,
                                    modifier = Modifier.weight(1f)
                                )
                                Text(
                                    text = analysis.source.label,
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onPrimaryContainer
                                )
                            }
                            Text(
                                text = reply.text,
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onPrimaryContainer
                            )
                            Button(
                                onClick = { onCopy(reply.text) },
                                shape = RoundedCornerShape(12.dp),
                                colors = ButtonDefaults.buttonColors(
                                    containerColor = MaterialTheme.colorScheme.onPrimaryContainer,
                                    contentColor = MaterialTheme.colorScheme.primaryContainer
                                )
                            ) {
                                Text("Copy reply")
                            }
                        }
                    }

                    Text(
                        text = analysis.coach.read,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 4.dp)
                    )
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Button(
                    onClick = onStop,
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(14.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.errorContainer,
                        contentColor = MaterialTheme.colorScheme.onErrorContainer
                    )
                ) {
                    Icon(Icons.Filled.Close, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Stop watching", fontWeight = FontWeight.SemiBold)
                }
                if (analysis != null && !busy) {
                    Button(
                        onClick = onSave,
                        modifier = Modifier.weight(1f),
                        shape = RoundedCornerShape(14.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = Color.White,
                            contentColor = Color(0xFF4338CA)
                        )
                    ) {
                        Icon(Icons.Filled.Close, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Save profile", fontWeight = FontWeight.SemiBold)
                    }
                }
            }
        }
    }
}

/** Minimal person row — name, avatar, scan button. */
@Composable
private fun PersonRow(
    person: Person,
    profile: PersonalityProfile?,
    onScan: () -> Unit,
    onStop: () -> Unit
) {
    val context = LocalContext.current
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            InitialAvatar(name = person.displayName, color = person.avatarColor, size = 40.dp)
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = person.displayName,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis
                )
                Text(
                    text = if (profile != null && profile.scanCount > 0) {
                        "Scanned ${timeAgo(person.lastScanAt)} · ${profile.scanCount} scan${if (profile.scanCount == 1) "" else "s"}"
                    } else {
                        "No scan yet"
                    },
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis
                )
            }
            Button(
                onClick = onScan,
                shape = RoundedCornerShape(12.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color(0xFF4F46E5),
                    contentColor = Color.White
                )
            ) {
                Icon(Icons.Filled.PlayArrow, contentDescription = null, modifier = Modifier.size(16.dp))
                Spacer(modifier = Modifier.width(6.dp))
                Text("Scan")
            }
        }
    }
}

@Composable
private fun InitialAvatar(
    name: String,
    color: Long,
    modifier: Modifier = Modifier,
    size: androidx.compose.ui.unit.Dp = 40.dp
) {
    Box(
        modifier = modifier.size(size).background(Color(color), CircleShape),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = initialsOf(name),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            color = Color.White
        )
    }
}
