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
        val title = remoteMessage.notification?.title ?: data["title"] ?: ""
        val body = remoteMessage.notification?.body ?: data["body"] ?: ""
        val role = data["role"]
        val action = data["action"]

        val isCustomer = role == "customer"
        val isUrgent = !isCustomer && (
            role in listOf("rider", "delivery", "seller", "delivery_partner") ||
            action == "new_order" ||
            data["target"] in listOf("rider", "seller") ||
            title.contains("Order Available", ignoreCase = true) ||
            (title.contains("New Order", ignoreCase = true) && role != "customer")
        )

        val orderId = data["order_id"]
        val status = (data["status"] ?: action ?: "").lowercase()

        if (isUrgent) {
            handleUrgentOrder(if (title.isNotEmpty()) title else "New Order!", if (body.isNotEmpty()) body else "You have a new order waiting", data)
        } else if (!orderId.isNullOrEmpty() || isCustomer || status.isNotEmpty() || title.isNotEmpty()) {
            handleCustomerOrderTracking(if (title.isNotEmpty()) title else "Order Update", if (body.isNotEmpty()) body else "Check order status", data)
        }
    }

    private fun handleCustomerOrderTracking(title: String, body: String, data: Map<String, String>) {
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val orderId = data["order_id"]
            val status = (data["status"] ?: data["action"] ?: "").lowercase()
            val notifId = if (!orderId.isNullOrEmpty()) {
                (Math.abs(orderId.hashCode()) % 100000) + 10000
            } else {
                888
            }

            // 1. Dismiss/cancel persistent ongoing progress bar on terminal statuses or cancellations
            val isTerminalOrCancelled = status in listOf("delivered", "cancelled", "seller_rejected", "partner_rejected") ||
                data["action"] in listOf("cancel_order", "order_delivered")

            if (isTerminalOrCancelled) {
                notificationManager.cancel(notifId)
                notificationManager.cancel(888)
                if (orderId != null) notificationManager.cancel(orderId.hashCode())
            }

            val launchIntent = Intent(this, MainActivity::class.java).apply {
                this.action = "FLUTTER_NOTIFICATION_CLICK"
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP
                for ((k, v) in data) {
                    putExtra(k, v)
                }
            }

            val isOngoingProgress = status in listOf("confirmed", "preparing", "ready_for_pickup", "picked_up", "out_for_delivery")

            if (isOngoingProgress) {
                // Active fulfillment milestones: Render persistent ongoing progress notification
                val progress = when (status) {
                    "confirmed" -> 25
                    "preparing", "ready_for_pickup" -> 50
                    "picked_up" -> 75
                    "out_for_delivery" -> 90
                    else -> 35
                }

                val channelId = "order_tracking_channel"
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val channel = NotificationChannel(
                        channelId,
                        "Order Tracking",
                        NotificationManager.IMPORTANCE_HIGH
                    ).apply {
                        description = "Shows real-time order progress"
                        enableVibration(false)
                        setSound(null, null)
                        enableLights(false)
                        setShowBadge(false)
                        lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                    }
                    notificationManager.createNotificationChannel(channel)
                }

                val contentPendingIntent = PendingIntent.getActivity(
                    this,
                    notifId,
                    launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )

                val otp = data["delivery_otp"]
                val summaryText = if (!otp.isNullOrEmpty() && status == "out_for_delivery") {
                    "🔑 Delivery OTP: $otp"
                } else {
                    "$progress% completed"
                }

                val notification = NotificationCompat.Builder(this, channelId)
                    .setSmallIcon(R.mipmap.ic_launcher)
                    .setContentTitle(title)
                    .setContentText(body)
                    .setSubText(summaryText)
                    .setStyle(NotificationCompat.BigTextStyle().bigText(body).setSummaryText(summaryText))
                    .setPriority(NotificationCompat.PRIORITY_HIGH)
                    .setCategory(NotificationCompat.CATEGORY_PROGRESS)
                    .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                    .setOnlyAlertOnce(true)
                    .setShowWhen(false)
                    .setProgress(100, progress, false)
                    .setOngoing(true)
                    .setAutoCancel(false)
                    .setColor(0xFFFF5200.toInt())
                    .setContentIntent(contentPendingIntent)
                    .addAction(
                        R.mipmap.ic_launcher,
                        "Track Order 🛵",
                        contentPendingIntent
                    )
                    .build()

                notificationManager.notify(notifId, notification)
            } else {
                // Non-ongoing customer notifications (Delivered, Cancelled, Awaiting Payment, Broadcasts):
                // Render as a standard, dismissible alert notification with sound!
                val stdChannelId = "customer_notifications_channel"
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val channel = NotificationChannel(
                        stdChannelId,
                        "Customer Notifications",
                        NotificationManager.IMPORTANCE_HIGH
                    ).apply {
                        description = "Order status updates and delivery completion notices"
                        enableVibration(true)
                        enableLights(true)
                        setShowBadge(true)
                        lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                    }
                    notificationManager.createNotificationChannel(channel)
                }

                val stdNotifId = if (!orderId.isNullOrEmpty()) {
                    Math.abs(orderId.hashCode()) % 100000 + 30000
                } else {
                    (System.currentTimeMillis() % 100000).toInt()
                }

                val contentPendingIntent = PendingIntent.getActivity(
                    this,
                    stdNotifId,
                    launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )

                val notification = NotificationCompat.Builder(this, stdChannelId)
                    .setSmallIcon(R.mipmap.ic_launcher)
                    .setContentTitle(title)
                    .setContentText(body)
                    .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                    .setPriority(NotificationCompat.PRIORITY_HIGH)
                    .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                    .setAutoCancel(true)
                    .setOngoing(false)
                    .setColor(0xFFFF5200.toInt())
                    .setContentIntent(contentPendingIntent)
                    .build()

                notificationManager.notify(stdNotifId, notification)
            }
        } catch (e: Exception) {
            Log.e("EnythingFCM", "handleCustomerOrderTracking error: $e")
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
