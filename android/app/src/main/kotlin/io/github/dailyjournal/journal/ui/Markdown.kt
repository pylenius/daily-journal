package io.github.dailyjournal.journal.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Checkbox
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import java.util.regex.Pattern

/**
 * A small line-based Markdown renderer for Details and other free-form sections, covering what the journal writer
 * produces: headings, bullets, numbered lists, task items, quotes, code blocks, tables, rules and inline emphasis,
 * code and links. Task items are real checkboxes; [onToggle] gets their 0-based line within [markdown], so the store
 * can flip exactly that line in the file.
 */
@Composable
fun MarkdownBlocks(markdown: String, onToggle: ((Int) -> Unit)? = null, modifier: Modifier = Modifier) {
    val blocks = remember(markdown) { parseBlocks(markdown) }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        for (block in blocks) Block(block, onToggle)
    }
}

@Composable
private fun Block(block: MdBlock, onToggle: ((Int) -> Unit)?) {
    val colors = MaterialTheme.colorScheme
    when (block) {
        is MdBlock.Heading -> Text(
            inlineMarkdown(block.text, colors.primary),
            style = when (block.level) {
                1 -> MaterialTheme.typography.titleLarge
                2 -> MaterialTheme.typography.titleMedium
                else -> MaterialTheme.typography.titleSmall
            },
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(top = 8.dp),
        )
        is MdBlock.Paragraph -> Text(inlineMarkdown(block.text, colors.primary), style = MaterialTheme.typography.bodyMedium)
        is MdBlock.Item -> Row(Modifier.padding(start = (block.indent * 16).dp)) {
            Text(block.marker, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.width(if (block.marker.length > 2) 28.dp else 16.dp))
            Text(inlineMarkdown(block.text, colors.primary), style = MaterialTheme.typography.bodyMedium)
        }
        is MdBlock.Task -> Row(Modifier.padding(start = (block.indent * 16).dp), verticalAlignment = Alignment.Top) {
            Checkbox(
                checked = block.checked,
                onCheckedChange = onToggle?.let { toggle -> { toggle(block.line) } },
                modifier = Modifier.padding(end = 4.dp).then(Modifier.width(24.dp)),
            )
            Text(
                inlineMarkdown(block.text, colors.primary),
                style = MaterialTheme.typography.bodyMedium,
                color = if (block.checked) colors.onSurfaceVariant else Color.Unspecified,
                textDecoration = if (block.checked) TextDecoration.LineThrough else null,
                modifier = Modifier.padding(top = 12.dp),
            )
        }
        is MdBlock.Quote -> Row {
            Box(Modifier.width(3.dp).background(colors.outlineVariant).padding(vertical = 10.dp))
            Text(
                inlineMarkdown(block.text, colors.primary),
                style = MaterialTheme.typography.bodyMedium,
                color = colors.onSurfaceVariant,
                modifier = Modifier.padding(start = 10.dp),
            )
        }
        is MdBlock.Code -> Text(
            block.text,
            fontFamily = FontFamily.Monospace,
            style = MaterialTheme.typography.bodySmall,
            modifier = Modifier
                .fillMaxWidth()
                .background(colors.surfaceContainerHighest, RoundedCornerShape(8.dp))
                .horizontalScroll(rememberScrollState())
                .padding(10.dp),
        )
        is MdBlock.Table -> Column(
            Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState())
                .background(colors.surfaceContainerHigh, RoundedCornerShape(8.dp))
                .padding(8.dp),
        ) {
            block.rows.forEachIndexed { r, cells ->
                Row {
                    cells.forEach { cell ->
                        Text(
                            inlineMarkdown(cell, colors.primary),
                            style = MaterialTheme.typography.bodySmall,
                            fontWeight = if (r == 0) FontWeight.SemiBold else null,
                            modifier = Modifier.width(140.dp).padding(end = 8.dp, bottom = 4.dp),
                        )
                    }
                }
            }
        }
        MdBlock.Rule -> HorizontalDivider(Modifier.padding(vertical = 4.dp))
    }
}

// Blocks

sealed interface MdBlock {
    data class Heading(val level: Int, val text: String) : MdBlock
    data class Paragraph(val text: String) : MdBlock
    data class Item(val indent: Int, val marker: String, val text: String) : MdBlock
    data class Task(val indent: Int, val checked: Boolean, val text: String, val line: Int) : MdBlock
    data class Quote(val text: String) : MdBlock
    data class Code(val text: String) : MdBlock
    data class Table(val rows: List<List<String>>) : MdBlock
    data object Rule : MdBlock
}

private val HEADING = Regex("""^(#{1,6})\s+(.*?)\s*#*\s*$""")
private val TASK = Regex("""^(\s*)[-*+] \[( |x|X)] (.*)$""")
private val BULLET = Regex("""^(\s*)[-*+]\s+(.*)$""")
private val ORDERED = Regex("""^(\s*)(\d+[.)])\s+(.*)$""")
private val QUOTE = Regex("""^\s*>\s?(.*)$""")
private val RULE = Regex("""^\s*([-*_])(\s*\1){2,}\s*$""")
private val TABLE_SEPARATOR = Regex("""^\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$""")

private fun indentOf(s: String) = s.replace("\t", "    ").length / 2

private fun isBlockStart(line: String) =
    line.isBlank() || HEADING.matches(line) || BULLET.matches(line) || ORDERED.matches(line) ||
        QUOTE.matches(line) || RULE.matches(line) || line.trimStart().startsWith("```") || line.trimStart().startsWith("|")

fun parseBlocks(markdown: String): List<MdBlock> {
    val lines = markdown.split('\n').map { it.removeSuffix("\r") }
    val out = mutableListOf<MdBlock>()
    var i = 0
    while (i < lines.size) {
        val line = lines[i]
        when {
            line.isBlank() -> i++
            line.trimStart().startsWith("```") -> {
                val code = mutableListOf<String>()
                i++
                while (i < lines.size && !lines[i].trimStart().startsWith("```")) code += lines[i++]
                i++ // closing fence
                out += MdBlock.Code(code.joinToString("\n"))
            }
            RULE.matches(line) -> { out += MdBlock.Rule; i++ }
            HEADING.matches(line) -> {
                val m = HEADING.matchEntire(line)!!
                out += MdBlock.Heading(m.groupValues[1].length, m.groupValues[2]); i++
            }
            line.trimStart().startsWith("|") -> {
                val rows = mutableListOf<List<String>>()
                while (i < lines.size && lines[i].trimStart().startsWith("|")) {
                    val row = lines[i++].trim()
                    if (TABLE_SEPARATOR.matches(row)) continue
                    rows += row.removePrefix("|").removeSuffix("|").split("|").map { it.trim() }
                }
                out += MdBlock.Table(rows)
            }
            TASK.matches(line) -> {
                val m = TASK.matchEntire(line)!!
                val start = i++
                val text = StringBuilder(m.groupValues[3])
                while (i < lines.size && isContinuation(lines[i], m.groupValues[1])) text.append(' ').append(lines[i++].trim())
                out += MdBlock.Task(indentOf(m.groupValues[1]), m.groupValues[2] != " ", text.toString(), start)
            }
            BULLET.matches(line) || ORDERED.matches(line) -> {
                val b = BULLET.matchEntire(line)
                val indent = b?.groupValues?.get(1) ?: ORDERED.matchEntire(line)!!.groupValues[1]
                val marker = if (b != null) "•" else ORDERED.matchEntire(line)!!.groupValues[2]
                val text = StringBuilder(b?.groupValues?.get(2) ?: ORDERED.matchEntire(line)!!.groupValues[3])
                i++
                while (i < lines.size && isContinuation(lines[i], indent)) text.append(' ').append(lines[i++].trim())
                out += MdBlock.Item(indentOf(indent), marker, text.toString())
            }
            QUOTE.matches(line) -> {
                val text = mutableListOf<String>()
                while (i < lines.size && QUOTE.matches(lines[i])) text += QUOTE.matchEntire(lines[i++])!!.groupValues[1]
                out += MdBlock.Quote(text.joinToString(" "))
            }
            else -> {
                val text = StringBuilder(line.trim())
                i++
                while (i < lines.size && !isBlockStart(lines[i])) text.append(' ').append(lines[i++].trim())
                out += MdBlock.Paragraph(text.toString())
            }
        }
    }
    return out
}

/** An indented plain line under a list item belongs to that item. */
private fun isContinuation(line: String, itemIndent: String): Boolean {
    if (line.isBlank()) return false
    val leading = line.takeWhile { it == ' ' || it == '\t' }
    if (leading.replace("\t", "    ").length <= itemIndent.replace("\t", "    ").length) return false
    return !BULLET.matches(line) && !ORDERED.matches(line)
}

// Inline

private val URL = Pattern.compile("""https?://[^\s<>"'`()\[\]]+""", Pattern.CASE_INSENSITIVE)
private val MD_LINK = Pattern.compile("""\[([^\]]+)]\(([^)\s]+)\)""")

/**
 * Inline Markdown to an [AnnotatedString]: `**bold**`, `*italic*`/`_italic_`, `~~strike~~`, `` `code` ``,
 * `[text](url)`, `<url>` and bare URLs. Anything unmatched is kept literally.
 */
fun inlineMarkdown(text: String, linkColor: Color, codeBackground: Color = Color(0x1F808080)): AnnotatedString {
    val linkStyles = TextLinkStyles(SpanStyle(color = linkColor, textDecoration = TextDecoration.Underline))
    return buildAnnotatedString {
        fun run(s: String) {
            var i = 0
            val plain = StringBuilder()
            fun flush() { append(plain); plain.clear() }
            while (i < s.length) {
                val c = s[i]
                // bare URL (checked first, so underscores in URLs are not emphasis)
                if ((c == 'h' || c == 'H') && (i == 0 || !s[i - 1].isLetterOrDigit())) {
                    val m = URL.matcher(s).region(i, s.length)
                    if (m.lookingAt()) {
                        val url = m.group().trimEnd { it in ".,;:!?" }
                        flush()
                        withLink(LinkAnnotation.Url(url, linkStyles)) { append(url) }
                        i += url.length
                        continue
                    }
                }
                if (c == '<') {
                    val end = s.indexOf('>', i + 1)
                    if (end > i && URL.matcher(s.substring(i + 1, end)).matches()) {
                        val url = s.substring(i + 1, end)
                        flush()
                        withLink(LinkAnnotation.Url(url, linkStyles)) { append(url) }
                        i = end + 1
                        continue
                    }
                }
                if (c == '[') {
                    val m = MD_LINK.matcher(s).region(i, s.length)
                    if (m.lookingAt()) {
                        flush()
                        withLink(LinkAnnotation.Url(m.group(2)!!, linkStyles)) { run(m.group(1)!!) }
                        i = m.end()
                        continue
                    }
                }
                if (c == '`') {
                    val end = s.indexOf('`', i + 1)
                    if (end > i + 1) {
                        flush()
                        withStyle(SpanStyle(fontFamily = FontFamily.Monospace, background = codeBackground)) {
                            append(s.substring(i + 1, end))
                        }
                        i = end + 1
                        continue
                    }
                }
                val delimiter = when {
                    s.startsWith("**", i) -> "**"
                    s.startsWith("__", i) && (i == 0 || !s[i - 1].isLetterOrDigit()) -> "__"
                    s.startsWith("~~", i) -> "~~"
                    c == '*' -> "*"
                    c == '_' && (i == 0 || !s[i - 1].isLetterOrDigit()) -> "_"
                    else -> null
                }
                if (delimiter != null && i + delimiter.length < s.length && !s[i + delimiter.length].isWhitespace()) {
                    val end = s.indexOf(delimiter, i + delimiter.length + 1)
                    val closes = end > 0 && !s[end - 1].isWhitespace() &&
                        (delimiter[0] != '_' || end + delimiter.length >= s.length || !s[end + delimiter.length].isLetterOrDigit())
                    if (closes) {
                        flush()
                        val style = when (delimiter) {
                            "**", "__" -> SpanStyle(fontWeight = FontWeight.Bold)
                            "~~" -> SpanStyle(textDecoration = TextDecoration.LineThrough)
                            else -> SpanStyle(fontStyle = FontStyle.Italic)
                        }
                        withStyle(style) { run(s.substring(i + delimiter.length, end)) }
                        i = end + delimiter.length
                        continue
                    }
                }
                if (c == '\\' && i + 1 < s.length && s[i + 1] in "\\`*_[]()#+-.!~|<>") {
                    plain.append(s[i + 1]); i += 2; continue
                }
                plain.append(c)
                i++
            }
            flush()
        }
        run(text)
    }
}
