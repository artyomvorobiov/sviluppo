package app.kvartet.reminders

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import app.kvartet.Kvartet
import app.kvartet.MainActivity
import app.kvartet.R
import app.kvartet.data.Format
import java.time.Duration
import java.time.LocalDate
import java.time.ZonedDateTime
import java.util.concurrent.TimeUnit

/** Ежедневное напоминание с темой дня. */
object Reminders {
    private const val CHANNEL = "daily"
    private const val WORK = "daily-reminder"

    fun createChannel(context: Context) {
        val channel = NotificationChannel(CHANNEL, context.getString(R.string.reminder_channel), NotificationManager.IMPORTANCE_DEFAULT)
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    fun canNotify(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    fun reschedule(context: Context) {
        val settings = Kvartet.settings.state.value
        val work = WorkManager.getInstance(context)
        if (!settings.reminderEnabled) {
            work.cancelUniqueWork(WORK)
            return
        }
        val now = ZonedDateTime.now()
        var next = now.withHour(settings.reminderHour).withMinute(settings.reminderMinute).withSecond(0).withNano(0)
        if (!next.isAfter(now)) next = next.plusDays(1)
        val request = OneTimeWorkRequestBuilder<ReminderWorker>()
            .setInitialDelay(Duration.between(now, next).toMillis(), TimeUnit.MILLISECONDS)
            .build()
        work.enqueueUniqueWork(WORK, ExistingWorkPolicy.REPLACE, request)
    }

    fun show(context: Context) {
        if (!canNotify(context)) return
        val issue = Kvartet.issueFor(LocalDate.now())
        val items = Kvartet.visibleItems(issue)
        val body = items.firstOrNull()?.let { first ->
            val lead = "${first.kind.title} «${first.title}»"
            val rest = items.size - 1
            if (rest > 0) "$lead и ещё ${Format.count(rest, "открытие", "открытия", "открытий")}." else "$lead."
        } ?: "Новый выпуск уже ждёт."
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("kvartet://today"), context, MainActivity::class.java)
        val pending = PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("Тема дня — «${issue.theme}»")
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(pending)
            .setAutoCancel(true)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(1, notification)
        } catch (e: SecurityException) {
            // Разрешение на уведомления отозвано.
        }
    }
}

class ReminderWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        Kvartet.init(applicationContext)
        Reminders.show(applicationContext)
        Reminders.reschedule(applicationContext)
        return Result.success()
    }
}
