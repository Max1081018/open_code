package com.example.app.data

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface ChatMessageDao {

    @Query("SELECT * FROM chat_messages WHERE personId = :personId ORDER BY createdAt ASC, id ASC")
    fun observeForPerson(personId: Long): Flow<List<ChatMessage>>

    @Query("SELECT * FROM chat_messages WHERE personId = :personId ORDER BY createdAt ASC, id ASC")
    suspend fun allForPerson(personId: Long): List<ChatMessage>

    @Insert
    suspend fun insert(message: ChatMessage): Long

    @Insert
    suspend fun insertAll(messages: List<ChatMessage>)

    @Delete
    suspend fun delete(message: ChatMessage)
}
