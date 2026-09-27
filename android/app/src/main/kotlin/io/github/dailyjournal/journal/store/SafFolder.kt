package io.github.dailyjournal.journal.store

import android.content.ContentResolver
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import journal.core.JournalFolder
import java.io.FileNotFoundException
import java.nio.file.FileAlreadyExistsException

/**
 * The journal folder through the Storage Access Framework: a tree the user picked once, kept with a persisted URI
 * permission. SAF has no atomic rename-over, so [replace] truncates and rewrites in place; [journal.core.JournalFileIO]
 * re-reads right before every write, which keeps the window for a clash with the sync app small.
 */
class SafFolder(private val resolver: ContentResolver, val treeUri: Uri) : JournalFolder {
    private data class Child(val id: String, val name: String, val isDir: Boolean, val modified: Long?, val size: Long?)

    private val rootId: String = DocumentsContract.getTreeDocumentId(treeUri)

    override val displayName: String by lazy {
        runCatching {
            resolver.query(docUri(rootId), arrayOf(Document.COLUMN_DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst()) it.getString(0) else null
            }
        }.getOrNull() ?: treeUri.lastPathSegment?.substringAfterLast(':')?.substringAfterLast('/') ?: "Journal"
    }

    override fun isReachable(): Boolean = runCatching {
        resolver.query(docUri(rootId), arrayOf(Document.COLUMN_MIME_TYPE), null, null, null)?.use {
            it.moveToFirst() && it.getString(0) == Document.MIME_TYPE_DIR
        } ?: false
    }.getOrDefault(false)

    override fun list(dir: String): List<JournalFolder.FileInfo> {
        val dirId = resolve(dir) ?: return emptyList()
        return children(dirId).filter { !it.isDir }.map { JournalFolder.FileInfo(it.name, it.modified, it.size) }
    }

    override fun read(path: String): ByteArray {
        val id = resolve(path) ?: throw FileNotFoundException(path)
        return resolver.openInputStream(docUri(id))?.use { it.readBytes() } ?: throw FileNotFoundException(path)
    }

    override fun replace(path: String, bytes: ByteArray) {
        val id = resolve(path) ?: throw FileNotFoundException(path)
        val stream = resolver.openOutputStream(docUri(id), "wt") ?: throw FileNotFoundException(path)
        stream.use { it.write(bytes) }
    }

    override fun createNew(path: String, bytes: ByteArray) {
        val dir = path.substringBeforeLast('/', "")
        val name = path.substringAfterLast('/')
        val dirId = ensureDir(dir)
        if (children(dirId).any { it.name == name }) throw FileAlreadyExistsException(path)
        // octet-stream so the provider keeps the name exactly as given instead of adjusting the extension.
        val uri = DocumentsContract.createDocument(resolver, docUri(dirId), "application/octet-stream", name)
            ?: throw FileNotFoundException(path)
        resolver.openOutputStream(uri, "wt")?.use { it.write(bytes) } ?: throw FileNotFoundException(path)
    }

    // Helpers

    private fun docUri(id: String): Uri = DocumentsContract.buildDocumentUriUsingTree(treeUri, id)

    private fun children(parentId: String): List<Child> {
        val uri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentId)
        val columns = arrayOf(
            Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME, Document.COLUMN_MIME_TYPE,
            Document.COLUMN_LAST_MODIFIED, Document.COLUMN_SIZE,
        )
        val out = mutableListOf<Child>()
        resolver.query(uri, columns, null, null, null)?.use { c ->
            while (c.moveToNext()) {
                out += Child(
                    id = c.getString(0),
                    name = c.getString(1) ?: continue,
                    isDir = c.getString(2) == Document.MIME_TYPE_DIR,
                    modified = if (c.isNull(3)) null else c.getLong(3),
                    size = if (c.isNull(4)) null else c.getLong(4),
                )
            }
        }
        return out
    }

    /** Document id for a relative path, or null if any part is missing. */
    private fun resolve(path: String): String? {
        var id = rootId
        for (part in path.split('/').filter { it.isNotEmpty() }) {
            id = children(id).firstOrNull { it.name == part }?.id ?: return null
        }
        return id
    }

    private fun ensureDir(path: String): String {
        var id = rootId
        for (part in path.split('/').filter { it.isNotEmpty() }) {
            val existing = children(id).firstOrNull { it.name == part && it.isDir }
            id = existing?.id ?: DocumentsContract.createDocument(resolver, docUri(id), Document.MIME_TYPE_DIR, part)
                ?.let { DocumentsContract.getDocumentId(it) } ?: throw FileNotFoundException(path)
        }
        return id
    }
}
