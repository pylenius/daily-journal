package io.github.dailyjournal.journal.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Inbox
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.TaskAlt
import androidx.compose.material3.Badge
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import io.github.dailyjournal.journal.store.JournalState
import journal.core.CaptureKind
import journal.core.CheckboxLine
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.format.TextStyle
import java.time.temporal.ChronoUnit
import java.util.Locale

private val contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 96.dp)

// Days

@Composable
fun DaysScreen(state: JournalState, onOpen: (String) -> Unit) {
    if (state.entries.isEmpty() && !state.isLoading) {
        EmptyState(
            Icons.Outlined.CalendarMonth,
            "No entries yet",
            "Run /daily-journal on your Mac. Entries appear here once the folder has synced.",
        )
        return
    }
    val months = remember(state.entries) { state.entries.groupBy { it.date.take(7) }.toList() }
    val today = LocalDate.now().toString()
    LazyColumn(Modifier.fillMaxSize(), contentPadding = contentPadding) {
        if (state.placeholders.isNotEmpty()) {
            item {
                Text(
                    "Not readable yet: ${state.placeholders.joinToString()}. They appear once the sync app has downloaded them.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(4.dp),
                )
            }
        }
        for ((month, entries) in months) {
            item(key = "m$month") { SectionHeader(monthTitle(month)) }
            item(key = "c$month") {
                RowsCard(entries.size) { i ->
                    val e = entries[i]
                    val date = e.localDate
                    val open = e.openActionCount
                    ListItem(
                        headlineContent = {
                            Text(
                                date?.format(DateTimeFormatter.ofPattern("EEEE d", Locale.getDefault())) ?: e.date,
                                fontWeight = if (e.date == today) FontWeight.Bold else null,
                            )
                        },
                        supportingContent = {
                            val done = e.doneItems.size
                            Text(
                                e.doneItems.firstOrNull()?.text?.let { "$done done · $it" } ?: "$done done",
                                maxLines = 1,
                                overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                            )
                        },
                        trailingContent = {
                            if (open > 0) Badge(containerColor = MaterialTheme.colorScheme.primaryContainer, contentColor = MaterialTheme.colorScheme.onPrimaryContainer) {
                                Text("$open open", modifier = Modifier.padding(horizontal = 4.dp))
                            }
                        },
                        colors = androidx.compose.material3.ListItemDefaults.colors(containerColor = androidx.compose.ui.graphics.Color.Transparent),
                        modifier = Modifier.clickable { onOpen(e.date) },
                    )
                }
            }
        }
    }
}

private fun monthTitle(ym: String): String = runCatching {
    val m = YearMonth.parse(ym)
    "${m.month.getDisplayName(TextStyle.FULL_STANDALONE, Locale.getDefault()).replaceFirstChar { it.titlecase() }} ${m.year}"
}.getOrDefault(ym)

// Actions

@Composable
fun ActionsScreen(state: JournalState, onToggle: (CheckboxLine) -> Unit, onOpen: (String) -> Unit) {
    if (state.openActions.isEmpty()) {
        EmptyState(Icons.Outlined.TaskAlt, "Nothing open", "Every action in the journal is done.")
        return
    }
    val today = LocalDate.now()
    LazyColumn(Modifier.fillMaxSize(), contentPadding = contentPadding) {
        item {
            Text(
                "${state.openActions.size} open, across all days. Ticking one writes to the newest day it appears in.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(4.dp, 8.dp),
            )
        }
        item {
            RowsCard(state.openActions.size) { i ->
                val a = state.openActions[i]
                val since = runCatching { ChronoUnit.DAYS.between(LocalDate.parse(a.firstSeen), today) }.getOrNull()
                val subtitle = when {
                    since == null || since <= 0 -> "Today"
                    since == 1L -> "Since yesterday"
                    else -> "Since ${shortDate(a.firstSeen)} · $since days"
                }
                ActionRow(a.latest, onToggle = { onToggle(a.latest) }, subtitle = subtitle, onClick = { onOpen(a.latest.date) }, hideCarriedFrom = true)
            }
        }
    }
}

fun shortDate(date: String): String = runCatching {
    LocalDate.parse(date).format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM))
}.getOrDefault(date)

// Search

@Composable
fun SearchScreen(state: JournalState, onOpen: (String) -> Unit) {
    var query by rememberSaveable { mutableStateOf("") }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { if (query.isEmpty()) runCatching { focus.requestFocus() } }
    val hits = remember(query, state.index) { state.index.search(query) }
    val colors = MaterialTheme.colorScheme
    Column(Modifier.fillMaxSize()) {
        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            placeholder = { Text("Search all entries") },
            leadingIcon = { Icon(Icons.Outlined.Search, null) },
            trailingIcon = { if (query.isNotEmpty()) IconButton(onClick = { query = "" }) { Icon(Icons.Outlined.Close, "Clear") } },
            singleLine = true,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp).focusRequester(focus),
        )
        when {
            query.isBlank() -> EmptyState(Icons.Outlined.Search, "Search the journal", "Every word must appear on the same line. Case and accents are ignored.")
            hits.isEmpty() -> EmptyState(Icons.Outlined.Search, "No matches", "Nothing in ${state.entries.size} entries matches “$query”.")
            else -> LazyColumn(contentPadding = contentPadding) {
                items(hits, key = { it.id }) { hit ->
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .clickable { onOpen(hit.date) }
                            .padding(horizontal = 4.dp, vertical = 10.dp),
                        verticalArrangement = Arrangement.spacedBy(2.dp),
                    ) {
                        Text(
                            shortDate(hit.date) + (hit.section.title.takeIf { it.isNotEmpty() }?.let { " · $it" } ?: ""),
                            style = MaterialTheme.typography.labelMedium,
                            color = colors.primary,
                        )
                        val text = hit.lineText.trim()
                        Text(
                            buildAnnotatedString {
                                append(text)
                                for (r in journal.core.SearchIndex.matchRanges(text, query)) {
                                    addStyle(SpanStyle(background = colors.tertiaryContainer, color = colors.onTertiaryContainer), r.first, r.last + 1)
                                }
                            },
                            style = MaterialTheme.typography.bodyMedium,
                            maxLines = 4,
                        )
                    }
                    HorizontalDivider(color = colors.outlineVariant.copy(alpha = 0.5f))
                }
                if (hits.size >= 200) item {
                    Text("Showing the first 200 matches.", style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(8.dp))
                }
            }
        }
    }
}

// Inbox

@Composable
fun InboxScreen(state: JournalState) {
    if (state.inbox.isEmpty()) {
        EmptyState(
            Icons.Outlined.Inbox,
            "Inbox is empty",
            "Tap + to jot down a note or an action. The next journal run on the Mac folds it into the day's entry.",
        )
        return
    }
    val colors = MaterialTheme.colorScheme
    val formatter = remember { DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT) }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = contentPadding, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        item {
            Text(
                "${state.inbox.size} waiting for the next journal run.",
                style = MaterialTheme.typography.bodySmall,
                color = colors.onSurfaceVariant,
                modifier = Modifier.padding(4.dp, 8.dp),
            )
        }
        items(state.inbox, key = { it.id }) { c ->
            PlainCard {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    val action = c.kind == CaptureKind.Action
                    Text(
                        if (action) "Action" else "Note",
                        style = MaterialTheme.typography.labelMedium,
                        color = if (action) colors.onPrimaryContainer else colors.onSecondaryContainer,
                        modifier = Modifier
                            .background(if (action) colors.primaryContainer else colors.secondaryContainer, MaterialTheme.shapes.small)
                            .padding(horizontal = 8.dp, vertical = 2.dp),
                    )
                    Text(
                        listOfNotNull(c.created?.atZoneSameInstant(java.time.ZoneId.systemDefault())?.format(formatter), c.device).joinToString(" · "),
                        style = MaterialTheme.typography.labelMedium,
                        color = colors.onSurfaceVariant,
                    )
                }
                MarkdownBlocks(c.body, modifier = Modifier.padding(top = 8.dp))
            }
        }
    }
}
