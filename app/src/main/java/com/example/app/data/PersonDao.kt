package com.example.app.data

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

@Dao
interface PersonDao {

    @Query("SELECT * FROM people ORDER BY updatedAt DESC, id DESC")
    fun observeAll(): Flow<List<Person>>

    @Query("SELECT * FROM people WHERE id = :id")
    suspend fun findById(id: Long): Person?

    @Insert
    suspend fun insert(person: Person): Long

    @Update
    suspend fun update(person: Person)

    @Delete
    suspend fun delete(person: Person)

    @Query("DELETE FROM people WHERE id = :id")
    suspend fun deleteById(id: Long)
}
