package journal.core

import java.text.Normalizer
import java.util.Locale

data class SearchHit(val date: String, val line: Int, val lineText: String, val section: SectionKind) {
    val id: String get() = "$date#$line"
}

/**
 * Case- and diacritic-insensitive substring search over every line of every entry.
 * Every query term must occur on the same line (AND). Small enough to rebuild on each folder change.
 */
class SearchIndex(entries: Iterable<JournalEntry>) {
    private data class Row(val date: String, val line: Int, val text: String, val folded: String, val section: SectionKind)

    private val rows = buildList {
        for (e in entries) for (s in e.sections) for (i in s.bodyLines) {
            val t = e.lines[i]
            if (t.isBlank()) continue
            add(Row(e.date, i, t, fold(t), s.kind))
        }
    }

    val lineCount: Int get() = rows.size

    /** Hits newest day first, file order within a day. */
    fun search(query: String, limit: Int = 200): List<SearchHit> {
        val terms = terms(query)
        if (terms.isEmpty()) return emptyList()
        return rows.asSequence()
            .filter { r -> terms.all { r.folded.contains(it) } }
            .map { SearchHit(it.date, it.line, it.text, it.section) }
            .sortedWith(compareByDescending<SearchHit> { it.date }.thenBy { it.line })
            .take(limit)
            .toList()
    }

    companion object {
        private val MARKS = Regex("""\p{Mn}+""")

        fun fold(s: String): String =
            Normalizer.normalize(MARKS.replace(Normalizer.normalize(s, Normalizer.Form.NFD), ""), Normalizer.Form.NFC)
                .lowercase(Locale.ROOT)

        fun terms(query: String): List<String> =
            query.split(Regex("""\s+""")).filter { it.isNotEmpty() }.map(::fold).filter { it.isNotEmpty() }

        /**
         * Ranges in [text] where any query term matches, for highlighting. Folds per character, so the ranges map back
         * onto the original string even when a character loses its accent.
         */
        fun matchRanges(text: String, query: String): List<IntRange> {
            val terms = terms(query)
            if (terms.isEmpty()) return emptyList()
            val folded = StringBuilder()
            val origin = mutableListOf<Int>()
            var i = 0
            while (i < text.length) {
                val len = Character.charCount(text.codePointAt(i))
                val f = fold(text.substring(i, i + len))
                folded.append(f)
                repeat(f.length) { origin += i }
                i += len
            }
            val ranges = mutableListOf<IntRange>()
            val haystack = folded.toString()
            for (term in terms) {
                var from = haystack.indexOf(term)
                while (from >= 0) {
                    val endFolded = from + term.length - 1
                    val end = origin[endFolded] + Character.charCount(text.codePointAt(origin[endFolded])) - 1
                    ranges += origin[from]..end
                    from = haystack.indexOf(term, from + term.length)
                }
            }
            return ranges.sortedBy { it.first }
        }
    }
}
