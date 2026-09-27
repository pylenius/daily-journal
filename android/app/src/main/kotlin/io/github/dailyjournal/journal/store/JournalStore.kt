package io.github.dailyjournal.journal.store

import android.app.Application
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.edit
import androidx.core.net.toUri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import journal.core.AggregatedAction
import journal.core.CaptureKind
import journal.core.CheckboxLine
import journal.core.DoneItem
import journal.core.FileSystemFolder
import journal.core.InboxCapture
import journal.core.JournalEntry
import journal.core.JournalFileIO
import journal.core.JournalFolder
import journal.core.JournalParser
import journal.core.LineEditor
import journal.core.OpenActionsAggregator
import journal.core.SearchIndex
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File

enum class FolderState { NotChosen, Ready, Unreachable }

data class JournalState(
    val folderState: FolderState = FolderState.NotChosen,
    val folderName: String? = null,
    val unreachableMessage: String? = null,
    /** Newest first. */
    val entries: List<JournalEntry> = emptyList(),
    /** Entry files that could not be read yet (still downloading from the sync app). */
    val placeholders: List<String> = emptyList(),
    val inbox: List<InboxCapture> = emptyList(),
    val openActions: List<AggregatedAction> = emptyList(),
    val index: SearchIndex = SearchIndex(emptyList()),
    val hashes: Map<String, String> = emptyMap(),
    val isLoading: Boolean = false,
    val lastRefresh: Long? = null,
) {
    fun entry(date: String): JournalEntry? = entries.firstOrNull { it.date == date }
}

/**
 * The app's single source of truth, mirroring ios/Journal/Store/JournalStore.swift and the Windows store. File work
 * runs on the IO dispatcher, one operation at a time; the UI observes [state].
 */
class JournalStore(app: Application) : AndroidViewModel(app) {
    private val _state = MutableStateFlow(JournalState())
    val state: StateFlow<JournalState> = _state

    private val _messages = MutableSharedFlow<String>(extraBufferCapacity = 4)
    /** Errors and confirmations to show in a snackbar. */
    val messages: SharedFlow<String> = _messages

    private val prefs = app.getSharedPreferences("settings", Context.MODE_PRIVATE)
    private val lock = Mutex()
    private var io: JournalFileIO? = null
    private var signature: String? = null

    val canForget: Boolean get() = io?.folder is SafFolder

    // Folder

    fun restore() {
        val saved = prefs.getString(KEY_TREE, null)?.toUri()
        if (saved == null) {
            _state.update { it.copy(folderState = FolderState.NotChosen) }
            return
        }
        val permitted = getApplication<Application>().contentResolver.persistedUriPermissions
            .any { it.uri == saved && it.isReadPermission && it.isWritePermission }
        if (!permitted) {
            _state.update {
                it.copy(folderState = FolderState.Unreachable, unreachableMessage = "Access to the journal folder was revoked. Choose it again.")
            }
            return
        }
        activate(SafFolder(getApplication<Application>().contentResolver, saved))
    }

    fun chooseFolder(uri: Uri) {
        val resolver = getApplication<Application>().contentResolver
        val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        try {
            resolver.takePersistableUriPermission(uri, flags)
        } catch (e: SecurityException) {
            _messages.tryEmit("This folder cannot be kept open: ${e.message}")
            return
        }
        prefs.getString(KEY_TREE, null)?.toUri()?.takeIf { it != uri }?.let { old ->
            runCatching { resolver.releasePersistableUriPermission(old, flags) }
        }
        prefs.edit { putString(KEY_TREE, uri.toString()) }
        activate(SafFolder(resolver, uri))
    }

    /** Debug builds only: a plain directory path, so the emulator can be driven without the picker. */
    fun useDirectory(path: String) = activate(FileSystemFolder(File(path)))

    fun forgetFolder() {
        prefs.getString(KEY_TREE, null)?.toUri()?.let { old ->
            runCatching {
                getApplication<Application>().contentResolver.releasePersistableUriPermission(
                    old, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
            }
        }
        prefs.edit { remove(KEY_TREE) }
        io = null
        signature = null
        _state.value = JournalState(folderState = FolderState.NotChosen)
    }

    private fun activate(folder: JournalFolder) {
        io = JournalFileIO(folder)
        signature = null
        _state.value = JournalState(folderState = FolderState.Ready, folderName = null, isLoading = true)
        reload()
    }

    // Loading

    fun reload() {
        viewModelScope.launch { load(force = true) }
    }

    /** Cheap check used on resume and while the app is open: reloads only when a file was added, removed or changed. */
    fun reloadIfChanged() {
        viewModelScope.launch { load(force = false) }
    }

    private suspend fun load(force: Boolean) {
        val fileIO = io ?: return
        lock.withLock {
            val current = _state.value
            try {
                val result = withContext(Dispatchers.IO) {
                    val sig = fileIO.signature()
                    if (!force && sig == signature && current.folderState == FolderState.Ready) return@withContext null
                    if (force) _state.update { it.copy(isLoading = true) }
                    val previous = current.entries.associateBy { it.date }
                    val entries = mutableListOf<JournalEntry>()
                    val hashes = mutableMapOf<String, String>()
                    val placeholders = mutableListOf<String>()
                    for (f in fileIO.listEntryFiles()) {
                        try {
                            val loaded = fileIO.read(f.name)
                            val existing = previous[f.date]
                            entries += if (existing != null && current.hashes[f.date] == loaded.hash) existing
                            else JournalParser.parse(loaded.text, f.name)
                            hashes[f.date] = loaded.hash
                        } catch (_: Exception) {
                            placeholders += f.date
                        }
                    }
                    val inbox = runCatching { fileIO.listInbox() }.getOrDefault(emptyList())
                    Loaded(sig, entries.sortedByDescending { it.date }, hashes, placeholders, inbox, fileIO.folder.displayName)
                }
                if (io !== fileIO) return // folder changed meanwhile
                if (result == null) return
                signature = result.signature
                _state.update {
                    it.copy(
                        folderState = FolderState.Ready,
                        folderName = result.folderName,
                        unreachableMessage = null,
                        entries = result.entries,
                        hashes = result.hashes,
                        placeholders = result.placeholders,
                        inbox = result.inbox,
                        openActions = OpenActionsAggregator.openActions(result.entries),
                        index = SearchIndex(result.entries),
                        lastRefresh = System.currentTimeMillis(),
                    )
                }
            } catch (e: Exception) {
                if (io !== fileIO) return
                signature = null
                _state.update { it.copy(folderState = FolderState.Unreachable, unreachableMessage = e.message ?: e.toString()) }
            } finally {
                _state.update { it.copy(isLoading = false) }
            }
        }
    }

    private data class Loaded(
        val signature: String,
        val entries: List<JournalEntry>,
        val hashes: Map<String, String>,
        val placeholders: List<String>,
        val inbox: List<InboxCapture>,
        val folderName: String,
    )

    // Mutations

    fun toggle(cb: CheckboxLine) = mutate(cb.date) { fileIO, name -> fileIO.toggle(name, cb.line, cb.raw) }

    fun remove(item: DoneItem) = mutate(item.date) { fileIO, name -> fileIO.editLine(name, item.line, item.raw, null) }

    fun toggleHighlight(item: DoneItem) {
        val replacement = LineEditor.highlightToggled(item.raw) ?: return
        mutate(item.date) { fileIO, name -> fileIO.editLine(name, item.line, item.raw, replacement) }
    }

    private fun mutate(date: String, edit: (JournalFileIO, String) -> JournalFileIO.Loaded) {
        val fileIO = io ?: return
        val name = _state.value.entry(date)?.fileName ?: return
        viewModelScope.launch {
            try {
                val loaded = lock.withLock { withContext(Dispatchers.IO) { edit(fileIO, name) } }
                apply(loaded, date, name)
            } catch (e: Exception) {
                _messages.tryEmit(e.message ?: e.toString())
                load(force = true)
            }
        }
    }

    /** Full-text save. Throws [journal.core.ChangedSinceLoadException] when the file moved on. */
    suspend fun save(date: String, text: String, expectedHash: String?) {
        val fileIO = io ?: return
        val name = _state.value.entry(date)?.fileName ?: return
        val loaded = lock.withLock { withContext(Dispatchers.IO) { fileIO.write(name, text, expectedHash) } }
        apply(loaded, date, name)
    }

    fun capture(kind: CaptureKind, body: String) {
        val fileIO = io ?: return
        viewModelScope.launch {
            try {
                val inbox = lock.withLock {
                    withContext(Dispatchers.IO) {
                        fileIO.writeCapture(kind, body, DEVICE_NAME)
                        fileIO.listInbox()
                    }
                }
                _state.update { it.copy(inbox = inbox) }
                _messages.tryEmit(if (kind == CaptureKind.Action) "Action added to the inbox" else "Note added to the inbox")
            } catch (e: Exception) {
                _messages.tryEmit("Could not save the capture: ${e.message ?: e}")
            }
        }
    }

    private fun apply(loaded: JournalFileIO.Loaded, date: String, fileName: String) {
        val entry = JournalParser.parse(loaded.text, fileName)
        signature = null // the folder listing changed underneath us; let the next check re-read it
        _state.update { s ->
            val entries = (s.entries.filter { it.date != date } + entry).sortedByDescending { it.date }
            s.copy(
                entries = entries,
                hashes = s.hashes + (date to loaded.hash),
                openActions = OpenActionsAggregator.openActions(entries),
                index = SearchIndex(entries),
            )
        }
    }

    companion object {
        const val DEVICE_NAME = "Android"
        private const val KEY_TREE = "journalTreeUri"
    }
}
