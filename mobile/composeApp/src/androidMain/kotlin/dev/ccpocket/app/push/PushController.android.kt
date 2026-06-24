package dev.ccpocket.app.push

/** No-op (Firebase disabled — dev branch). */
actual object PushController {
    actual fun start(onToken: (PushToken) -> Unit) {}
}
