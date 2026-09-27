package io.github.dailyjournal.journal.ui

import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Inbox
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.TaskAlt
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.Inbox
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.TaskAlt
import androidx.compose.material.icons.outlined.Today
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Badge
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import io.github.dailyjournal.journal.store.FolderState
import io.github.dailyjournal.journal.store.JournalStore
import journal.core.CaptureKind
import kotlinx.coroutines.delay
import java.time.LocalDate

/** A request to open the capture sheet, from the + button, the share sheet or the launcher shortcut. */
data class CaptureRequest(val text: String = "", val kind: CaptureKind = CaptureKind.Note)

private enum class Tab(val title: String, val icon: ImageVector, val selectedIcon: ImageVector) {
    Days("Days", Icons.Outlined.CalendarMonth, Icons.Filled.CalendarMonth),
    Actions("Actions", Icons.Outlined.TaskAlt, Icons.Filled.TaskAlt),
    Search("Search", Icons.Outlined.Search, Icons.Filled.Search),
    Inbox("Inbox", Icons.Outlined.Inbox, Icons.Filled.Inbox),
}

/** How often the folder is checked for changes from the Mac while the app is in front. */
private const val POLL_MILLIS = 15_000L

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun JournalApp(
    store: JournalStore,
    capture: CaptureRequest?,
    onCaptureConsumed: () -> Unit,
    openDate: String?,
    onOpenDateConsumed: () -> Unit,
) {
    val state by store.state.collectAsStateWithLifecycle()
    val snackbar = remember { SnackbarHostState() }
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var entryDate by rememberSaveable { mutableStateOf<String?>(null) }
    var editDate by rememberSaveable { mutableStateOf<String?>(null) }
    var captureRequest by remember { mutableStateOf<CaptureRequest?>(null) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri: Uri? ->
        uri?.let(store::chooseFolder)
    }

    LaunchedEffect(Unit) { store.messages.collect { snackbar.showSnackbar(it) } }
    LaunchedEffect(capture) { if (capture != null) { captureRequest = capture; onCaptureConsumed() } }
    LaunchedEffect(openDate) { if (openDate != null) { entryDate = openDate; onOpenDateConsumed() } }

    // There is no file watching through SAF: check on resume and every few seconds while visible.
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            while (true) {
                store.reloadIfChanged()
                delay(POLL_MILLIS)
            }
        }
    }

    when (state.folderState) {
        FolderState.NotChosen -> SetupScreen(onChoose = { picker.launch(null) })
        FolderState.Unreachable -> SetupScreen(
            message = state.unreachableMessage,
            onChoose = { picker.launch(null) },
            onRetry = store::reload,
        )
        FolderState.Ready -> {
            val edit = editDate
            val entry = entryDate
            when {
                edit != null -> EditScreen(state, edit, store, onClose = { editDate = null })
                entry != null -> {
                    BackHandler { entryDate = null }
                    EntryScreen(
                        state, entry, store, snackbar,
                        onBack = { entryDate = null },
                        onOpen = { entryDate = it },
                        onEdit = { editDate = entry },
                    )
                }
                else -> {
                    BackHandler(enabled = tab != 0) { tab = 0 }
                    Scaffold(
                        snackbarHost = { SnackbarHost(snackbar) },
                        topBar = {
                            TopAppBar(
                                title = {
                                    Column {
                                        Text(Tab.entries[tab].title)
                                        state.folderName?.let {
                                            Text(it, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                        }
                                    }
                                },
                                actions = {
                                    val today = LocalDate.now().toString()
                                    val latest = state.entries.firstOrNull()?.date
                                    IconButton(onClick = { entryDate = state.entry(today)?.date ?: latest }, enabled = latest != null) {
                                        Icon(Icons.Outlined.Today, "Latest entry")
                                    }
                                    OverflowMenu(
                                        onReload = store::reload,
                                        onChooseFolder = { picker.launch(null) },
                                        onForget = if (store.canForget) store::forgetFolder else null,
                                    )
                                },
                            )
                        },
                        bottomBar = {
                            NavigationBar {
                                Tab.entries.forEachIndexed { i, t ->
                                    NavigationBarItem(
                                        selected = tab == i,
                                        onClick = { tab = i },
                                        icon = {
                                            val count = when (t) {
                                                Tab.Actions -> state.openActions.size
                                                Tab.Inbox -> state.inbox.size
                                                else -> 0
                                            }
                                            BadgedBox(badge = { if (count > 0) Badge { Text("$count") } }) {
                                                Icon(if (tab == i) t.selectedIcon else t.icon, null)
                                            }
                                        },
                                        label = { Text(t.title) },
                                    )
                                }
                            }
                        },
                        floatingActionButton = {
                            if (Tab.entries[tab] != Tab.Search) {
                                FloatingActionButton(onClick = {
                                    captureRequest = CaptureRequest(kind = if (Tab.entries[tab] == Tab.Actions) CaptureKind.Action else CaptureKind.Note)
                                }) { Icon(Icons.Outlined.Add, "Add to Journal") }
                            }
                        },
                    ) { padding ->
                        PullToRefreshBox(
                            isRefreshing = state.isLoading,
                            onRefresh = store::reload,
                            modifier = Modifier.padding(padding).fillMaxSize(),
                        ) {
                            when (Tab.entries[tab]) {
                                Tab.Days -> DaysScreen(state, onOpen = { entryDate = it })
                                Tab.Actions -> ActionsScreen(state, onToggle = store::toggle, onOpen = { entryDate = it })
                                Tab.Search -> SearchScreen(state, onOpen = { entryDate = it })
                                Tab.Inbox -> InboxScreen(state)
                            }
                        }
                    }
                }
            }
        }
    }

    captureRequest?.let { req ->
        if (state.folderState == FolderState.Ready) {
            CaptureSheet(
                initialText = req.text,
                initialKind = req.kind,
                onSave = { kind, text -> store.capture(kind, text); captureRequest = null },
                onDismiss = { captureRequest = null },
            )
        }
    }
}

@Composable
private fun OverflowMenu(onReload: () -> Unit, onChooseFolder: () -> Unit, onForget: (() -> Unit)?) {
    var open by remember { mutableStateOf(false) }
    IconButton(onClick = { open = true }) { Icon(Icons.Outlined.MoreVert, "More") }
    DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
        DropdownMenuItem(text = { Text("Reload") }, onClick = { open = false; onReload() })
        DropdownMenuItem(text = { Text("Choose journal folder…") }, onClick = { open = false; onChooseFolder() })
        onForget?.let { forget ->
            DropdownMenuItem(text = { Text("Forget folder") }, onClick = { open = false; forget() })
        }
    }
}

@Composable
fun SetupScreen(message: String? = null, onChoose: () -> Unit, onRetry: (() -> Unit)? = null) {
    Scaffold { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState()).padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
        ) {
            Icon(Icons.Outlined.FolderOpen, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(8.dp))
            Text(if (message == null) "Choose your journal folder" else "Journal folder not reachable", style = MaterialTheme.typography.headlineSmall, textAlign = TextAlign.Center)
            Text(
                message ?: ("Pick the folder that holds your YYYY-MM-DD.md entries. It has to be a real folder on this " +
                    "phone that a sync app keeps up to date with your Mac, for example Syncthing, FolderSync or " +
                    "Autosync for Google Drive, OneDrive or Dropbox. The app reads and writes it in place and " +
                    "never uploads anything itself."),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
            Button(onClick = onChoose) { Text(if (message == null) "Choose folder" else "Choose another folder") }
            onRetry?.let { OutlinedButton(onClick = it) { Text("Try again") } }
        }
    }
}
