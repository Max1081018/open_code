@file:OptIn(ExperimentalMaterial3Api::class)

package com.example.app.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.OpenInNew
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.runtime.rememberCoroutineScope
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
import com.example.app.data.AiProvider
import com.example.app.data.ChatMessage
import com.example.app.data.CoachConfig
import com.example.app.data.CoachLine
import com.example.app.data.ConsentStatus
import com.example.app.data.Person
import com.example.app.data.PersonalityProfile
import com.example.app.data.ReplyCoach
import com.example.app.service.FloatingScanService
import com.example.app.data.WingmanBrain
import com.example.app.MainActivity
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

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

    if (selectedPerson == null) {
        PeopleScreen(
            vm = vm,
            themeMode = themeMode,
            onCycleTheme = onCycleTheme,
            snackbarHostState = snackbarHostState,
            onOpenChat = { vm.selectPerson(it.id) },
            onOpenAiSettings = { showAiSettings = true }
        )
    } else {
        BackHandler { vm.selectPerson(null) }
        PersonScreen(
            vm = vm,
            person = selectedPerson,
            themeMode = themeMode,
            onCycleTheme = onCycleTheme,
            snackbarHostState = snackbarHostState,
            onBack = { vm.selectPerson(null) },
            onOpenAiSettings = { showAiSettings = true }
        )
    }

    if (scan.visible) {
        ScanSheet(
            vm = vm,
            session = scan,
            onDismiss = { vm.closeScan() },
            onOpenAiSettings = { showAiSettings = true }
        )
    }

    if (showAiSettings) {
        AiSettingsDialog(
            vm = vm,
            onDismiss = { showAiSettings = false }
        )
    }
}

@Composable
private fun PeopleScreen(
    vm: WingmanViewModel,
    themeMode: ThemeMode,
    onCycleTheme: () -> Unit,
    snackbarHostState: SnackbarHostState,
    onOpenChat: (Person) -> Unit,
    onOpenAiSettings: () -> Unit
) {
    val everyone by vm.people.collectAsStateWithLifecycle()
    val people by vm.filteredPeople.collectAsStateWithLifecycle()
    val profiles by vm.profiles.collectAsStateWithLifecycle()
    val query by vm.query.collectAsStateWithLifecycle()
    val config by vm.coachConfig.collectAsStateWithLifecycle()

    val scope = rememberCoroutineScope()
    var showEditor by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf<Person?>(null) }
    var newAvatarColor by remember { mutableStateOf(Person.DEFAULT_AVATAR_COLOR) }
    val openNew: () -> Unit = {
        editing = null
        newAvatarColor = vm.nextAvatarColor()
        vm.query.value = ""
        showEditor = true
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text("Wingman", fontWeight = FontWeight.SemiBold)
                        Text(
                            text = when {
                                everyone.isEmpty() -> "Screen-aware conversation coach"
                                everyone.size == 1 -> "1 person saved"
                                else -> "${everyone.size} people saved"
                            },
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                },
                actions = {
                    IconButton(onClick = onOpenAiSettings) {
                        Icon(Icons.Filled.Settings, contentDescription = "AI settings")
                    }
                    val context = LocalContext.current
                    val activity = context as? MainActivity
                    val overlayEnabled = activity != null && FloatingScanService.isOverlayEnabled(context)
                    IconButton(
                        onClick = {
                            if (overlayEnabled) {
                                activity?.stopFloatingBubble()
                            } else {
                                FloatingScanService.requestOverlayPermission(context)
                            }
                        },
                        contentDescription = if (overlayEnabled) "Hide floating scan bubble" else "Show floating scan bubble"
                    ) {
                        Icon(
                            imageVector = if (overlayEnabled) Icons.Filled.Close else Icons.Filled.OpenInNew,
                            contentDescription = null
                        )
                    }
                    TextButton(onClick = onCycleTheme) { Text(themeMode.label) }
                }
            )
        },
        floatingActionButton = {
            FloatingActionButton(onClick = { openNew() }) {
                Icon(Icons.Filled.Add, contentDescription = "Add person")
            }
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            if (everyone.isNotEmpty()) {
                OutlinedTextField(
                    value = query,
                    onValueChange = { vm.query.value = it },
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 10.dp),
                    placeholder = { Text("Search people, vibes, interests") },
                    leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                    trailingIcon = {
                        if (query.isNotEmpty()) {
                            IconButton(onClick = { vm.query.value = "" }) {
                                Icon(Icons.Filled.Close, contentDescription = "Clear search")
                            }
                        }
                    },
                    singleLine = true,
                    shape = RoundedCornerShape(16.dp)
                )
            }

            LazyColumn(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f),
                contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 100.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                item { HeroCard(config = config, onScan = { vm.openScan(null) }, onOpenAiSettings = onOpenAiSettings) }

                if (everyone.isEmpty()) {
                    item { HowItWorksCard(onScan = { vm.openScan(null) }, onAdd = { openNew() }) }
                } else {
                    item {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            SectionLabel("Your people", modifier = Modifier.weight(1f))
                            TextButton(onClick = { vm.openScan(null) }) { Text("New scan") }
                        }
                    }
                    if (people.isEmpty()) {
                        item {
                            Card(
                                modifier = Modifier.fillMaxWidth(),
                                shape = RoundedCornerShape(18.dp),
                                colors = CardDefaults.cardColors(
                                    containerColor = MaterialTheme.colorScheme.surfaceVariant
                                )
                            ) {
                                Column(modifier = Modifier.padding(18.dp)) {
                                    Text("No matches", fontWeight = FontWeight.SemiBold)
                                    Text(
                                        "Nobody matches \"$query\".",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                        }
                    }
                    items(people, key = { it.id }) { person ->
                        val profile = profiles.firstOrNull { it.personId == person.id }
                        PersonCard(
                            person = person,
                            profile = profile,
                            onOpen = { onOpenChat(person) },
                            onScan = { vm.openScan(person) },
                            onDelete = {
                                vm.deletePerson(person)
                                scope.launch {
                                    val result = snackbarHostState.showSnackbar(
                                        message = "${person.displayName} removed",
                                        actionLabel = "Undo",
                                        duration = SnackbarDuration.Short
                                    )
                                    if (result == SnackbarResult.ActionPerformed) {
                                        vm.restoreDeletedPerson()
                                    }
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    if (showEditor) {
        PersonEditor(
            person = editing,
            newAvatarColor = newAvatarColor,
            onDismiss = { showEditor = false },
            onSave = { person ->
                vm.savePerson(person)
                showEditor = false
            },
            onDelete = { person ->
                vm.deletePerson(person)
                showEditor = false
                scope.launch {
                    val result = snackbarHostState.showSnackbar(
                        message = "${person.displayName} removed",
                        actionLabel = "Undo"
                    )
                    if (result == SnackbarResult.ActionPerformed) vm.restoreDeletedPerson()
                }
            }
        )
    }
}

@Composable
private fun HeroCard(
    config: CoachConfig,
    onScan: () -> Unit,
    onOpenAiSettings: () -> Unit
) {
    val status = when {
        config.provider == AiProvider.FREE -> "Free AI · no key needed"
        config.isReady -> "${config.provider.shortLabel} · ready"
        else -> "${config.provider.shortLabel} · add a key"
    }

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(232.dp)
            .clip(RoundedCornerShape(28.dp))
            .background(Brush.linearGradient(HeroGradient))
    ) {
        Box(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .offset(x = 44.dp, y = (-54).dp)
                .size(190.dp)
                .background(Color.White.copy(alpha = 0.07f), CircleShape)
        )
        Box(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .offset(x = (-40).dp, y = 58.dp)
                .size(150.dp)
                .background(Color.White.copy(alpha = 0.06f), CircleShape)
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(22.dp),
            verticalArrangement = Arrangement.SpaceBetween
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Pill(
                    text = "WINGMAN",
                    container = Color.White.copy(alpha = 0.16f),
                    content = Color.White
                )
                Text(
                    text = "Read the room.\nThen say the right thing.",
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                    lineHeight = 34.sp
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .size(7.dp)
                            .background(Color(0xFF4ADE80), CircleShape)
                    )
                    Text(
                        text = status,
                        style = MaterialTheme.typography.labelMedium,
                        color = Color.White.copy(alpha = 0.9f)
                    )
                }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Button(
                        onClick = onScan,
                        shape = RoundedCornerShape(14.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = Color.White,
                            contentColor = Color(0xFF4338CA)
                        )
                    ) {
                        Icon(Icons.Filled.Search, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Scan a chat", fontWeight = FontWeight.SemiBold)
                    }
                    TextButton(
                        onClick = onOpenAiSettings,
                        colors = ButtonDefaults.textButtonColors(contentColor = Color.White)
                    ) {
                        Text("AI settings")
                    }
                }
            }
        }
    }
}

@Composable
private fun HowItWorksCard(onScan: () -> Unit, onAdd: () -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(22.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
    ) {
        Column(
            modifier = Modifier.padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Text(
                text = "How this works",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            StepRow("1", "Open a chat", "Start a scan, then switch to Discord or any chat app.")
            StepRow("2", "Review the capture", "Wingman reads the visible messages. You can fix or paste them.")
            StepRow("3", "Save the read", "The profile is saved under their name, with replies you can use.")
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Button(onClick = onScan, shape = RoundedCornerShape(14.dp)) { Text("Scan a chat") }
                OutlinedButton(onClick = onAdd, shape = RoundedCornerShape(14.dp)) { Text("Add by hand") }
            }
        }
    }
}

@Composable
private fun StepRow(number: String, title: String, detail: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(
            modifier = Modifier
                .size(26.dp)
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
        Column {
            Text(title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
            Text(
                detail,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun PersonCard(
    person: Person,
    profile: PersonalityProfile?,
    onOpen: () -> Unit,
    onScan: () -> Unit,
    onDelete: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onOpen),
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Column(
            modifier = Modifier.padding(start = 14.dp, end = 6.dp, top = 14.dp, bottom = 12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                InitialAvatar(name = person.displayName, color = person.avatarColor, size = 46.dp)
                Spacer(modifier = Modifier.width(12.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = person.displayName,
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        text = if (person.lastScanAt > 0L) {
                            "Scanned ${timeAgo(person.lastScanAt)}"
                        } else {
                            "No scan yet"
                        },
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                IconButton(onClick = onScan) {
                    Icon(
                        Icons.Filled.Refresh,
                        contentDescription = "Scan ${person.displayName}'s chat",
                        tint = MaterialTheme.colorScheme.primary
                    )
                }
                IconButton(onClick = onDelete) {
                    Icon(
                        Icons.Filled.Delete,
                        contentDescription = "Delete ${person.displayName}",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            Text(
                text = profile?.summary?.takeIf { it.isNotBlank() }
                    ?: person.notes.takeIf { it.isNotBlank() }
                    ?: "Tap to open, or scan their chat to build a profile.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                if (profile != null) {
                    SourcePill(profile.source.ifBlank { "On-device" })
                    if (profile.scanCount > 0) {
                        Pill(
                            text = "${profile.scanCount} scan${if (profile.scanCount == 1) "" else "s"}",
                            container = MaterialTheme.colorScheme.surfaceVariant,
                            content = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                } else {
                    Pill(
                        text = "Profile needed",
                        container = MaterialTheme.colorScheme.tertiaryContainer,
                        content = MaterialTheme.colorScheme.onTertiaryContainer
                    )
                }
            }
        }
    }
}

@Composable
private fun PersonScreen(
    vm: WingmanViewModel,
    person: Person,
    themeMode: ThemeMode,
    onCycleTheme: () -> Unit,
    snackbarHostState: SnackbarHostState,
    onBack: () -> Unit,
    onOpenAiSettings: () -> Unit
) {
    val messages by vm.messages.collectAsStateWithLifecycle()
    val profile by vm.profile.collectAsStateWithLifecycle()
    val showCoach by vm.showCoach.collectAsStateWithLifecycle()

    var text by remember(person.id) { mutableStateOf("") }
    var sender by remember(person.id) { mutableStateOf(ChatMessage.MessageSender.USER) }
    var showEditor by remember(person.id) { mutableStateOf(false) }
    val listState = rememberLazyListState()
    val context = LocalContext.current

    LaunchedEffect(messages.size) {
        // Two header items sit above the log in the lazy list.
        if (messages.isNotEmpty()) listState.scrollToItem(messages.lastIndex + 2)
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(person.displayName, fontWeight = FontWeight.SemiBold)
                        Text(
                            text = listOfNotNull(
                                person.discordHandle.takeIf { it.isNotBlank() },
                                if (person.lastScanAt > 0L) "scanned ${timeAgo(person.lastScanAt)}" else null
                            ).joinToString(" · ").ifBlank { "Wingman profile" },
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { showEditor = true }) {
                        Icon(Icons.Filled.Edit, contentDescription = "Edit ${person.displayName}")
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
                .consumeWindowInsets(padding)
                .imePadding()
        ) {
            LazyColumn(
                state = listState,
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth(),
                contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 10.dp, bottom = 16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                item {
                    if (profile == null) {
                        NoProfileCard(
                            onScan = { vm.openScan(person) },
                            onCoach = { vm.openCoach() },
                            onGenerate = { vm.generateProfile() }
                        )
                    } else {
                        ProfileCard(
                            person = person,
                            profile = profile!!,
                            onScan = { vm.openScan(person) },
                            onCoach = { vm.openCoach() },
                            onRebuild = { vm.generateProfile() },
                            onCopy = { copyToClipboard(context, it, "Copied") },
                            onOpenAiSettings = onOpenAiSettings
                        )
                    }
                }

                item {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 4.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        SectionLabel("Chat notes", modifier = Modifier.weight(1f))
                        Text(
                            text = "${messages.size} logged",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }

                if (messages.isEmpty()) {
                    item {
                        Card(
                            modifier = Modifier.fillMaxWidth(),
                            shape = RoundedCornerShape(18.dp),
                            colors = CardDefaults.cardColors(
                                containerColor = MaterialTheme.colorScheme.surfaceVariant
                            )
                        ) {
                            Column(
                                modifier = Modifier.padding(16.dp),
                                verticalArrangement = Arrangement.spacedBy(4.dp)
                            ) {
                                Text(
                                    "Optional",
                                    style = MaterialTheme.typography.labelMedium,
                                    fontWeight = FontWeight.SemiBold
                                )
                                Text(
                                    "Keep notes on what you said and what they said. Scans already give the coach context, so this is only if you want a history.",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }
                } else {
                    items(messages, key = { it.id }) { message ->
                        MessageRow(message = message)
                    }
                }
            }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Log as",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                ChatMessage.MessageSender.values().forEach { option ->
                    FilterChip(
                        selected = sender == option,
                        onClick = { sender = option },
                        label = { Text(option.label) }
                    )
                }
            }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = 16.dp, end = 8.dp, top = 4.dp, bottom = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                OutlinedTextField(
                    value = text,
                    onValueChange = { text = it },
                    modifier = Modifier.weight(1f),
                    placeholder = {
                        Text(if (sender == ChatMessage.MessageSender.USER) "Your message" else "Their message")
                    },
                    singleLine = false,
                    maxLines = 4,
                    shape = RoundedCornerShape(16.dp)
                )
                TextButton(
                    onClick = {
                        if (text.isNotBlank()) {
                            vm.sendMessage(text, sender)
                            text = ""
                        }
                    },
                    enabled = text.isNotBlank()
                ) {
                    Text("Send")
                }
            }
        }
    }

    if (showCoach) {
        CoachDialog(
            vm = vm,
            person = person,
            initialTranscript = profile?.lastTranscript?.takeIf { it.isNotBlank() }
                ?: ReplyCoach.formatTranscript(
                    messages.takeLast(14).map { CoachLine(it.isFromMe, it.text) }
                ),
            onDismiss = { vm.closeCoach() },
            onUseReply = { reply ->
                text = reply
                sender = ChatMessage.MessageSender.USER
                vm.closeCoach()
            }
        )
    }

    if (showEditor) {
        PersonEditor(
            person = person,
            newAvatarColor = person.avatarColor,
            onDismiss = { showEditor = false },
            onSave = { updated ->
                vm.savePerson(updated)
                showEditor = false
            },
            onDelete = { target ->
                vm.deletePerson(target)
                showEditor = false
                onBack()
            }
        )
    }
}

@Composable
private fun NoProfileCard(
    onScan: () -> Unit,
    onCoach: () -> Unit,
    onGenerate: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(22.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer)
    ) {
        Column(
            modifier = Modifier.padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = "No profile yet",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onPrimaryContainer
            )
            Text(
                text = "Scan a chat to read how they write, what they are into and what to send next. You can also build a profile from your own notes.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onPrimaryContainer
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = onScan, shape = RoundedCornerShape(14.dp)) {
                    Icon(Icons.Filled.Search, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(modifier = Modifier.width(6.dp))
                    Text("Scan chat")
                }
                OutlinedButton(onClick = onCoach, shape = RoundedCornerShape(14.dp)) { Text("Coach") }
            }
            TextButton(onClick = onGenerate) { Text("Build from my notes instead") }
        }
    }
}

@Composable
private fun ProfileCard(
    person: Person,
    profile: PersonalityProfile,
    onScan: () -> Unit,
    onCoach: () -> Unit,
    onRebuild: () -> Unit,
    onCopy: (String) -> Unit,
    onOpenAiSettings: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Column(
            modifier = Modifier.padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                InitialAvatar(name = person.displayName, color = person.avatarColor, size = 54.dp)
                Spacer(modifier = Modifier.width(12.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = person.displayName,
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = buildString {
                            append(if (profile.scanCount > 0) "Scanned ${timeAgo(profile.updatedAt)}" else "Built ${timeAgo(profile.updatedAt)}")
                            if (profile.scanCount > 0) {
                                append(" · ")
                                append(profile.scanCount)
                                append(if (profile.scanCount == 1) " scan" else " scans")
                            }
                        },
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                SourcePill(profile.source.ifBlank { "On-device" })
            }

            Text(
                text = profile.summary,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface
            )

            ChipRow(items = splitItems(profile.vibe) + splitItems(profile.interests))

            if (profile.attachmentStyle.isNotBlank() && profile.attachmentStyle != "unclear") {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = "Attachment style",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(
                        text = profile.attachmentStyle,
                        style = MaterialTheme.typography.bodySmall,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
            }
            if (profile.emotionalNeeds.isNotBlank()) {
                Text(
                    text = "Needs: ${profile.emotionalNeeds}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            if (profile.greenFlags.isNotEmpty() || profile.redFlags.isNotEmpty()) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(1.dp)
                        .background(MaterialTheme.colorScheme.outline.copy(alpha = 0.35f))
                )
                if (profile.greenFlags.isNotEmpty()) {
                    FlagList(
                        title = "Green flags",
                        items = profile.greenFlags,
                        color = Color(0xFF059669),
                        marker = "+"
                    )
                }
                if (profile.redFlags.isNotEmpty()) {
                    FlagList(
                        title = "Watch for",
                        items = profile.redFlags,
                        color = Color(0xFFD97706),
                        marker = "!"
                    )
                }
            }

            if (profile.signals.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    SectionLabel("What the chat shows")
                    profile.signals.take(4).forEach { signal ->
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

            if (profile.suggestedOpener.isNotBlank()) {
                Surface(
                    color = MaterialTheme.colorScheme.primaryContainer,
                    shape = RoundedCornerShape(16.dp),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column(
                        modifier = Modifier.padding(14.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                text = "Opening line",
                                style = MaterialTheme.typography.labelMedium,
                                fontWeight = FontWeight.SemiBold,
                                color = MaterialTheme.colorScheme.onPrimaryContainer,
                                modifier = Modifier.weight(1f)
                            )
                            TextButton(onClick = { onCopy(profile.suggestedOpener) }) {
                                Text("Copy")
                            }
                        }
                        Text(
                            text = profile.suggestedOpener,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onPrimaryContainer
                        )
                    }
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                LinearProgressIndicator(
                    progress = { profile.confidence.coerceIn(0f, 1f) },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(5.dp)
                )
                Text(
                    text = "Confidence ${WingmanBrain.confidencePercent(profile)}% · ${profile.source.ifBlank { "On-device" }}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            if (profile.lastTranscript.isNotBlank()) {
                Surface(
                    color = MaterialTheme.colorScheme.surfaceVariant,
                    shape = RoundedCornerShape(16.dp),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column(
                        modifier = Modifier.padding(14.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Text(
                            text = "Last captured chat",
                            style = MaterialTheme.typography.labelMedium,
                            fontWeight = FontWeight.SemiBold
                        )
                        Text(
                            text = profile.lastTranscript,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 5,
                            overflow = TextOverflow.Ellipsis
                        )
                        TextButton(
                            onClick = onCoach,
                            contentPadding = PaddingValues(horizontal = 0.dp, vertical = 0.dp)
                        ) {
                            Text("Open this in the coach")
                        }
                    }
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Button(onClick = onScan, shape = RoundedCornerShape(14.dp)) {
                    Icon(Icons.Filled.Search, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(modifier = Modifier.width(6.dp))
                    Text("Scan again")
                }
                OutlinedButton(onClick = onCoach, shape = RoundedCornerShape(14.dp)) {
                    Icon(Icons.Filled.PlayArrow, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(modifier = Modifier.width(6.dp))
                    Text("Coach")
                }
                IconButton(onClick = onRebuild) {
                    Icon(
                        Icons.Filled.Refresh,
                        contentDescription = "Rebuild from notes",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            if (profile.source.contains("on-device", ignoreCase = true)) {
                Text(
                    text = "AI was unavailable, so this was built on the phone. Add a free key in AI settings for a sharper read.",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                TextButton(onClick = onOpenAiSettings) { Text("Open AI settings") }
            }
        }
    }
}

@Composable
private fun FlagList(
    title: String,
    items: List<String>,
    color: Color,
    marker: String
) {
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
private fun MessageRow(message: ChatMessage) {
    val isUser = message.isFromMe
    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = if (isUser) Alignment.End else Alignment.Start
    ) {
        Card(
            shape = RoundedCornerShape(16.dp),
            colors = CardDefaults.cardColors(
                containerColor = if (isUser) {
                    MaterialTheme.colorScheme.primaryContainer
                } else {
                    MaterialTheme.colorScheme.surfaceVariant
                }
            ),
            modifier = Modifier.padding(vertical = 2.dp)
        ) {
            Text(
                text = message.text,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp)
            )
        }
        Text(
            text = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(message.createdAt)),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun PersonEditor(
    person: Person?,
    newAvatarColor: Long,
    onDismiss: () -> Unit,
    onSave: (Person) -> Unit,
    onDelete: (Person) -> Unit
) {
    var displayName by remember { mutableStateOf(person?.displayName ?: "") }
    var discordHandle by remember { mutableStateOf(person?.discordHandle ?: "") }
    var interests by remember { mutableStateOf(person?.interests ?: "") }
    var vibe by remember { mutableStateOf(person?.vibe ?: "") }
    var communicationStyle by remember { mutableStateOf(person?.communicationStyle ?: "") }
    var notes by remember { mutableStateOf(person?.notes ?: "") }
    var consent by remember { mutableStateOf(person?.consentStatus ?: ConsentStatus.NOT_STARTED) }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .fillMaxHeight(0.94f)
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
                    text = if (person == null) "Add a person" else "Edit ${person.displayName}",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = "Scans fill this in for you. Everything here is optional.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )

                OutlinedTextField(
                    value = displayName,
                    onValueChange = { displayName = it },
                    label = { Text("Name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = discordHandle,
                    onValueChange = { discordHandle = it },
                    label = { Text("Handle (optional)") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = vibe,
                    onValueChange = { vibe = it },
                    label = { Text("Vibe") },
                    minLines = 2,
                    maxLines = 4,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = interests,
                    onValueChange = { interests = it },
                    label = { Text("Interests") },
                    minLines = 2,
                    maxLines = 4,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = communicationStyle,
                    onValueChange = { communicationStyle = it },
                    label = { Text("How they write") },
                    minLines = 2,
                    maxLines = 4,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = notes,
                    onValueChange = { notes = it },
                    label = { Text("Private notes") },
                    minLines = 2,
                    maxLines = 4,
                    modifier = Modifier.fillMaxWidth()
                )

                Text("Consent", style = MaterialTheme.typography.labelLarge)
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    ConsentStatus.values().forEach { status ->
                        FilterChip(
                            selected = consent == status,
                            onClick = { consent = status },
                            label = { Text(status.label) }
                        )
                    }
                }
                Text(
                    text = "Only reach out when they have agreed, and respect a pause.",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )

                Spacer(modifier = Modifier.height(4.dp))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    if (person != null) {
                        TextButton(
                            onClick = { onDelete(person) },
                            colors = ButtonDefaults.textButtonColors(
                                contentColor = MaterialTheme.colorScheme.error
                            )
                        ) {
                            Text("Delete")
                        }
                    } else {
                        Spacer(modifier = Modifier.width(1.dp))
                    }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        TextButton(onClick = onDismiss) { Text("Cancel") }
                        Spacer(modifier = Modifier.width(8.dp))
                        Button(
                            onClick = {
                                val name = displayName.trim()
                                if (name.isNotBlank()) {
                                    val base = person ?: Person(
                                        displayName = name,
                                        avatarColor = newAvatarColor
                                    )
                                    onSave(
                                        base.copy(
                                            displayName = name,
                                            discordHandle = discordHandle.trim(),
                                            interests = interests.trim(),
                                            vibe = vibe.trim(),
                                            communicationStyle = communicationStyle.trim(),
                                            notes = notes.trim(),
                                            consentStatus = consent,
                                            updatedAt = System.currentTimeMillis()
                                        )
                                    )
                                }
                            },
                            enabled = displayName.isNotBlank()
                        ) {
                            Text("Save")
                        }
                    }
                }
            }
        }
    }
}

private fun splitItems(value: String): List<String> =
    value.split(',', ';', '/', '\n')
        .map { it.trim() }
        .filter { it.isNotEmpty() }
        .map { it.replaceFirstChar { char -> char.uppercase() } }

private fun copyToClipboard(context: Context, text: String, message: String) {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
    clipboard?.setPrimaryClip(ClipData.newPlainText("Wingman", text))
    Toast.makeText(context, message, Toast.LENGTH_SHORT).show()
}
