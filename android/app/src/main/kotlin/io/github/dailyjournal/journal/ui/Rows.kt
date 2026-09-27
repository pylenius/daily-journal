package io.github.dailyjournal.journal.ui

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.OpenInBrowser
import androidx.compose.material.icons.outlined.Star
import androidx.compose.material.icons.outlined.StarOutline
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import journal.core.CheckboxLine
import journal.core.DoneItem
import journal.core.ReferenceKind

/** Copies plain text to the clipboard; Android 13+ shows its own confirmation. */
@Composable
fun rememberCopy(): (String) -> Unit {
    val context = LocalContext.current
    return remember(context) {
        { text ->
            context.getSystemService(android.content.ClipboardManager::class.java)
                .setPrimaryClip(android.content.ClipData.newPlainText("Journal", text))
        }
    }
}

@Composable
fun SectionHeader(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        fontWeight = FontWeight.SemiBold,
        modifier = modifier.padding(start = 4.dp, top = 20.dp, bottom = 8.dp),
    )
}

/** A card holding rows separated by thin dividers. */
@Composable
fun RowsCard(count: Int, row: @Composable ColumnScope.(Int) -> Unit) {
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
        modifier = Modifier.fillMaxWidth(),
    ) {
        for (i in 0 until count) {
            if (i > 0) HorizontalDivider(Modifier.padding(start = 16.dp), color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
            row(i)
        }
    }
}

@Composable
fun PlainCard(content: @Composable ColumnScope.() -> Unit) {
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(16.dp), content = content)
    }
}

/**
 * One action: the box toggles it, links in the text and reference open, a long press offers copy and open.
 * [subtitle] shows where it came from on the Actions tab; [onClick] opens its day there, and [hideCarriedFrom]
 * drops the `(from YYYY-MM-DD)` note that the subtitle already covers.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ActionRow(
    item: CheckboxLine,
    onToggle: () -> Unit,
    subtitle: String? = null,
    onClick: (() -> Unit)? = null,
    hideCarriedFrom: Boolean = false,
) {
    val colors = MaterialTheme.colorScheme
    val copy = rememberCopy()
    val uriHandler = LocalUriHandler.current
    val haptics = LocalHapticFeedback.current
    var menu by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier
                .fillMaxWidth()
                .combinedClickable(
                    onClick = { onClick?.invoke() ?: onToggle() },
                    onLongClick = { haptics.performHapticFeedback(HapticFeedbackType.LongPress); menu = true },
                    onClickLabel = if (onClick != null) "Open day" else if (item.isChecked) "Mark open" else "Mark done",
                )
                .padding(end = 16.dp, top = 4.dp, bottom = 10.dp),
            verticalAlignment = Alignment.Top,
        ) {
            Checkbox(checked = item.isChecked, onCheckedChange = { onToggle() }, modifier = Modifier.padding(start = 4.dp))
            Column(Modifier.padding(top = 12.dp).weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                val text = if (hideCarriedFrom) item.text.replace(CARRIED_FROM, "") else item.text
                Text(
                    inlineMarkdown(text, colors.primary),
                    style = MaterialTheme.typography.bodyLarge,
                    color = if (item.isChecked) colors.onSurfaceVariant else Color.Unspecified,
                    textDecoration = if (item.isChecked) TextDecoration.LineThrough else null,
                )
                for (line in item.continuation) {
                    Text(inlineMarkdown(line.trim(), colors.primary), style = MaterialTheme.typography.bodyMedium, color = colors.onSurfaceVariant)
                }
                item.reference?.takeIf { it.isNotEmpty() }?.let { ref ->
                    val label = if (item.referenceKind == ReferenceKind.Done) "done: " else "source: "
                    Text(
                        inlineMarkdown(label + ref, colors.primary),
                        style = MaterialTheme.typography.bodySmall,
                        color = colors.onSurfaceVariant,
                        maxLines = 3,
                    )
                }
                subtitle?.let { Text(it, style = MaterialTheme.typography.labelMedium, color = colors.tertiary) }
            }
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(
                text = { Text(if (item.isChecked) "Mark open" else "Mark done") },
                onClick = { menu = false; onToggle() },
            )
            DropdownMenuItem(
                text = { Text("Copy text") },
                leadingIcon = { Icon(Icons.Outlined.ContentCopy, null) },
                onClick = { menu = false; copy(item.text) },
            )
            item.reference?.let { ref ->
                DropdownMenuItem(
                    text = { Text("Copy reference") },
                    leadingIcon = { Icon(Icons.Outlined.ContentCopy, null) },
                    onClick = { menu = false; copy(ref) },
                )
            }
            for (url in item.urls.take(3)) {
                DropdownMenuItem(
                    text = { Text("Open ${url.host ?: url}", maxLines = 1) },
                    leadingIcon = { Icon(Icons.Outlined.OpenInBrowser, null) },
                    onClick = { menu = false; uriHandler.openUri(url.toString()) },
                )
            }
        }
    }
}

private val CARRIED_FROM = Regex("""\s*\(from \d{4}-\d{2}-\d{2}\)\s*$""")

/** One Done bullet. Long press: highlight / remove / copy. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun DoneRow(item: DoneItem, onToggleHighlight: () -> Unit, onRemove: () -> Unit) {
    val colors = MaterialTheme.colorScheme
    val copy = rememberCopy()
    val haptics = LocalHapticFeedback.current
    var menu by remember { mutableStateOf(false) }
    var confirmRemove by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier
                .fillMaxWidth()
                .combinedClickable(
                    onClick = {},
                    onLongClick = { haptics.performHapticFeedback(HapticFeedbackType.LongPress); menu = true },
                    onLongClickLabel = "More",
                )
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.Top,
        ) {
            if (item.isHighlighted) {
                Icon(Icons.Outlined.Star, contentDescription = "Highlighted", tint = colors.tertiary, modifier = Modifier.padding(top = 2.dp).size(16.dp))
            } else {
                Surface(shape = CircleShape, color = colors.primary, modifier = Modifier.padding(top = 8.dp, start = 5.dp, end = 5.dp).size(6.dp)) {}
            }
            Text(
                inlineMarkdown(item.text, colors.primary),
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = if (item.isHighlighted) FontWeight.SemiBold else null,
                modifier = Modifier.padding(start = 12.dp).weight(1f),
            )
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(
                text = { Text(if (item.isHighlighted) "Remove highlight" else "Highlight") },
                leadingIcon = { Icon(if (item.isHighlighted) Icons.Outlined.StarOutline else Icons.Outlined.Star, null) },
                onClick = { menu = false; onToggleHighlight() },
            )
            DropdownMenuItem(
                text = { Text("Copy") },
                leadingIcon = { Icon(Icons.Outlined.ContentCopy, null) },
                onClick = { menu = false; copy(item.text) },
            )
            DropdownMenuItem(
                text = { Text("Remove") },
                leadingIcon = { Icon(Icons.Outlined.Delete, null) },
                onClick = { menu = false; confirmRemove = true },
            )
        }
    }
    if (confirmRemove) {
        AlertDialog(
            onDismissRequest = { confirmRemove = false },
            title = { Text("Remove this item?") },
            text = { Text(item.text, maxLines = 4) },
            confirmButton = { TextButton(onClick = { confirmRemove = false; onRemove() }) { Text("Remove") } },
            dismissButton = { TextButton(onClick = { confirmRemove = false }) { Text("Cancel") } },
        )
    }
}

@Composable
fun EmptyState(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, text: String, modifier: Modifier = Modifier) {
    Column(
        modifier.fillMaxWidth().padding(horizontal = 32.dp, vertical = 64.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(icon, null, tint = MaterialTheme.colorScheme.outline, modifier = Modifier.size(48.dp))
        Text(title, style = MaterialTheme.typography.titleMedium)
        Text(text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
    }
}
