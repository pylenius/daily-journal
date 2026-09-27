package io.github.dailyjournal.journal

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import io.github.dailyjournal.journal.store.JournalStore
import io.github.dailyjournal.journal.ui.CaptureRequest
import io.github.dailyjournal.journal.ui.JournalApp
import io.github.dailyjournal.journal.ui.JournalTheme
import journal.core.CaptureKind

class MainActivity : ComponentActivity() {
    private val store: JournalStore by viewModels()
    private var capture by mutableStateOf<CaptureRequest?>(null)
    private var openDate by mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) {
            // Debug builds take `-e journalFolder <path>` so the emulator can skip the folder picker.
            val debugFolder = intent.getStringExtra("journalFolder")?.takeIf { BuildConfig.DEBUG }
            if (debugFolder != null) store.useDirectory(debugFolder) else store.restore()
            handle(intent)
        }
        publishShortcut()
        setContent {
            JournalTheme {
                JournalApp(
                    store = store,
                    capture = capture,
                    onCaptureConsumed = { capture = null },
                    openDate = openDate,
                    onOpenDateConsumed = { openDate = null },
                )
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    /** Text shared from another app, the "New capture" shortcut, or `-e openDate YYYY-MM-DD`. */
    private fun handle(intent: Intent) {
        when (intent.action) {
            Intent.ACTION_SEND -> {
                val text = listOfNotNull(
                    intent.getStringExtra(Intent.EXTRA_SUBJECT),
                    intent.getStringExtra(Intent.EXTRA_TEXT),
                ).distinct().joinToString("\n")
                capture = CaptureRequest(text = text, kind = CaptureKind.Note)
            }
            ACTION_CAPTURE -> capture = CaptureRequest()
        }
        intent.getStringExtra("openDate")?.let { openDate = it }
    }

    private fun publishShortcut() {
        val shortcut = ShortcutInfoCompat.Builder(this, "capture")
            .setShortLabel(getString(R.string.shortcut_capture_short))
            .setLongLabel(getString(R.string.shortcut_capture_long))
            .setIcon(IconCompat.createWithResource(this, R.drawable.ic_shortcut_capture))
            .setIntent(Intent(ACTION_CAPTURE, null, this, MainActivity::class.java))
            .build()
        runCatching { ShortcutManagerCompat.setDynamicShortcuts(this, listOf(shortcut)) }
    }

    companion object {
        const val ACTION_CAPTURE = "io.github.dailyjournal.journal.CAPTURE"
    }
}
