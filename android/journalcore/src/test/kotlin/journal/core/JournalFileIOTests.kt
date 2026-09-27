package journal.core

import java.io.File
import java.nio.file.FileAlreadyExistsException
import java.nio.file.Files
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class JournalFileIOTests {
    private val dir: File = Files.createTempDirectory("journal-tests-").toFile()
    private val io = JournalFileIO(FileSystemFolder(dir))

    @AfterTest fun cleanUp() {
        dir.deleteRecursively()
    }

    private fun put(name: String, text: String) = File(dir, name).writeText(text)
    private fun get(name: String) = File(dir, name).readText()

    @Test fun listsOnlyEntryFilesNewestFirst() {
        put("2026-09-03.md", "# a\n")
        put("2026-09-04.md", "# b\n")
        put("2026-09-04-DESKTOP.md", "conflict copy\n")
        put("notes.md", "x\n")
        assertEquals(listOf("2026-09-04", "2026-09-03"), io.listEntryFiles().map { it.date })
    }

    @Test fun unreachableFolderThrows() {
        val gone = JournalFileIO(FileSystemFolder(File(dir, "missing")))
        assertFailsWith<FolderUnreachableException> { gone.listEntryFiles() }
    }

    @Test fun toggleKeepsCrlfAndEveryOtherByte() {
        put("2026-09-05.md", "# T\r\n\r\n## Actions\r\n- [ ] one — source: x\r\n- [ ] two\r\n")
        val loaded = io.toggle("2026-09-05.md", 4, "- [ ] two")
        assertEquals("# T\r\n\r\n## Actions\r\n- [ ] one — source: x\r\n- [x] two\r\n", get("2026-09-05.md"))
        assertEquals(io.read("2026-09-05.md").hash, loaded.hash)
        assertTrue(dir.listFiles()!!.none { it.name.startsWith(".") })
    }

    @Test fun toggleFailsWhenLineGone() {
        put("2026-09-05.md", "## Actions\n- [ ] one\n")
        assertFailsWith<LineEditException> { io.toggle("2026-09-05.md", 1, "- [ ] two") }
        assertEquals("## Actions\n- [ ] one\n", get("2026-09-05.md"))
    }

    @Test fun staleWriteIsRefused() {
        put("2026-09-06.md", "## Done\n- a\n")
        val hash = io.read("2026-09-06.md").hash
        put("2026-09-06.md", "## Done\n- a\n- written by the Mac\n")
        assertFailsWith<ChangedSinceLoadException> { io.write("2026-09-06.md", "## Done\n- mine\n", hash) }
        assertTrue(get("2026-09-06.md").contains("written by the Mac"))
        io.write("2026-09-06.md", "## Done\n- mine\n", null)
        assertEquals("## Done\n- mine\n", get("2026-09-06.md"))
    }

    @Test fun captureNeverOverwritesAndIsListed() {
        val now = ZonedDateTime.of(2026, 9, 4, 9, 12, 33, 0, ZoneId.of("Europe/Helsinki"))
        val name = io.writeCapture(CaptureKind.Action, "Call Noor", "Android", now)
        val inbox = io.listInbox()
        assertEquals(1, inbox.size)
        assertEquals(name, inbox[0].fileName)
        assertEquals(CaptureKind.Action, inbox[0].kind)
        assertEquals("Call Noor", inbox[0].body)
        assertFailsWith<FileAlreadyExistsException> {
            FileSystemFolder(dir).createNew("inbox/$name", "x".toByteArray())
        }
        assertEquals("Call Noor", io.listInbox()[0].body)
    }

    @Test fun signatureChangesWithContent() {
        put("2026-09-03.md", "# a\n")
        val before = io.signature()
        put("notes.md", "not an entry\n")
        assertEquals(before, io.signature())
        io.writeCapture(CaptureKind.Note, "x", null)
        assertNotEquals(before, io.signature())
    }

    @Test fun readToleratesBom() {
        File(dir, "2026-09-07.md").writeBytes(byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte()) + "# T\n".toByteArray())
        assertEquals("# T\n", io.read("2026-09-07.md").text)
    }
}
