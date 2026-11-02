package com.example.app.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.room.withTransaction
import com.example.app.data.ChatMessage
import com.example.app.data.Person
import com.example.app.data.PersonalityProfile
import com.example.app.data.WingmanBrain
import com.example.app.data.WingmanDatabase
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

class WingmanViewModel(app: Application) : AndroidViewModel(app) {

    private val database = WingmanDatabase.get(app)
    private val personDao = database.personDao()
    private val chatMessageDao = database.chatMessageDao()
    private val personalityProfileDao = database.personalityProfileDao()

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
                personDao.update(person.copy(updatedAt = now))
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

    private fun Person.matches(needle: String): Boolean =
        listOf(displayName, discordHandle, vibe, interests, notes, communicationStyle)
            .any { it.contains(needle, ignoreCase = true) }

    private data class DeletedPerson(
        val person: Person,
        val messages: List<ChatMessage>,
        val profiles: List<PersonalityProfile>
    )
}
