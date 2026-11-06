package com.example.app.data

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.example.app.MainActivity
import com.example.app.R

/**
 * A single, quiet notification while a scan is armed, and one when the chat has
 * been captured. This is what lets the user switch to Discord and know they can
 * come back. Notifications are optional: every call is a no-op when the user has
 * not granted the permission.
 */
object ScanNotifier {

    private const val CHANNEL = "wingman_scan"
    private const val ID = 4107

    fun armed(context: Context) {
        post(
            context = context,
            title = "Wingman is ready to scan",
            text = "Open the chat you want to read. Tap here when you are done."
        )
    }

    fun captured(context: Context) {
        post(
            context = context,
            title = "Chat captured",
            text = "Tap to review the messages and get your read."
        )
    }

    fun cancel(context: Context) {
        runCatching { NotificationManagerCompat.from(context).cancel(ID) }
    }

    private fun post(context: Context, title: String, text: String) {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        val manager = NotificationManagerCompat.from(context)
        if (!manager.areNotificationsEnabled()) return

        if (Build.VERSION.SDK_INT >= 26) {
            val channel = NotificationChannel(
                CHANNEL,
                "Chat scans",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows when Wingman is ready to read a chat"
                setShowBadge(false)
            }
            manager.createNotificationChannel(channel)
        }

        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(pending)
            .setAutoCancel(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        runCatching { manager.notify(ID, notification) }
    }
}
