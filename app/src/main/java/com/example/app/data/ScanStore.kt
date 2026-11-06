package com.example.app.data

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Small process-wide bridge between the accessibility service and the UI.
 *
 * The service writes a snapshot here; the screen observes it and opens the
 * review step. Nothing is captured unless [arm] was called by the user.
 */
object ScanStore {

    private val _connected = MutableStateFlow(false)
    val connected: StateFlow<Boolean> = _connected.asStateFlow()

    private val _armed = MutableStateFlow(false)
    val armed: StateFlow<Boolean> = _armed.asStateFlow()

    private val _snapshot = MutableStateFlow<ScanSnapshot?>(null)
    val snapshot: StateFlow<ScanSnapshot?> = _snapshot.asStateFlow()

    /** Set by the service so the UI can ask for an immediate capture. */
    @Volatile
    var captureHandler: (() -> Unit)? = null

    fun setConnected(value: Boolean) {
        _connected.value = value
        if (!value) captureHandler = null
    }

    fun arm() {
        _snapshot.value = null
        _armed.value = true
    }

    fun disarm() {
        _armed.value = false
    }

    fun requestCapture(): Boolean {
        val handler = captureHandler ?: return false
        handler()
        return true
    }

    fun publish(snapshot: ScanSnapshot) {
        if (!_armed.value || snapshot.lines.isEmpty()) return
        _snapshot.value = snapshot
        _armed.value = false
    }

    fun clearSnapshot() {
        _snapshot.value = null
    }
}
