package de.eliasrosch.casa_pazza

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
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
