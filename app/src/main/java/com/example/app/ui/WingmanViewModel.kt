package com.example.app.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.room.withTransaction
import com.example.app.data.ChatMessage
import com.example.app.data.CoachConfig
import com.example.app.data.CoachException
import com.example.app.data.CoachLine
import com.example.app.data.CoachReply
import com.example.app.data.CoachSettings
import com.example.app.data.LocalWingman
import com.example.app.data.Person
import com.example.app.data.PersonalityProfile
import com.example.app.data.RemoteAi
import com.example.app.data.ReplyCoach
import com.example.app.data.ResilientWingman
import com.example.app.data.ScanNotifier
import com.example.app.data.ScanSnapshot
import com.example.app.data.ScanStore
import com.example.app.data.ScreenAnalysis
import com.example.app.data.WingmanAi
import com.example.app.data.WingmanBrain
import com.example.app.data.WingmanDatabase
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** What the reply coach is currently doing. */
sealed interface CoachUiState {
    data object Idle : CoachUiState
    data object Loading : CoachUiState
    data class Ready(val reply: CoachReply) : CoachUiState
    data class Failed(val message: String) : CoachUiState
}

enum class ScanStage { ARMING, REVIEW, RESULT }

/** Everything the scan dialog needs, kept in the ViewModel so rotation is safe. */
data class ScanSession(
    val visible: Boolean = false,
    val stage: ScanStage = ScanStage.ARMING,
    val targetPerson: Person? = null,
    val snapshot: ScanSnapshot? = null,
    val transcript: String = "",
    val name: String = "",
    val analysis: ScreenAnalysis? = null,
    val busy: Boolean = false,
    val error: String? = null,
    val serviceConnected: Boolean = false
)

/** Result of pressing "Test" in AI settings. */
data class AiTestState(
    val running: Boolean = false,
    val ok: Boolean = false,
    val message: String = ""
)

class WingmanViewModel(app: Application) : AndroidViewModel(app) {

    private val database = WingmanDatabase.get(app)
    private val personDao = database.personDao()
    private val chatMessageDao = database.chatMessageDao()
    private val personalityProfileDao = database.personalityProfileDao()

    private val coachSettings by lazy { CoachSettings(getApplication<Application>()) }

    /** Keystore work is deferred until the coach is first opened, off the startup path. */
    val coachConfig: StateFlow<CoachConfig> by lazy { coachSettings.config }

    /** False when secure storage failed and the key will not survive a restart. */
    val coachStoragePersistent: Boolean by lazy { coachSettings.isPersistent }

    /** Swappable so the AI layer can be tested without touching the network. */
    internal var aiFactory: (CoachConfig) -> WingmanAi = { ResilientWingman(RemoteAi(it)) }

    val people: StateFlow<List<Person>> =
        personDao.observeAll()
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val profiles: StateFlow<List<PersonalityProfile>> =
        personalityProfileDao.observeAll()
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val query = MutableStateFlow("")

    val filteredPeople: StateFlow<List<Person>> =
        combine(people, query) { all, text ->
            val needle = text.trim()
            if (needle.isEmpty()) {
                all
            } else {
                all.filter { person -> person.matches(needle) }
            }
        }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    private val _selectedPersonId = MutableStateFlow<Long?>(null)
    val selectedPersonId: StateFlow<Long?> = _selectedPersonId.asStateFlow()

    val selectedPerson: StateFlow<Person?> =
        combine(_selectedPersonId, people) { id, all ->
            if (id == null) null else all.firstOrNull { it.id == id }
        }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    val messages: StateFlow<List<ChatMessage>> = _selectedPersonId
        .flatMapLatest { id ->
            if (id == null) flowOf(emptyList()) else chatMessageDao.observeForPerson(id)
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val profile: StateFlow<PersonalityProfile?> = _selectedPersonId
        .flatMapLatest { id ->
            if (id == null) {
                flowOf<PersonalityProfile?>(null)
            } else {
                personalityProfileDao.observeByPerson(id).map { it.firstOrNull() }
            }
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    private val _notice = MutableStateFlow<String?>(null)
    val notice: StateFlow<String?> = _notice.asStateFlow()

    private var lastDeleted: DeletedPerson? = null

    private val _scan = MutableStateFlow(ScanSession(serviceConnected = ScanStore.connected.value))
    val scan: StateFlow<ScanSession> = _scan.asStateFlow()

    private var scanJob: Job? = null

    init {
        viewModelScope.launch {
            ScanStore.snapshot.collect { snapshot ->
                if (snapshot == null) return@collect
                val current = _scan.value
                if (!current.visible || current.stage != ScanStage.ARMING) return@collect
                _scan.value = current.copy(
                    stage = ScanStage.REVIEW,
                    snapshot = snapshot,
                    transcript = snapshot.transcript,
                    name = current.targetPerson?.displayName
                        ?.takeIf { it.isNotBlank() }
                        ?: snapshot.nameGuess,
                    error = null,
                    busy = false
                )
                ScanNotifier.cancel(getApplication())
            }
        }
        viewModelScope.launch {
            ScanStore.connected.collect { connected ->
                if (_scan.value.serviceConnected != connected) {
                    _scan.value = _scan.value.copy(serviceConnected = connected)
                }
            }
        }
    }

    fun selectPerson(id: Long?) {
        _selectedPersonId.value = id
    }

    fun consumeNotice() {
        _notice.value = null
    }

    fun nextAvatarColor(): Long {
        val palette = Person.AVATAR_PALETTE
        return palette[people.value.size % palette.size]
    }

    fun savePerson(person: Person) {
        viewModelScope.launch {
            val now = System.currentTimeMillis()
            if (person.id == 0L) {
                personDao.insert(person.copy(createdAt = now, updatedAt = now))
            } else {
                val saved = person.copy(updatedAt = now)
                personDao.update(saved)
                // Keep an existing notes profile in sync with the details that feed it.
                val existing = personalityProfileDao.allForPerson(person.id).firstOrNull()
                if (existing != null && existing.lastTranscript.isBlank()) {
                    val refreshed = WingmanBrain.profileFor(
                        person = saved,
                        history = chatMessageDao.allForPerson(person.id),
                        profileId = existing.id
                    ).copy(
                        createdAt = existing.createdAt,
                        greenFlags = existing.greenFlags,
                        redFlags = existing.redFlags,
                        signals = existing.signals,
                        scanCount = existing.scanCount
                    )
                    personalityProfileDao.update(refreshed)
                }
            }
        }
    }

    /**
     * Deletes the friend together with their chat history and profile, but keeps a
     * full in-memory backup so "Undo" can put everything back exactly as it was.
     */
    fun deletePerson(person: Person) {
        viewModelScope.launch {
            val backup = database.withTransaction {
                val snapshot = DeletedPerson(
                    person = person,
                    messages = chatMessageDao.allForPerson(person.id),
                    profiles = personalityProfileDao.allForPerson(person.id)
                )
                personDao.deleteById(person.id)
                snapshot
            }
            lastDeleted = backup
            if (_selectedPersonId.value == person.id) {
                _selectedPersonId.value = null
            }
        }
    }

    fun restoreDeletedPerson() {
        val backup = lastDeleted ?: return
        lastDeleted = null
        viewModelScope.launch {
            database.withTransaction {
                personDao.insert(backup.person)
                if (backup.messages.isNotEmpty()) chatMessageDao.insertAll(backup.messages)
                if (backup.profiles.isNotEmpty()) personalityProfileDao.insertAll(backup.profiles)
            }
        }
    }

    fun sendMessage(text: String, sender: ChatMessage.MessageSender) {
        val trimmed = text.trim()
        val person = selectedPerson.value ?: return
        if (trimmed.isEmpty()) return
        viewModelScope.launch {
            chatMessageDao.insert(
                ChatMessage(
                    personId = person.id,
                    sender = sender,
                    text = trimmed
                )
            )
            personDao.update(person.copy(updatedAt = System.currentTimeMillis()))
        }
    }

    fun generateProfile() {
        val person = selectedPerson.value ?: return
        viewModelScope.launch {
            val history = chatMessageDao.allForPerson(person.id)
            val existing = personalityProfileDao.allForPerson(person.id).firstOrNull()
            val generated = WingmanBrain.profileFor(
                person = person,
                history = history,
                profileId = existing?.id ?: 0L
            ).let { profile ->
                if (existing == null) {
                    profile
                } else {
                    profile.copy(
                        createdAt = existing.createdAt,
                        lastTranscript = existing.lastTranscript,
                        scanCount = existing.scanCount,
                        greenFlags = existing.greenFlags,
                        redFlags = existing.redFlags,
                        signals = existing.signals
                    )
                }
            }
            if (existing == null) {
                personalityProfileDao.insert(generated)
            } else {
                personalityProfileDao.update(generated)
            }
            _notice.value = "Profile rebuilt from your notes"
        }
    }

    // ---- Screen scan -------------------------------------------------------

    fun openScan(person: Person?) {
        scanJob?.cancel()
        ScanStore.clearSnapshot()
        ScanStore.arm()
        ScanNotifier.armed(getApplication())
        _scan.value = ScanSession(
            visible = true,
            stage = ScanStage.ARMING,
            targetPerson = person,
            name = person?.displayName.orEmpty(),
            serviceConnected = ScanStore.connected.value
        )
    }

    fun closeScan() {
        scanJob?.cancel()
        ScanStore.disarm()
        ScanNotifier.cancel(getApplication())
        _scan.value = ScanSession(serviceConnected = ScanStore.connected.value)
    }

    /** Switch to the editable review step without a capture. */
    fun reviewManually(text: String) {
        ScanStore.disarm()
        ScanNotifier.cancel(getApplication())
        _scan.value = _scan.value.copy(
            visible = true,
            stage = ScanStage.REVIEW,
            transcript = text,
            snapshot = null,
            analysis = null,
            error = null,
            busy = false
        )
    }

    /** Use the last capture again, for example after accidentally closing review. */
    fun reviewCapturedSnapshot() {
        val snapshot = ScanStore.snapshot.value ?: return
        _scan.value = _scan.value.copy(
            visible = true,
            stage = ScanStage.REVIEW,
            snapshot = snapshot,
            transcript = snapshot.transcript,
            name = _scan.value.name.ifBlank { snapshot.nameGuess },
            error = null
        )
    }

    fun updateTranscript(text: String) {
        _scan.value = _scan.value.copy(transcript = text, error = null)
    }

    fun updateScanName(name: String) {
        _scan.value = _scan.value.copy(name = name, error = null)
    }

    fun analyzeScan() {
        val session = _scan.value
        val lines = ReplyCoach.parseTranscript(session.transcript)
            .filter { it.text.isNotBlank() }
        if (lines.isEmpty()) {
            _scan.value = session.copy(error = "There is no chat text to analyse yet.")
            return
        }
        if (lines.size == 1 && lines.single().text.length < 8) {
            _scan.value = session.copy(error = "That is only one short line. Capture a bit more of the chat.")
            return
        }

        scanJob?.cancel()
        _scan.value = session.copy(busy = true, error = null, stage = ScanStage.REVIEW)
        val config = coachConfig.value
        scanJob = viewModelScope.launch {
            try {
                val analysis = if (config.isReady) {
                    aiFactory(config).analyze(
                        appLabel = session.snapshot?.appLabel.orEmpty().ifBlank { "chat" },
                        personName = session.name.trim().ifBlank { null },
                        transcript = lines,
                        theirStyle = session.targetPerson?.communicationStyle.orEmpty(),
                        myVoice = config.myVoice
                    )
                } else {
                    LocalWingman.analyze(
                        personName = session.name,
                        transcript = lines,
                        theirStyle = session.targetPerson?.communicationStyle.orEmpty()
                    ).copy(notice = "No AI key for that provider, so this read is on-device.")
                }
                _scan.value = _scan.value.copy(
                    stage = ScanStage.RESULT,
                    analysis = analysis,
                    busy = false,
                    error = null
                )
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _scan.value = _scan.value.copy(
                    busy = false,
                    error = e.message ?: "The analysis failed. Try again."
                )
            }
        }
    }

    fun saveScanResult() {
        val session = _scan.value
        val analysis = session.analysis ?: return
        val draft = analysis.person
        val name = session.name.trim().ifBlank { draft.name.trim() }
        if (name.isBlank() && session.targetPerson == null) {
            _scan.value = session.copy(error = "Add their name before saving the profile.")
            return
        }

        viewModelScope.launch {
            val now = System.currentTimeMillis()
            val existing = session.targetPerson
            val personId: Long
            if (existing == null) {
                personId = personDao.insert(
                    Person(
                        displayName = name,
                        discordHandle = "",
                        avatarColor = nextAvatarColor(),
                        interests = draft.interests,
                        vibe = draft.vibe,
                        communicationStyle = draft.communicationStyle,
                        lastScanAt = now,
                        createdAt = now,
                        updatedAt = now
                    )
                )
            } else {
                personDao.update(
                    existing.copy(
                        displayName = name.ifBlank { existing.displayName },
                        interests = draft.interests.ifBlank { existing.interests },
                        vibe = draft.vibe.ifBlank { existing.vibe },
                        communicationStyle = draft.communicationStyle.ifBlank { existing.communicationStyle },
                        lastScanAt = now,
                        updatedAt = now
                    )
                )
                personId = existing.id
            }

            val previous = personalityProfileDao.allForPerson(personId).firstOrNull()
            val profile = PersonalityProfile(
                id = previous?.id ?: 0L,
                personId = personId,
                summary = draft.summary.ifBlank {
                    previous?.summary ?: "Profile built from a captured chat."
                },
                vibe = draft.vibe.ifBlank { previous?.vibe.orEmpty() },
                interests = draft.interests.ifBlank { previous?.interests.orEmpty() },
                communicationStyle = draft.communicationStyle.ifBlank {
                    previous?.communicationStyle.orEmpty()
                },
                confidence = draft.confidence,
                suggestedOpener = draft.opener.ifBlank { previous?.suggestedOpener.orEmpty() },
                greenFlags = draft.greenFlags,
                redFlags = draft.redFlags,
                signals = analysis.coach.signals,
                source = analysis.source.label,
                lastTranscript = session.transcript.take(6_000),
                scanCount = (previous?.scanCount ?: 0) + 1,
                createdAt = previous?.createdAt ?: now,
                updatedAt = now
            )

            if (previous == null) {
                personalityProfileDao.insert(profile)
            } else {
                personalityProfileDao.update(profile)
            }

            _selectedPersonId.value = personId
            val savedName = name.ifBlank { existing?.displayName.orEmpty() }.ifBlank { "their" }
            _notice.value = "Saved $savedName's profile"
            closeScan()
        }
    }

    // ---- Reply coach -------------------------------------------------------

    private val _showCoach = MutableStateFlow(false)
    val showCoach: StateFlow<Boolean> = _showCoach.asStateFlow()

    private val _coachState = MutableStateFlow<CoachUiState>(CoachUiState.Idle)
    val coachState: StateFlow<CoachUiState> = _coachState.asStateFlow()

    private var coachJob: Job? = null

    fun openCoach() {
        _coachState.value = CoachUiState.Idle
        _showCoach.value = true
    }

    fun closeCoach() {
        coachJob?.cancel()
        _showCoach.value = false
    }

    fun saveCoachConfig(config: CoachConfig) {
        coachSettings.save(config)
        _aiTest.value = AiTestState()
    }

    fun clearCoachKey() {
        coachSettings.clearKey()
    }

    /**
     * Sends the transcript to the configured provider. Only the transcript and
     * the style notes travel; the name, handle and private notes stay here.
     */
    fun askCoach(lines: List<CoachLine>) {
        val person = selectedPerson.value ?: return
        val config = coachConfig.value
        val cleaned = lines.filter { it.text.isNotBlank() }

        if (cleaned.isEmpty()) {
            _coachState.value = CoachUiState.Failed("Add what was said, then ask again.")
            return
        }

        coachJob?.cancel()
        _coachState.value = CoachUiState.Loading
        coachJob = viewModelScope.launch {
            try {
                val reply = if (config.isReady) {
                    aiFactory(config).suggest(
                        lines = cleaned,
                        theirStyle = person.communicationStyle,
                        myVoice = config.myVoice,
                        paused = !person.consentStatus.allowsContact
                    )
                } else {
                    LocalWingman.suggest(cleaned).copy(
                        notice = "No AI key for that provider, so this read is on-device."
                    )
                }
                _coachState.value = CoachUiState.Ready(reply)
            } catch (e: CancellationException) {
                throw e
            } catch (e: CoachException) {
                _coachState.value = CoachUiState.Failed(e.message ?: "Something went wrong.")
            } catch (e: Exception) {
                _coachState.value = CoachUiState.Failed(
                    "Something went wrong: ${e.javaClass.simpleName}"
                )
            }
        }
    }

    // ---- AI settings -------------------------------------------------------

    private val _aiTest = MutableStateFlow(AiTestState())
    val aiTest: StateFlow<AiTestState> = _aiTest.asStateFlow()

    fun testAi(config: CoachConfig) {
        if (!config.isReady) {
            _aiTest.value = AiTestState(
                message = if (config.provider.requiresKey) {
                    "Add a free ${config.provider.shortLabel} key first."
                } else {
                    "Check the base URL and model."
                }
            )
            return
        }
        _aiTest.value = AiTestState(running = true)
        viewModelScope.launch {
            try {
                val model = RemoteAi(config).test()
                _aiTest.value = AiTestState(
                    ok = true,
                    message = "Working. ${config.provider.shortLabel} answered as $model."
                )
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _aiTest.value = AiTestState(message = e.message ?: "The test failed.")
            }
        }
    }

    override fun onCleared() {
        coachJob?.cancel()
        scanJob?.cancel()
        super.onCleared()
    }

    private fun Person.matches(needle: String): Boolean =
        listOf(displayName, discordHandle, vibe, interests, notes, communicationStyle)
            .any { it.contains(needle, ignoreCase = true) }

    private data class DeletedPerson(
        val person: Person,
        val messages: List<ChatMessage>,
        val profiles: List<PersonalityProfile>
    )

    companion object {
        fun formatScanTime(value: Long): String {
            if (value <= 0L) return "never"
            val format = SimpleDateFormat("d MMM, HH:mm", Locale.getDefault())
            return format.format(Date(value))
        }
    }
}
