package com.example.app.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.example.app.data.AppDatabase
import com.example.app.data.Task
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

enum class TaskFilter(val label: String) {
    ALL("All"),
    ACTIVE("Active"),
    DONE("Done")
}

enum class SortMode(val label: String) {
    SMART("Smart"),
    DUE("Due date"),
    PRIORITY("Priority"),
    NEWEST("Newest")
}

class TaskViewModel(app: Application) : AndroidViewModel(app) {

    private val dao = AppDatabase.get(app).taskDao()

    val query = MutableStateFlow("")
    val filter = MutableStateFlow(TaskFilter.ALL)
    val sort = MutableStateFlow(SortMode.SMART)

    val tasks: StateFlow<List<Task>> =
        combine(dao.observeAll(), query, filter, sort) { all, text, activeFilter, sortMode ->
            var result = all
            if (text.isNotBlank()) {
                result = result.filter {
                    it.title.contains(text, ignoreCase = true) ||
                        it.notes.contains(text, ignoreCase = true)
                }
            }
            result = when (activeFilter) {
                TaskFilter.ALL -> result
                TaskFilter.ACTIVE -> result.filter { !it.completed }
                TaskFilter.DONE -> result.filter { it.completed }
            }
            when (sortMode) {
                SortMode.SMART -> result.sortedWith(
                    compareByDescending<Task> { it.pinned }
                        .thenBy { it.completed }
                        .thenBy { it.dueAt == null }
                        .thenBy { it.dueAt ?: Long.MAX_VALUE }
                        .thenByDescending { it.priority }
                        .thenByDescending { it.createdAt }
                )
                SortMode.DUE -> result.sortedWith(
                    compareBy<Task> { it.dueAt == null }
                        .thenBy { it.dueAt ?: Long.MAX_VALUE }
                        .thenByDescending { it.priority }
                )
                SortMode.PRIORITY -> result.sortedWith(
                    compareByDescending<Task> { it.priority }
                        .thenBy { it.completed }
                        .thenByDescending { it.createdAt }
                )
                SortMode.NEWEST -> result.sortedByDescending { it.createdAt }
            }
        }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val stats: StateFlow<Pair<Int, Int>> = dao.observeAll()
        .map { all -> all.count { it.completed } to all.size }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), 0 to 0)

    fun save(task: Task) {
        viewModelScope.launch {
            if (task.id == 0L) dao.insert(task) else dao.update(task)
        }
    }

    fun toggle(task: Task) {
        viewModelScope.launch { dao.setCompleted(task.id, !task.completed) }
    }

    fun togglePin(task: Task) {
        viewModelScope.launch { dao.setPinned(task.id, !task.pinned) }
    }

    fun delete(task: Task) {
        viewModelScope.launch { dao.delete(task) }
    }

    fun restore(task: Task) {
        viewModelScope.launch { dao.insert(task) }
    }
}
