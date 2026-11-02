package com.example.app.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

@Dao
interface PersonalityProfileDao {

    @Query("SELECT * FROM personality_profiles ORDER BY updatedAt DESC, id DESC")
    fun observeAll(): Flow<List<PersonalityProfile>>

    @Query("SELECT * FROM personality_profiles WHERE personId = :personId ORDER BY updatedAt DESC, id DESC")
    fun observeByPerson(personId: Long): Flow<List<PersonalityProfile>>

    @Query("SELECT * FROM personality_profiles WHERE personId = :personId ORDER BY updatedAt DESC, id DESC")
    suspend fun allForPerson(personId: Long): List<PersonalityProfile>

    @Insert
    suspend fun insert(profile: PersonalityProfile): Long

    @Insert
    suspend fun insertAll(profiles: List<PersonalityProfile>)

    @Update
    suspend fun update(profile: PersonalityProfile)
}
