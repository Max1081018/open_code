package com.example.app.data

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "people")
data class Person(
    @PrimaryKey(autoGenerate = true) val id: Long = 0L,
    val displayName: String,
    val discordHandle: String = "",
    val avatarColor: Long = DEFAULT_AVATAR_COLOR,
    val interests: String = "",
    val vibe: String = "",
    val communicationStyle: String = "",
    val notes: String = "",
    val consentStatus: ConsentStatus = ConsentStatus.NOT_STARTED,
    @ColumnInfo(defaultValue = "0") val lastScanAt: Long = 0L,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis()
) {
    val initials: String
        get() = displayName.trim()
            .split(' ', '\t', '\n')
            .filter { it.isNotBlank() }
            .take(2)
            .joinToString("") { it.first().uppercase() }
            .ifBlank { "?" }

    companion object {
        const val DEFAULT_AVATAR_COLOR: Long = 0xFF4F46E5

        /** Stable, pleasant palette so each friend gets a distinct avatar. */
        val AVATAR_PALETTE: List<Long> = listOf(
            0xFF4F46E5,
            0xFF0EA5E9,
            0xFF10B981,
            0xFFF59E0B,
            0xFFEC4899,
            0xFF8B5CF6
        )
    }
}

enum class ConsentStatus(val label: String) {
    NOT_STARTED("Not started"),
    AGREED("Agreed"),
    ACTIVE("Active"),
    PAUSED("Paused");

    val allowsContact: Boolean
        get() = this == AGREED || this == ACTIVE
}
