package journal.core

import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.random.Random

enum class CaptureKind { Note, Action }

/** A capture file in `inbox/`, written by a phone or PC and consumed by the Mac. */
data class InboxCapture(
    val fileName: String,
    val kind: CaptureKind,
    val created: OffsetDateTime?,
    val device: String?,
    val body: String,
) {
    val id: String get() = fileName
}

object InboxWriter {
    private val STAMP = DateTimeFormatter.ofPattern("yyyy-MM-dd-HHmmss", Locale.ROOT)
    private val ISO = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ssXXX", Locale.ROOT)

    /** File name and contents for a new capture, per spec "Inbox captures". */
    fun makeCapture(
        kind: CaptureKind,
        body: String,
        device: String?,
        now: ZonedDateTime = ZonedDateTime.now(ZoneId.systemDefault()),
        random: () -> Int = { Random.nextInt(0, 0x10000) },
    ): Pair<String, String> {
        val suffix = "%04x".format(random())
        var header = "kind: ${if (kind == CaptureKind.Action) "action" else "note"}\ncreated: ${now.format(ISO)}\n"
        if (!device.isNullOrEmpty()) header += "device: $device\n"
        return "${now.format(STAMP)}-$suffix.md" to header + "\n" + body.trim() + "\n"
    }
}

object InboxParser {
    /** Parses a capture file. Unknown header keys are ignored; missing `kind` means `note`. */
    fun parse(fileName: String, contents: String): InboxCapture {
        val normalised = contents.replace("\r\n", "\n")
        val parts = normalised.split("\n\n")
        val headers = mutableMapOf<String, String>()
        var body = normalised
        val headerLines = parts[0].split('\n')
        val looksLikeHeader = headerLines.all { line ->
            val colon = line.indexOf(':')
            colon > 0 && line.substring(0, colon).all { it.isLetter() || it == '_' || it == '-' }
        }
        if (looksLikeHeader) {
            for (line in headerLines) {
                val colon = line.indexOf(':')
                headers[line.substring(0, colon).lowercase(Locale.ROOT)] = line.substring(colon + 1).trim()
            }
            body = parts.drop(1).joinToString("\n\n")
        }
        val kind = if (headers["kind"] == "action") CaptureKind.Action else CaptureKind.Note
        val created = headers["created"]?.let { runCatching { OffsetDateTime.parse(it) }.getOrNull() }
        return InboxCapture(fileName, kind, created, headers["device"], body.trim())
    }
}
