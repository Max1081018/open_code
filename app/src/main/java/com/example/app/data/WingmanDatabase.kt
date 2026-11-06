package com.example.app.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(
    entities = [Person::class, ChatMessage::class, PersonalityProfile::class],
    version = 3,
    exportSchema = false
)
@TypeConverters(Converters::class)
abstract class WingmanDatabase : RoomDatabase() {

    abstract fun personDao(): PersonDao

    abstract fun chatMessageDao(): ChatMessageDao

    abstract fun personalityProfileDao(): PersonalityProfileDao

    companion object {
        /**
         * Adds the scan metadata. Defaults are declared on the entities too, so
         * Room's schema check accepts the migrated tables.
         */
        val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL(
                    "ALTER TABLE people ADD COLUMN lastScanAt INTEGER NOT NULL DEFAULT 0"
                )
                database.execSQL(
                    "ALTER TABLE personality_profiles ADD COLUMN greenFlags TEXT NOT NULL DEFAULT ''"
                )
                database.execSQL(
                    "ALTER TABLE personality_profiles ADD COLUMN redFlags TEXT NOT NULL DEFAULT ''"
                )
                database.execSQL(
                    "ALTER TABLE personality_profiles ADD COLUMN signals TEXT NOT NULL DEFAULT ''"
                )
                database.execSQL(
                    "ALTER TABLE personality_profiles ADD COLUMN source TEXT NOT NULL DEFAULT ''"
                )
                database.execSQL(
                    "ALTER TABLE personality_profiles ADD COLUMN lastTranscript TEXT NOT NULL DEFAULT ''"
                )
                database.execSQL(
                    "ALTER TABLE personality_profiles ADD COLUMN scanCount INTEGER NOT NULL DEFAULT 0"
                )
            }
        }

        /**
         * Adds psychological profile fields (attachment style, emotional needs).
         */
        val MIGRATION_2_3 = object : Migration(2, 3) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL(
                    "ALTER TABLE personality_profiles ADD COLUMN attachmentStyle TEXT NOT NULL DEFAULT 'unclear'"
                )
                database.execSQL(
                    "ALTER TABLE personality_profiles ADD COLUMN emotionalNeeds TEXT NOT NULL DEFAULT ''"
                )
            }
        }

        @Volatile
        private var instance: WingmanDatabase? = null

        fun get(context: Context): WingmanDatabase =
            instance ?: synchronized(this) {
                instance ?: Room.databaseBuilder(
                    context.applicationContext,
                    WingmanDatabase::class.java,
                    "wingman.db"
                )
                    .addMigrations(MIGRATION_1_2, MIGRATION_2_3)
                    .build()
                    .also { instance = it }
            }
    }
}
