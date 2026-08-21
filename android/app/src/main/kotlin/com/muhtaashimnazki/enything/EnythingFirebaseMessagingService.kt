package com.muhtaashimnazki.enything

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class EnythingFirebaseMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)

        val data = remoteMessage.data
        val title = remoteMessage.notification?.title ?: data["title"] ?: "New Order!"
        val body = remoteMessage.notification?.body ?: data["body"] ?: "You have a new order waiting"
        val role = data["role"]
        val action = data["action"]

        val isUrgent = role in listOf("rider", "delivery", "seller", "delivery_partner") ||
                action == "new_order" ||
                title.contains("New Order", ignoreCase = true) ||
                title.contains("Order Available", ignoreCase = true)

        if (isUrgent) {
            handleUrgentOrder(title, body, data)
        }
    }

    private fun handleUrgentOrder(title: String, body: String, data: Map<String, String>) {
        try {
            // 1. Wake the screen immediately via PowerManager WakeLock
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            @Suppress("DEPRECATION")
            val wakeLock = powerManager.newWakeLock(
                PowerManager.FULL_WAKE_LOCK or
                PowerManager.ACQUIRE_CAUSES_WAKEUP or
                PowerManager.ON_AFTER_RELEASE,
                "Enything:IncomingOrderWakeLock"
            )
            wakeLock.acquire(15000L) // 15 seconds wake lock

            // 2. Prepare Launch Intent for MainActivity
            val launchIntent = Intent(this, MainActivity::class.java).apply {
                action = "FLUTTER_NOTIFICATION_CLICK"
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP
                for ((k, v) in data) {
                    putExtra(k, v)
                }
            }

            val notifId = data["order_id"]?.hashCode() ?: System.currentTimeMillis().toInt()

            val fullScreenPendingIntent = PendingIntent.getActivity(
                this,
                notifId,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // 3. Create Notification Channel with Alarm sound
            val channelId = "enything_urgent_order_v1"
            val soundUri = Uri.parse("android.resource://" + packageName + "/" + R.raw.enything_bell)

            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    channelId,
                    "Enything Urgent Orders",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Urgent order notifications with screen wake up and alarm sound"
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 1000, 500, 1000, 500, 1000)
                    setSound(
                        soundUri,
                        AudioAttributes.Builder()
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .setUsage(AudioAttributes.USAGE_ALARM)
                            .build()
                    )
                    enableLights(true)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                }
                notificationManager.createNotificationChannel(channel)
            }

            // 4. Build Notification with Full-Screen Intent
            val notification = NotificationCompat.Builder(this, channelId)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(body)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setAutoCancel(true)
                .setSound(soundUri)
                .setVibrate(longArrayOf(0, 1000, 500, 1000, 500, 1000))
                .setFullScreenIntent(fullScreenPendingIntent, true)
                .setContentIntent(fullScreenPendingIntent)
                .build()

            notificationManager.notify(notifId, notification)

            // 5. Automatically launch MainActivity directly over lockscreen
            try {
                startActivity(launchIntent)
            } catch (e: Exception) {
                Log.e("EnythingFCM", "Failed to startActivity: $e")
            }

        } catch (e: Exception) {
            Log.e("EnythingFCM", "handleUrgentOrder error: $e")
        }
    }
}
