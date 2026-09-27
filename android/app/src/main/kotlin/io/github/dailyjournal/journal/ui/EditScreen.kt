package io.github.dailyjournal.journal.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.foundation.text.KeyboardOptions
import io.github.dailyjournal.journal.store.JournalState
import io.github.dailyjournal.journal.store.JournalStore
import journal.core.ChangedSinceLoadException
import kotlinx.coroutines.launch

/** Raw Markdown editor with a stale-file guard: if the Mac rewrote the entry meanwhile, you choose what happens. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EditScreen(state: JournalState, date: String, store: JournalStore, onClose: () -> Unit) {
    val entry = state.entry(date)
    // Captured once when the editor opens; survives rotation.
    val loadedHash = rememberSaveable(date) { state.hashes[date] ?: "" }
    val original = rememberSaveable(date) { entry?.fullText?.replace("\r\n", "\n") ?: "" }
    var text by rememberSaveable(date) { mutableStateOf(original) }
    var conflict by remember { mutableStateOf(false) }
    var confirmClose by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val copy = rememberCopy()
    val dirty = text != original
    val stale = loadedHash.isNotEmpty() && state.hashes[date] != null && state.hashes[date] != loadedHash

    fun save(force: Boolean) {
        val newline = state.entry(date)?.newline ?: "\n"
        scope.launch {
            try {
                store.save(date, text.replace("\n", newline), if (force) null else loadedHash.ifEmpty { null })
                onClose()
            } catch (_: ChangedSinceLoadException) {
                conflict = true
            } catch (e: Exception) {
                error = "Could not save: ${e.message ?: e}"
            }
        }
    }

    BackHandler { if (dirty) confirmClose = true else onClose() }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Edit ${shortDate(date)}") },
                navigationIcon = {
                    IconButton(onClick = { if (dirty) confirmClose = true else onClose() }) { Icon(Icons.Outlined.Close, "Close") }
                },
                actions = { TextButton(onClick = { save(force = false) }, enabled = dirty) { Text("Save") } },
            )
        },
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().imePadding()) {
            val banner = error ?: if (stale) "This entry changed on another device while you were editing." else null
            if (banner != null) {
                ListItem(
                    headlineContent = { Text(banner, style = MaterialTheme.typography.bodyMedium) },
                    leadingContent = { Icon(Icons.Outlined.Warning, null) },
                    colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.errorContainer),
                )
            }
            TextField(
                value = text,
                onValueChange = { text = it },
                textStyle = TextStyle(fontFamily = FontFamily.Monospace, fontSize = MaterialTheme.typography.bodyMedium.fontSize),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences, autoCorrectEnabled = false),
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = Color.Transparent,
                    unfocusedContainerColor = Color.Transparent,
                    focusedIndicatorColor = Color.Transparent,
                    unfocusedIndicatorColor = Color.Transparent,
                ),
                modifier = Modifier.fillMaxWidth().weight(1f),
            )
        }
    }

    if (conflict) {
        AlertDialog(
            onDismissRequest = { conflict = false },
            title = { Text("The entry changed on another device") },
            text = { Text("Overwrite it with your version, or copy your text to the clipboard and discard it?") },
            confirmButton = { TextButton(onClick = { conflict = false; save(force = true) }) { Text("Overwrite") } },
            dismissButton = {
                Column {
                    TextButton(onClick = {
                        conflict = false
                        copy(text)
                        onClose()
                    }) { Text("Copy and discard") }
                    TextButton(onClick = { conflict = false }) { Text("Keep editing") }
                }
            },
        )
    }
    if (confirmClose) {
        AlertDialog(
            onDismissRequest = { confirmClose = false },
            title = { Text("Save your changes?") },
            confirmButton = { TextButton(onClick = { confirmClose = false; save(force = false) }) { Text("Save") } },
            dismissButton = {
                Column {
                    TextButton(onClick = { confirmClose = false; onClose() }) { Text("Discard") }
                    TextButton(onClick = { confirmClose = false }) { Text("Keep editing") }
                }
            },
        )
    }
}
