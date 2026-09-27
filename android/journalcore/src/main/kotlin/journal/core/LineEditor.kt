package journal.core

enum class EditFailure { LineNotFound, NotACheckbox }

class LineEditException(val failure: EditFailure) : Exception(
    if (failure == EditFailure.LineNotFound) "That line is no longer in the entry. It was reloaded."
    else "That line is not a checkbox."
)

/** Single-line edits that keep every other byte of the file intact. */
object LineEditor {
    /**
     * Locates the line (at [line] if it still reads [expectedRaw], else by unique text match) and replaces it with
     * [replacement]; null deletes the line. Returns the whole new file text.
     */
    fun replace(text: String, line: Int, expectedRaw: String, replacement: String?): String {
        // Each line keeps its own ending, so CRLF, LF and mixed files come back byte for byte.
        val parts = text.split('\n').toMutableList()
        fun content(i: Int) = parts[i].removeSuffix("\r")
        var index = line
        if (!(index in parts.indices && content(index) == expectedRaw)) {
            val matches = parts.indices.filter { content(it) == expectedRaw }
            if (matches.size != 1) throw LineEditException(EditFailure.LineNotFound)
            index = matches[0]
        }
        if (replacement != null) parts[index] = replacement + (if (parts[index].endsWith('\r')) "\r" else "")
        else parts.removeAt(index)
        return parts.joinToString("\n")
    }

    /** `- text` ↔ `- **text**` (a highlighted Done item). Null if the line is not a plain bullet. */
    fun highlightToggled(line: String): String? {
        val item = DoneItem.parse(line) ?: return null
        val prefix = line.substring(0, item.bulletPrefixLength)
        return if (item.isHighlighted) "$prefix${item.text}" else "$prefix**${item.text}**"
    }
}

/** A plain bullet under `## Done`. */
data class DoneItem(
    val date: String,
    val line: Int,
    val raw: String,
    val text: String,
    val isHighlighted: Boolean,
    val bulletPrefixLength: Int,
) {
    val id: String get() = "$date#$line"

    companion object {
        fun parse(line: String, date: String = "", lineNumber: Int = 0): DoneItem? {
            val indent = line.takeWhile { it == ' ' || it == '\t' }.length
            val rest = line.substring(indent)
            if (!(rest.startsWith("- ") || rest.startsWith("* "))) return null
            if (JournalParser.parseCheckbox(line) != null) return null
            var body = rest.substring(2).trim()
            var highlighted = false
            if (body.startsWith("**") && body.endsWith("**") && body.length > 4) {
                val inner = body.substring(2, body.length - 2)
                if (!inner.contains("**")) { body = inner; highlighted = true }
            }
            return DoneItem(date, lineNumber, line, body, highlighted, indent + 2)
        }
    }
}

object CheckboxToggler {
    /** Flip `[ ]`↔`[x]` on one line, preserving every other byte and the newline style. */
    fun toggle(text: String, line: Int, expectedRaw: String): String {
        val flipped = flip(expectedRaw) ?: throw LineEditException(EditFailure.NotACheckbox)
        return LineEditor.replace(text, line, expectedRaw, flipped)
    }

    /** The single line with its box flipped, or null if it is not a checkbox line. */
    fun flip(line: String): String? {
        if (JournalParser.parseCheckbox(line) == null) return null
        for ((from, to) in listOf("- [ ] " to "- [x] ", "- [x] " to "- [ ] ", "- [X] " to "- [ ] ")) {
            val i = line.indexOf(from)
            if (i >= 0) return line.substring(0, i) + to + line.substring(i + from.length)
        }
        return null
    }
}
