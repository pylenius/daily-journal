package journal.core

import java.net.URI
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

enum class SectionType { Done, Actions, CarriedOver, Details, Other, Preamble }

/** Which recognised section a line belongs to. See spec/JOURNAL_FORMAT.md. */
data class SectionKind(val type: SectionType, val name: String = "") {
    /** True for the two sections whose checkboxes count as actions. */
    val holdsActions: Boolean get() = type == SectionType.Actions || type == SectionType.CarriedOver

    val title: String
        get() = when (type) {
            SectionType.Done -> "Done"
            SectionType.Actions -> "Actions"
            SectionType.CarriedOver -> "Carried over"
            SectionType.Details -> "Details"
            SectionType.Other -> name
            SectionType.Preamble -> ""
        }

    companion object {
        val Done = SectionKind(SectionType.Done)
        val Actions = SectionKind(SectionType.Actions)
        val CarriedOver = SectionKind(SectionType.CarriedOver)
        val Details = SectionKind(SectionType.Details)
        val Preamble = SectionKind(SectionType.Preamble)
        fun other(name: String) = SectionKind(SectionType.Other, name)

        internal fun recognise(heading: String): SectionKind = when (heading.trim().lowercase(Locale.ROOT)) {
            "done" -> Done
            "actions" -> Actions
            "carried over" -> CarriedOver
            "details" -> Details
            else -> other(heading.trim())
        }
    }
}

/** A level-2 section of an entry. Body lines are 0-based line indexes after the heading, up to the next `##`. */
data class Section(val kind: SectionKind, val heading: String, val headingLine: Int, val bodyStart: Int, val bodyEnd: Int) {
    val bodyLines: IntRange get() = bodyStart until bodyEnd
}

/** How the trailing reference on a checkbox line was marked. */
enum class ReferenceKind { Source, Done }

/** One `- [ ]` / `- [x]` line. */
data class CheckboxLine(
    val id: String,
    val date: String,
    val line: Int,
    val isChecked: Boolean,
    val text: String,
    val referenceKind: ReferenceKind?,
    val reference: String?,
    val urls: List<URI>,
    val section: SectionKind,
    val raw: String,
    val continuation: List<String>,
    val identityKey: String,
) {
    /** The `(from YYYY-MM-DD)` note, if the text carries one. */
    val carriedFrom: String? get() = FROM_REGEX.find(text)?.groupValues?.get(1)

    companion object {
        internal val FROM_REGEX = Regex("""\(from (\d{4}-\d{2}-\d{2})\)\s*$""")
        private val WHITESPACE = Regex("""\s+""")

        /** Normalised identity across days. See spec "Action identity across days". */
        fun identityKeyFor(text: String): String {
            var t = FROM_REGEX.replaceFirst(text, "")
            t = WHITESPACE.replace(t, " ").trim().lowercase(Locale.ROOT)
            while (t.isNotEmpty() && t.last() in ".;:") t = t.dropLast(1)
            return t
        }
    }
}

/** A parsed journal entry. Immutable; re-parse after any write. */
class JournalEntry(
    /** `YYYY-MM-DD`, from the file name. */
    val date: String,
    val fileName: String,
    val title: String,
    val lines: List<String>,
    /** "\n" or "\r\n", whatever the file used (defaults to "\n"). */
    val newline: String,
    val sections: List<Section>,
    val checkboxes: List<CheckboxLine>,
    /** Plain bullets under `## Done`. */
    val doneItems: List<DoneItem>,
) {
    /** Checkboxes in `## Actions` and `## Carried over`. */
    val actions: List<CheckboxLine> by lazy { checkboxes.filter { it.section.holdsActions } }
    val openActionCount: Int get() = actions.count { !it.isChecked }

    fun sectionOf(kind: SectionKind): Section? = sections.firstOrNull { it.kind == kind }

    /** Raw text of a section body (without the heading). */
    fun textOf(kind: SectionKind): String? = sectionOf(kind)?.let { bodyText(it, newline) }

    fun bodyText(s: Section, separator: String = "\n"): String =
        lines.subList(s.bodyStart, s.bodyEnd).joinToString(separator)

    /** The whole file text as parsed. */
    val fullText: String get() = lines.joinToString(newline)

    val localDate: LocalDate? get() = runCatching { LocalDate.parse(date) }.getOrNull()

    /** Weekday-aware display title, falling back to the date. */
    fun displayDate(locale: Locale = Locale.getDefault()): String =
        localDate?.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.FULL).withLocale(locale)) ?: date
}
