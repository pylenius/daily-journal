package io.github.dailyjournal.journal.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.ChevronLeft
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.ExpandLess
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import io.github.dailyjournal.journal.store.JournalState
import io.github.dailyjournal.journal.store.JournalStore
import journal.core.JournalEntry
import journal.core.SectionKind
import journal.core.SectionType

/** One day: Done, Actions, Carried over as native rows; other sections and Details rendered as Markdown. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EntryScreen(
    state: JournalState,
    date: String,
    store: JournalStore,
    snackbar: SnackbarHostState,
    onBack: () -> Unit,
    onOpen: (String) -> Unit,
    onEdit: () -> Unit,
) {
    val entry = state.entry(date)
    val index = state.entries.indexOfFirst { it.date == date }
    val older = state.entries.getOrNull(index + 1)?.date
    val newer = if (index > 0) state.entries[index - 1].date else null
    val scroll = TopAppBarDefaults.pinnedScrollBehavior()
    Scaffold(
        modifier = Modifier.nestedScroll(scroll.nestedScrollConnection),
        snackbarHost = { SnackbarHost(snackbar) },
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(entry?.localDate?.let { shortDate(date) } ?: date, style = MaterialTheme.typography.titleMedium)
                        entry?.localDate?.let {
                            Text(
                                it.dayOfWeek.getDisplayName(java.time.format.TextStyle.FULL, java.util.Locale.getDefault()),
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, "Back") } },
                actions = {
                    IconButton(onClick = { older?.let(onOpen) }, enabled = older != null) { Icon(Icons.Outlined.ChevronLeft, "Previous day") }
                    IconButton(onClick = { newer?.let(onOpen) }, enabled = newer != null) { Icon(Icons.Outlined.ChevronRight, "Next day") }
                    IconButton(onClick = onEdit, enabled = entry != null) { Icon(Icons.Outlined.Edit, "Edit Markdown") }
                },
                scrollBehavior = scroll,
            )
        },
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = state.isLoading,
            onRefresh = store::reload,
            modifier = Modifier.padding(padding).fillMaxSize(),
        ) {
            if (entry == null) {
                EmptyState(Icons.Outlined.Edit, "Entry not found", "$date is not in the journal folder (any more).")
            } else {
                EntryContent(entry, store)
            }
        }
    }
}

@Composable
private fun EntryContent(entry: JournalEntry, store: JournalStore) {
    var detailsExpanded by rememberSaveable { mutableStateOf(false) }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 48.dp)) {
        entry.sectionOf(SectionKind.Preamble)?.let { s ->
            item { PlainCard { MarkdownBlocks(entry.bodyText(s), onToggle = { toggle(entry, store, s.bodyStart + it) }) } }
        }

        if (entry.doneItems.isNotEmpty()) {
            item { SectionHeader("Done") }
            item {
                RowsCard(entry.doneItems.size) { i ->
                    val d = entry.doneItems[i]
                    DoneRow(d, onToggleHighlight = { store.toggleHighlight(d) }, onRemove = { store.remove(d) })
                }
            }
        } else entry.textOf(SectionKind.Done)?.takeIf { it.isNotBlank() }?.let { body ->
            item { SectionHeader("Done") }
            item { PlainCard { MarkdownBlocks(body) } }
        }

        for (kind in listOf(SectionKind.Actions, SectionKind.CarriedOver)) {
            val items = entry.checkboxes.filter { it.section == kind }
            val body = entry.textOf(kind)?.trim().orEmpty()
            if (items.isEmpty() && body.isEmpty()) continue
            item { SectionHeader(kind.title) }
            item {
                if (items.isNotEmpty()) RowsCard(items.size) { i -> ActionRow(items[i], onToggle = { store.toggle(items[i]) }) }
                else PlainCard { Text(inlineMarkdown(body, MaterialTheme.colorScheme.primary), color = MaterialTheme.colorScheme.onSurfaceVariant) }
            }
        }

        for (s in entry.sections.filter { it.kind.type == SectionType.Other }) {
            item { SectionHeader(s.heading) }
            item { PlainCard { MarkdownBlocks(entry.bodyText(s), onToggle = { toggle(entry, store, s.bodyStart + it) }) } }
        }

        entry.sectionOf(SectionKind.Details)?.let { details ->
            item {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .padding(top = 12.dp)
                        .clickable { detailsExpanded = !detailsExpanded }
                        .padding(vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(
                        "Details",
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.primary,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.padding(start = 4.dp),
                    )
                    Icon(
                        if (detailsExpanded) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore,
                        if (detailsExpanded) "Collapse" else "Expand",
                        tint = MaterialTheme.colorScheme.primary,
                    )
                }
            }
            item {
                AnimatedVisibility(detailsExpanded) {
                    PlainCard {
                        MarkdownBlocks(entry.bodyText(details), onToggle = { toggle(entry, store, details.bodyStart + it) })
                    }
                }
            }
        }
    }
}

private fun toggle(entry: JournalEntry, store: JournalStore, line: Int) {
    entry.checkboxes.firstOrNull { it.line == line }?.let(store::toggle)
}
