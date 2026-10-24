package de.eliasrosch.casa_pazza

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.os.Build
import android.os.Bundle
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Widget and shortcut launches come through LaunchActivity with a
        // click time. Android replays a task's original intent when it
        // recreates the activity (e.g. after the process was killed); such an
        // old or unstamped launch must not repeat its action ("Neue Aufgabe").
        if (intent?.action == HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION && isStale(intent)) {
            intent = Intent(this, MainActivity::class.java).setAction(Intent.ACTION_MAIN)
        }
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    private fun isStale(intent: Intent): Boolean {
        val launchedAt = intent.getLongExtra(LaunchActivity.EXTRA_LAUNCHED_AT, 0L)
        return System.currentTimeMillis() - launchedAt > LaunchActivity.MAX_LAUNCH_AGE_MS
    }

    /** Channel for assignment pushes (referenced in AndroidManifest.xml). */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            "assignments",
            getString(R.string.channel_assignments),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply { description = getString(R.string.channel_assignments_description) }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }
}
