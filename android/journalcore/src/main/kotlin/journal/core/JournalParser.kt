package journal.core

import java.net.URI

object JournalParser {
    private val FILE_REGEX = Regex("""^(\d{4}-\d{2}-\d{2})\.md$""")
    private val CHECKBOX_REGEX = Regex("""^(\s*)- \[( |x|X)] (.*)$""")
    private val MARKER_REGEX = Regex("""\s+[—–-]{1,2}\s+(source|done):\s*""")
    private val URL_REGEX = Regex("""https?://[^\s<>"'`()\[\]]+""", RegexOption.IGNORE_CASE)
    private const val URL_TRAILING = ".,;:!?"

    /** Returns the date if [fileName] is an entry file, else null. */
    fun dateFromFileName(fileName: String): String? = FILE_REGEX.matchEntire(fileName)?.groupValues?.get(1)

    fun parse(text: String, fileName: String): JournalEntry {
        val date = dateFromFileName(fileName) ?: fileName
        val (lines, newline) = splitLines(text)

        var title = ""
        val sections = mutableListOf<Section>()
        var current: Section? = null // bodyEnd is filled in by close()
        var preambleStart = 0

        fun close(end: Int) {
            val c = current
            if (c != null) {
                sections += c.copy(bodyEnd = end)
            } else if (end > preambleStart && lines.subList(preambleStart, end).any { it.isNotBlank() }) {
                sections += Section(SectionKind.Preamble, "", -1, preambleStart, end)
            }
        }

        for ((i, line) in lines.withIndex()) {
            if (line.startsWith("# ") && title.isEmpty() && current == null) {
                title = line.substring(2).trim()
                preambleStart = i + 1
            } else if (line.startsWith("## ")) {
                close(i)
                val heading = line.substring(3)
                current = Section(SectionKind.recognise(heading), heading.trim(), i, i + 1, i + 1)
            }
        }
        close(lines.size)

        val checkboxes = mutableListOf<CheckboxLine>()
        val doneItems = mutableListOf<DoneItem>()
        for (section in sections) {
            var i = section.bodyStart
            while (i < section.bodyEnd) {
                val line = lines[i]
                val cb = parseCheckbox(line)
                if (cb != null) {
                    val continuation = mutableListOf<String>()
                    var j = i + 1
                    while (j < section.bodyEnd && isContinuation(lines[j], cb.indent)) {
                        continuation += lines[j]; j++
                    }
                    checkboxes += makeCheckbox(cb, i, date, section.kind, line, continuation)
                    i = j
                    continue
                }
                if (section.kind == SectionKind.Done) DoneItem.parse(line, date, i)?.let { doneItems += it }
                i++
            }
        }

        return JournalEntry(date, fileName, title, lines, newline, sections, checkboxes, doneItems)
    }

    /**
     * Splits on LF and drops a CR before it, so CRLF, LF and files mixing both (a line appended on Windows) all parse.
     * The reported newline is the first line's ending.
     */
    fun splitLines(text: String): Pair<List<String>, String> {
        val raw = text.split('\n')
        val newline = if (raw.size > 1 && raw[0].endsWith('\r')) "\r\n" else "\n"
        return raw.map { it.removeSuffix("\r") } to newline
    }

    internal data class RawCheckbox(val indent: Int, val checked: Boolean, val body: String)

    internal fun parseCheckbox(line: String): RawCheckbox? {
        val m = CHECKBOX_REGEX.matchEntire(line) ?: return null
        return RawCheckbox(m.groupValues[1].length, m.groupValues[2] != " ", m.groupValues[3])
    }

    private fun isContinuation(line: String, indent: Int): Boolean {
        if (line.isBlank()) return false
        val leading = line.takeWhile { it == ' ' || it == '\t' }.length
        if (leading <= indent) return false
        return parseCheckbox(line) == null
    }

    /** URLs found anywhere in [text], trailing punctuation trimmed. */
    fun findUrls(text: String): List<URI> = splitUrls(text).mapNotNull { it.second }

    /** Splits text into plain and URL runs, for rendering links. */
    fun splitUrls(text: String): List<Pair<String, URI?>> {
        val out = mutableListOf<Pair<String, URI?>>()
        var pos = 0
        for (m in URL_REGEX.findAll(text)) {
            if (m.range.first < pos) continue
            val s = m.value.trimEnd { it in URL_TRAILING }
            val uri = runCatching { URI(s) }.getOrNull()?.takeIf { it.isAbsolute } ?: continue
            if (m.range.first > pos) out += text.substring(pos, m.range.first) to null
            out += s to uri
            pos = m.range.first + s.length
        }
        if (pos < text.length) out += text.substring(pos) to null
        return out
    }

    private fun makeCheckbox(
        cb: RawCheckbox, line: Int, date: String, section: SectionKind, raw: String, continuation: List<String>,
    ): CheckboxLine {
        val body = cb.body
        var text = body
        var refKind: ReferenceKind? = null
        var reference: String? = null
        MARKER_REGEX.find(body)?.let { m ->
            text = body.substring(0, m.range.first)
            refKind = if (m.groupValues[1] == "source") ReferenceKind.Source else ReferenceKind.Done
            reference = body.substring(m.range.last + 1).trim()
        }
        text = text.trim()
        return CheckboxLine(
            "$date#$line", date, line, cb.checked, text, refKind, reference, findUrls(body),
            section, raw, continuation, CheckboxLine.identityKeyFor(text),
        )
    }
}
