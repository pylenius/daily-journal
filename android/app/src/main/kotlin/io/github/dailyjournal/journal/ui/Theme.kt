package io.github.dailyjournal.journal.ui

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

// The icon's blue, for devices without dynamic color.
private val Light = lightColorScheme(
    primary = Color(0xFF2B5BD7),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFDCE4FF),
    onPrimaryContainer = Color(0xFF0F2E7A),
    tertiary = Color(0xFF1F8A3E),
)
private val Dark = darkColorScheme(
    primary = Color(0xFFB4C5FF),
    onPrimary = Color(0xFF0F2E7A),
    primaryContainer = Color(0xFF1E4BC0),
    onPrimaryContainer = Color(0xFFDCE4FF),
    tertiary = Color(0xFF6FDC8C),
)

@Composable
fun JournalTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val scheme = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        dark -> Dark
        else -> Light
    }
    MaterialTheme(colorScheme = scheme, content = content)
}
