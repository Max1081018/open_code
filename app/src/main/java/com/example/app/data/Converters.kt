package com.example.app.data

import androidx.room.TypeConverter

class Converters {

    @TypeConverter
    fun fromConsentStatus(value: Int): ConsentStatus =
        ConsentStatus.values().getOrNull(value) ?: ConsentStatus.NOT_STARTED

    @TypeConverter
    fun toConsentStatus(value: ConsentStatus): Int = value.ordinal

    @TypeConverter
    fun fromMessageSender(value: Int): ChatMessage.MessageSender =
        ChatMessage.MessageSender.values().getOrNull(value) ?: ChatMessage.MessageSender.OTHER

    @TypeConverter
    fun toMessageSender(value: ChatMessage.MessageSender): Int = value.ordinal
}
