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
import com.example.app.data.OpenAiReplyEngine
import com.example.app.data.Person
import com.example.app.data.PersonalityProfile
import com.example.app.data.ReplyEngine
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

/** What the reply coach is currently doing. */
sealed interface CoachUiState {
    data object Idle : CoachUiState
    data object Loading : CoachUiState
    data class Ready(val reply: CoachReply) : CoachUiState
    data class Failed(val message: String) : CoachUiState
}

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

    /** Swappable so the coach can be tested without touching the network. */
    internal var engineFactory: (CoachConfig) -> ReplyEngine = { OpenAiReplyEngine(it) }

    val people: StateFlow<List<Person>> =
        personDao.observeAll()
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

    private var lastDeleted: DeletedPerson? = null

    fun selectPerson(id: Long?) {
        _selectedPersonId.value = id
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
                // Keep an existing profile in sync with the details that feed it.
                val existing = personalityProfileDao.allForPerson(person.id).firstOrNull()
                if (existing != null) {
                    val refreshed = WingmanBrain.profileFor(
                        person = saved,
                        history = chatMessageDao.allForPerson(person.id),
                        profileId = existing.id
                    ).copy(createdAt = existing.createdAt)
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
            ).let { generated ->
                // Keep the original creation time so "updated" means updated.
                if (existing == null) generated else generated.copy(createdAt = existing.createdAt)
            }
            if (existing == null) {
                personalityProfileDao.insert(generated)
            } else {
                personalityProfileDao.update(generated)
            }
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
        _showCoach.value = false
    }

    fun saveCoachConfig(config: CoachConfig) {
        coachSettings.save(config)
    }

    fun clearCoachKey() {
        coachSettings.clearKey()
    }

    /**
     * Sends the transcript to the configured provider. Only the transcript and
     * the two style notes travel; the name, handle and private notes stay here.
     */
    fun askCoach(lines: List<CoachLine>) {
        val person = selectedPerson.value ?: return
        val config = coachConfig.value
        val cleaned = lines.filter { it.text.isNotBlank() }

        if (!config.isReady) {
            _coachState.value = CoachUiState.Failed("Add your API key first, then try again.")
            return
        }
        if (cleaned.isEmpty()) {
            _coachState.value = CoachUiState.Failed("Add what was said, then ask again.")
            return
        }

        coachJob?.cancel()
        _coachState.value = CoachUiState.Loading
        coachJob = viewModelScope.launch {
            try {
                val reply = engineFactory(config).suggest(
                    lines = cleaned,
                    theirStyle = person.communicationStyle,
                    myVoice = config.myVoice,
                    paused = !person.consentStatus.allowsContact
                )
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

    override fun onCleared() {
        coachJob?.cancel()
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
}
