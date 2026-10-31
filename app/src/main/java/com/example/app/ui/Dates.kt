package com.example.app.ui

import com.example.app.data.Task
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

object Dates {

    fun startOfToday(): Long {
        val calendar = Calendar.getInstance()
        calendar.set(Calendar.HOUR_OF_DAY, 0)
        calendar.set(Calendar.MINUTE, 0)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)
        return calendar.timeInMillis
    }

    fun addDays(days: Int): Long {
        val calendar = Calendar.getInstance()
        calendar.timeInMillis = startOfToday()
        calendar.add(Calendar.DAY_OF_YEAR, days)
        return calendar.timeInMillis
    }

    fun isOverdue(task: Task): Boolean =
        !task.completed && task.dueAt != null && task.dueAt < startOfToday()

    fun label(dueAt: Long): String = when (dueAt) {
        startOfToday() -> "Today"
        addDays(1) -> "Tomorrow"
        addDays(-1) -> "Yesterday"
        else -> SimpleDateFormat("EEE, d MMM", Locale.getDefault()).format(Date(dueAt))
    }

    fun isQuickPick(dueAt: Long?): Boolean =
        dueAt == null ||
            dueAt == startOfToday() ||
            dueAt == addDays(1) ||
            dueAt == addDays(7)
}
