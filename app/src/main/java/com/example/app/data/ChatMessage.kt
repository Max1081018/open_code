package com.example.app.data

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "chat_messages",
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
data class ChatMessage(
    @PrimaryKey(autoGenerate = true) val id: Long = 0L,
    val personId: Long,
    val sender: MessageSender,
    val text: String,
    val createdAt: Long = System.currentTimeMillis()
) {
    val isFromMe: Boolean
        get() = sender == MessageSender.USER

    enum class MessageSender(val label: String) {
        USER("Me"),
        OTHER("Them")
    }
}
