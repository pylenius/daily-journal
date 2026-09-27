package io.github.dailyjournal.journal.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import journal.core.CaptureKind

/** Quick capture: a note or an action, written as a new file in `inbox/`. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CaptureSheet(initialText: String, initialKind: CaptureKind, onSave: (CaptureKind, String) -> Unit, onDismiss: () -> Unit) {
    var kind by rememberSaveable { mutableStateOf(initialKind) }
    var text by rememberSaveable { mutableStateOf(initialText) }
    val focus = remember { FocusRequester() }
    val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheet) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 16.dp).imePadding(),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("Add to Journal", style = MaterialTheme.typography.titleLarge)
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                CaptureKind.entries.forEachIndexed { i, k ->
                    SegmentedButton(
                        selected = kind == k,
                        onClick = { kind = k },
                        shape = SegmentedButtonDefaults.itemShape(i, CaptureKind.entries.size),
                    ) { Text(if (k == CaptureKind.Action) "Action" else "Note") }
                }
            }
            OutlinedTextField(
                value = text,
                onValueChange = { text = it },
                placeholder = { Text(if (kind == CaptureKind.Action) "Something to do…" else "Something to remember…") },
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                modifier = Modifier.fillMaxWidth().heightIn(min = 120.dp).focusRequester(focus),
            )
            Text(
                "Saved to the inbox folder. The next journal run on the Mac " +
                    if (kind == CaptureKind.Action) "adds it to Actions." else "folds it into the entry.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, androidx.compose.ui.Alignment.End)) {
                TextButton(onClick = onDismiss) { Text("Cancel") }
                Button(onClick = { onSave(kind, text) }, enabled = text.isNotBlank()) { Text("Add") }
            }
        }
    }
}
