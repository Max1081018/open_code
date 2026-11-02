package com.example.app.data

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "personality_profiles",
    foreignKeys = [
        ForeignKey(
            entity = Person::class,
            parentColumns = ["id"],
            childColumns = ["personId"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [Index("personId")]
)
data class PersonalityProfile(
    @PrimaryKey(autoGenerate = true) val id: Long = 0L,
    val personId: Long,
    val summary: String,
    val vibe: String,
    val interests: String,
    val communicationStyle: String,
    val confidence: Float,
    val suggestedOpener: String,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis()
)
