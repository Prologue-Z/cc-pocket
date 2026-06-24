package dev.ccpocket.app.push

import android.app.Service
import android.content.Intent
import android.os.IBinder

/** No-op (Firebase disabled — dev branch). */
class CcPocketMessagingService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null
}
