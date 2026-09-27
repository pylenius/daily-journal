package journal.core

import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.nio.file.FileAlreadyExistsException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.time.ZonedDateTime
import java.util.UUID

/**
 * The journal folder as the app sees it. Paths are relative to the folder root and use `/`, e.g. `2026-09-03.md` or
 * `inbox/2026-09-04-091233-beef.md`. On Android the app implements this over the Storage Access Framework; tests and
 * debug builds use [FileSystemFolder].
 */
interface JournalFolder {
    data class FileInfo(val name: String, val modified: Long?, val size: Long?)

    /** A short name for the UI. */
    val displayName: String

    fun isReachable(): Boolean

    /** Files (not directories) directly inside [dir]; an empty list if [dir] does not exist. */
    fun list(dir: String = ""): List<FileInfo>

    fun read(path: String): ByteArray

    /** Replaces an existing file, atomically where the storage allows it. */
    fun replace(path: String, bytes: ByteArray)

    /** Creates a new file, and its directory if needed. Throws [FileAlreadyExistsException] rather than overwrite. */
    fun createNew(path: String, bytes: ByteArray)
}

class ChangedSinceLoadException : Exception("The entry changed on another device since you opened it.")

class FolderUnreachableException : IOException("The journal folder is not reachable right now.")

/**
 * All reads and writes to the journal folder. There is no file coordination on Android, so every edit re-reads the
 * file right before writing; sync apps that briefly hold a file are retried.
 */
class JournalFileIO(val folder: JournalFolder) {
    data class EntryFile(val name: String, val date: String, val modified: Long?)
    data class Loaded(val text: String, val modified: Long?, val hash: String)

    // Listing

    fun listEntryFiles(): List<EntryFile> {
        if (!folder.isReachable()) throw FolderUnreachableException()
        return folder.list()
            .mapNotNull { f -> JournalParser.dateFromFileName(f.name)?.let { EntryFile(f.name, it, f.modified) } }
            .sortedByDescending { it.date }
    }

    /** Changes whenever an entry or capture is added, removed or rewritten; cheap enough to poll. */
    fun signature(): String =
        (folder.list().filter { JournalParser.dateFromFileName(it.name) != null } + folder.list(INBOX))
            .sortedBy { it.name }
            .joinToString("|") { "${it.name}:${it.modified}:${it.size}" }

    // Reading

    fun read(name: String): Loaded = retry {
        val data = folder.read(name)
        Loaded(decode(data), null, hash(data))
    }

    // Writing

    /** Flips one checkbox. Re-reads first so a concurrent Mac write is never clobbered. */
    fun toggle(name: String, line: Int, expectedRaw: String): Loaded {
        val flipped = CheckboxToggler.flip(expectedRaw) ?: throw LineEditException(EditFailure.LineNotFound)
        return editLine(name, line, expectedRaw, flipped)
    }

    /** Replaces (or, with null, deletes) one line, located by position or unique text. Every other byte is kept. */
    fun editLine(name: String, line: Int, expectedRaw: String, replacement: String?): Loaded = retry {
        val text = decode(folder.read(name))
        writeFile(name, LineEditor.replace(text, line, expectedRaw, replacement))
    }

    /** Replaces the whole file. When [expectedHash] is given and the file no longer matches it, nothing is written. */
    fun write(name: String, text: String, expectedHash: String?): Loaded = retry {
        if (expectedHash != null && hash(folder.read(name)) != expectedHash) throw ChangedSinceLoadException()
        writeFile(name, text)
    }

    // Inbox

    fun listInbox(): List<InboxCapture> =
        folder.list(INBOX)
            .filter { it.name.endsWith(".md") && !it.name.startsWith(".") }
            .mapNotNull { f ->
                try {
                    InboxParser.parse(f.name, decode(folder.read("$INBOX/${f.name}")))
                } catch (_: IOException) {
                    null
                }
            }
            .sortedByDescending { it.fileName }

    /** Writes a new capture into `inbox/`. Never overwrites an existing file. */
    fun writeCapture(kind: CaptureKind, body: String, device: String?, now: ZonedDateTime = ZonedDateTime.now()): String {
        val (name, contents) = InboxWriter.makeCapture(kind, body, device, now)
        folder.createNew("$INBOX/$name", contents.toByteArray(Charsets.UTF_8))
        return name
    }

    // Helpers

    private fun writeFile(name: String, text: String): Loaded {
        val bytes = text.toByteArray(Charsets.UTF_8)
        folder.replace(name, bytes)
        return Loaded(text, null, hash(bytes))
    }

    companion object {
        const val INBOX = "inbox"
        private val BOM = byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte())

        fun hash(data: ByteArray): String =
            MessageDigest.getInstance("SHA-256").digest(data).joinToString("") { "%02x".format(it) }

        /** UTF-8, tolerating a BOM (which is kept out of the text; entries are written without one). */
        fun decode(data: ByteArray): String {
            val start = if (data.size >= 3 && data.copyOfRange(0, 3).contentEquals(BOM)) 3 else 0
            return String(data, start, data.size - start, Charsets.UTF_8)
        }

        /** Retries briefly on I/O errors: sync apps hold files open while uploading or downloading. */
        private fun <T> retry(body: () -> T): T {
            var attempt = 0
            while (true) {
                try {
                    return body()
                } catch (e: IOException) {
                    if (attempt >= 4 || e is FileNotFoundException || e is FolderUnreachableException) throw e
                    Thread.sleep(150L * ++attempt)
                }
            }
        }
    }
}

/** [JournalFolder] over a plain directory; writes go to a temp file that is renamed over the target. */
class FileSystemFolder(val root: File) : JournalFolder {
    override val displayName: String get() = root.name

    override fun isReachable() = root.isDirectory

    override fun list(dir: String): List<JournalFolder.FileInfo> =
        (resolve(dir).listFiles() ?: emptyArray())
            .filter { it.isFile }
            .map { JournalFolder.FileInfo(it.name, it.lastModified(), it.length()) }

    override fun read(path: String): ByteArray = resolve(path).readBytes()

    override fun replace(path: String, bytes: ByteArray) {
        val target = resolve(path)
        val temp = File(target.parentFile, ".${target.name}.${UUID.randomUUID().toString().replace("-", "")}.tmp")
        try {
            temp.writeBytes(bytes)
            Files.move(temp.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
        } finally {
            temp.delete()
        }
    }

    override fun createNew(path: String, bytes: ByteArray) {
        val target = resolve(path)
        target.parentFile?.mkdirs()
        Files.write(target.toPath(), bytes, java.nio.file.StandardOpenOption.CREATE_NEW, java.nio.file.StandardOpenOption.WRITE)
    }

    private fun resolve(path: String) = if (path.isEmpty()) root else File(root, path)
}
