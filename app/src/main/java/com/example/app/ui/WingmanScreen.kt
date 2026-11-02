@file:OptIn(ExperimentalMaterial3Api::class)

package com.example.app.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.animateContentSize
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
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.example.app.data.ChatMessage
import com.example.app.data.ConsentStatus
import com.example.app.data.Person
import com.example.app.data.PersonalityProfile
import com.example.app.data.WingmanBrain
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun WingmanScreen(
    vm: WingmanViewModel,
    themeMode: ThemeMode,
    onCycleTheme: () -> Unit
) {
    val selectedPerson = vm.selectedPerson.collectAsStateWithLifecycle().value

    if (selectedPerson == null) {
        PeopleScreen(
            vm = vm,
            themeMode = themeMode,
            onCycleTheme = onCycleTheme,
            onOpenChat = { vm.selectPerson(it.id) }
        )
    } else {
        BackHandler { vm.selectPerson(null) }
        ChatScreen(
            vm = vm,
            person = selectedPerson,
            themeMode = themeMode,
            onCycleTheme = onCycleTheme,
            onBack = { vm.selectPerson(null) }
        )
    }
}

@Composable
private fun PeopleScreen(
    vm: WingmanViewModel,
    themeMode: ThemeMode,
    onCycleTheme: () -> Unit,
    onOpenChat: (Person) -> Unit
) {
    val everyone by vm.people.collectAsStateWithLifecycle()
    val people by vm.filteredPeople.collectAsStateWithLifecycle()
    val query by vm.query.collectAsStateWithLifecycle()

    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    var showEditor by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf<Person?>(null) }
    var newAvatarColor by remember { mutableStateOf(Person.DEFAULT_AVATAR_COLOR) }

    fun openNew() {
        editing = null
        newAvatarColor = vm.nextAvatarColor()
        vm.query.value = ""
        showEditor = true
    }

    fun openEdit(person: Person) {
        editing = person
        newAvatarColor = person.avatarColor
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
                                everyone.isEmpty() -> "Your offline friend notebook"
                                everyone.size == 1 -> "1 friend"
                                else -> "${everyone.size} friends"
                            },
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                },
                actions = {
                    TextButton(onClick = onCycleTheme) { Text(themeMode.label) }
                }
            )
        },
        floatingActionButton = {
            FloatingActionButton(onClick = { openNew() }) {
                Icon(Icons.Filled.Add, contentDescription = "Add friend")
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
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    placeholder = { Text("Search friends, vibes, interests") },
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

            if (people.isEmpty()) {
                EmptyPeopleState(
                    hasFriends = everyone.isNotEmpty(),
                    query = query,
                    modifier = Modifier.weight(1f)
                )
            } else {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f),
                    contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 96.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    items(people, key = { it.id }) { person ->
                        PersonCard(
                            person = person,
                            onOpenChat = { onOpenChat(person) },
                            onEdit = { openEdit(person) },
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
            }
        )
    }
}

@Composable
private fun PersonCard(
    person: Person,
    onOpenChat: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .animateContentSize(),
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = 10.dp, end = 2.dp, top = 10.dp, bottom = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(46.dp)
                    .background(Color(person.avatarColor), CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = person.initials,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )
            }
            Spacer(modifier = Modifier.width(12.dp))
            Column(
                modifier = Modifier
                    .weight(1f)
                    .clickable(onClick = onOpenChat)
                    .padding(vertical = 2.dp),
                verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = person.displayName,
                        style = MaterialTheme.typography.bodyLarge,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f, fill = false)
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    ConsentPill(person.consentStatus)
                }
                if (person.discordHandle.isNotBlank()) {
                    Text(
                        text = person.discordHandle,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                val detail = listOfNotNull(
                    person.vibe.takeIf { it.isNotBlank() },
                    person.interests.takeIf { it.isNotBlank() }
                ).joinToString(" • ")
                Text(
                    text = detail.ifBlank { "Tap to open chat notes" },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            IconButton(onClick = onEdit) {
                Icon(Icons.Filled.Edit, contentDescription = "Edit ${person.displayName}")
            }
            IconButton(onClick = onDelete) {
                Icon(
                    imageVector = Icons.Filled.Delete,
                    contentDescription = "Delete ${person.displayName}",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun ConsentPill(status: ConsentStatus) {
    val background = when (status) {
        ConsentStatus.ACTIVE -> MaterialTheme.colorScheme.primaryContainer
        ConsentStatus.AGREED -> MaterialTheme.colorScheme.secondaryContainer
        ConsentStatus.PAUSED -> MaterialTheme.colorScheme.surfaceVariant
        ConsentStatus.NOT_STARTED -> MaterialTheme.colorScheme.surfaceVariant
    }
    val foreground = when (status) {
        ConsentStatus.ACTIVE -> MaterialTheme.colorScheme.onPrimaryContainer
        ConsentStatus.AGREED -> MaterialTheme.colorScheme.onSecondaryContainer
        ConsentStatus.PAUSED -> MaterialTheme.colorScheme.onSurfaceVariant
        ConsentStatus.NOT_STARTED -> MaterialTheme.colorScheme.onSurfaceVariant
    }
    Surface(shape = CircleShape, color = background) {
        Text(
            text = status.label,
            style = MaterialTheme.typography.labelSmall,
            color = foreground,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp)
        )
    }
}

@Composable
private fun EmptyPeopleState(
    hasFriends: Boolean,
    query: String,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Text(
            text = if (hasFriends) "No matches" else "👋",
            style = MaterialTheme.typography.displayMedium
        )
        Spacer(modifier = Modifier.height(12.dp))
        Text(
            text = if (hasFriends) {
                "Nobody matches \"$query\""
            } else {
                "Add a friend to keep track of their vibe, interests and chat notes."
            },
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        if (!hasFriends) {
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "Tap + to get started.",
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary
            )
        }
    }
}

@Composable
private fun ChatScreen(
    vm: WingmanViewModel,
    person: Person,
    themeMode: ThemeMode,
    onCycleTheme: () -> Unit,
    onBack: () -> Unit
) {
    val messages by vm.messages.collectAsStateWithLifecycle()
    val profile = vm.profile.collectAsStateWithLifecycle().value

    var text by remember(person.id) { mutableStateOf("") }
    var sender by remember(person.id) { mutableStateOf(ChatMessage.MessageSender.USER) }
    val listState = rememberLazyListState()

    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty()) {
            listState.scrollToItem(messages.lastIndex)
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(person.displayName, fontWeight = FontWeight.SemiBold)
                        Text(
                            text = if (person.discordHandle.isBlank()) {
                                person.consentStatus.label
                            } else {
                                "${person.discordHandle} · ${person.consentStatus.label}"
                            },
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
            if (!person.consentStatus.allowsContact) {
                ConsentNotice(person.consentStatus)
            }

            if (profile == null) {
                NoProfileCard(onGenerate = { vm.generateProfile() })
            } else {
                ProfileCard(profile = profile, onRefresh = { vm.generateProfile() })
            }

            if (messages.isEmpty()) {
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                        .padding(24.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = "No messages logged yet.\nLog what you sent and what they said.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            } else {
                LazyColumn(
                    state = listState,
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth(),
                    contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
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
}

@Composable
private fun ConsentNotice(status: ConsentStatus) {
    Surface(
        color = MaterialTheme.colorScheme.secondaryContainer,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        shape = RoundedCornerShape(12.dp)
    ) {
        Text(
            text = when (status) {
                ConsentStatus.PAUSED -> "This chat is paused. Give them space and check in later."
                ConsentStatus.NOT_STARTED -> "Consent not confirmed yet. Ask before messaging."
                else -> ""
            },
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSecondaryContainer,
            modifier = Modifier.padding(12.dp)
        )
    }
}

@Composable
private fun NoProfileCard(onGenerate: () -> Unit) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = "No wingman profile yet",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onPrimaryContainer
            )
            Text(
                text = "Build one on-device from the notes and chat history you have saved.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onPrimaryContainer
            )
            Button(onClick = onGenerate) { Text("Generate profile") }
        }
    }
}

@Composable
private fun ProfileCard(profile: PersonalityProfile, onRefresh: () -> Unit) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = "Wingman profile",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onPrimaryContainer,
                    modifier = Modifier.weight(1f)
                )
                IconButton(onClick = onRefresh) {
                    Icon(
                        imageVector = Icons.Filled.Refresh,
                        contentDescription = "Regenerate profile",
                        tint = MaterialTheme.colorScheme.onPrimaryContainer
                    )
                }
            }
            Text(
                text = profile.summary,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onPrimaryContainer
            )
            ProfileLine("Vibe", profile.vibe)
            ProfileLine("Interests", profile.interests)
            ProfileLine("Style", profile.communicationStyle)
            ProfileLine("Opener", profile.suggestedOpener)

            LinearProgressIndicator(
                progress = { profile.confidence },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(4.dp)
            )
            Text(
                text = "Confidence ${WingmanBrain.confidencePercent(profile)}% · generated on-device",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onPrimaryContainer
            )
        }
    }
}

@Composable
private fun ProfileLine(label: String, value: String) {
    if (value.isBlank()) return
    Text(
        text = "$label: $value",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onPrimaryContainer
    )
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
    onSave: (Person) -> Unit
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
                    text = if (person == null) "New friend" else "Edit friend",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.SemiBold
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
                    label = { Text("Discord handle") },
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
                    label = { Text("Communication style") },
                    minLines = 2,
                    maxLines = 4,
                    modifier = Modifier.fillMaxWidth()
                )

                OutlinedTextField(
                    value = notes,
                    onValueChange = { notes = it },
                    label = { Text("Notes") },
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
                    horizontalArrangement = Arrangement.End,
                    verticalAlignment = Alignment.CenterVertically
                ) {
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
