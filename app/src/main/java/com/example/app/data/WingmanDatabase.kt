package com.example.app.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

@Database(
    entities = [Person::class, ChatMessage::class, PersonalityProfile::class],
    version = 1,
    exportSchema = false,
    typeConverters = [Converters::class]
)
abstract class WingmanDatabase : RoomDatabase() {

    abstract fun personDao(): PersonDao

    abstract fun chatMessageDao(): ChatMessageDao

    abstract fun personalityProfileDao(): PersonalityProfileDao

    companion object {
        @Volatile
        private var instance: WingmanDatabase? = null

        fun get(context: Context): WingmanDatabase =
            instance ?: synchronized(this) {
                instance ?: Room.databaseBuilder(
                    context.applicationContext,
                    WingmanDatabase::class.java,
                    "wingman.db"
                ).build().also { instance = it }
            }
    }
}
