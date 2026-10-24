package de.eliasrosch.casa_pazza

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.glance.action.Action
import androidx.glance.appwidget.action.actionStartActivity
import es.antonborri.home_widget.HomeWidgetLaunchIntent

/**
 * Invisible trampoline for widget buttons and app shortcuts.
 *
 * It forwards the casapazza:// URI to [MainActivity] as a home_widget launch
 * and stamps it with the click time. Android may later recreate MainActivity
 * with that same intent (e.g. after the process was killed); MainActivity
 * recognizes the old stamp and starts normally instead of repeating the action.
 */
class LaunchActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        startActivity(
            Intent(this, MainActivity::class.java)
                .setAction(HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION)
                .setData(intent?.data)
                .putExtra(EXTRA_LAUNCHED_AT, System.currentTimeMillis())
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        finish()
    }

    companion object {
        const val EXTRA_LAUNCHED_AT = "de.eliasrosch.casa_pazza.LAUNCHED_AT"

        /** Launch intents older than this are replays, not user actions. */
        const val MAX_LAUNCH_AGE_MS = 30_000L
    }
}

/** Glance action that opens the app at [uri] via [LaunchActivity]. */
fun actionOpenApp(context: Context, uri: String): Action =
    actionStartActivity(Intent(context, LaunchActivity::class.java).setData(Uri.parse(uri)))
