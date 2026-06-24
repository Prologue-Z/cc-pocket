package dev.ccpocket.app.telemetry

import android.content.Context

/** No-op (Firebase disabled — dev branch). Call once from MainActivity. */
fun initTelemetry(context: Context) {}
actual object Telemetry {
    actual fun setEnabled(enabled: Boolean) {}
    actual fun isEnabled(): Boolean = false
    actual fun track(event: TelEvent, params: Map<TelKey, Any>) {}
    actual fun recordError(message: String, phase: String?) {}
}
