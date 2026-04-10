package app.cool.mobile.momo_sms

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class MomoSmsBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) {
            return
        }
        val prefs = MomoSmsPrefs.getInstance(context)
        if (!prefs.hasSyncConfiguration()) {
            return
        }
        MomoSmsSyncWorker.enqueue(context)
    }
}
