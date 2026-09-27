package journal.core

import java.util.SortedSet

/** One action as seen across days: the newest copy decides its state. */
data class AggregatedAction(val key: String, val latest: CheckboxLine, val seenOn: List<String>) {
    val isOpen: Boolean get() = !latest.isChecked
    val firstSeen: String get() = seenOn.firstOrNull() ?: latest.date
}

object OpenActionsAggregator {
    /** All actions from `## Actions` / `## Carried over`, one per identity key, newest copy wins. */
    fun aggregate(entries: Iterable<JournalEntry>): List<AggregatedAction> {
        val latest = LinkedHashMap<String, CheckboxLine>()
        val dates = HashMap<String, SortedSet<String>>()
        for (entry in entries) {
            for (cb in entry.actions) {
                val existing = latest[cb.identityKey]
                if (existing == null) {
                    latest[cb.identityKey] = cb
                    dates[cb.identityKey] = sortedSetOf(cb.date)
                } else {
                    dates.getValue(cb.identityKey) += cb.date
                    val cmp = cb.date.compareTo(existing.date)
                    if (cmp > 0 || (cmp == 0 && cb.line > existing.line)) latest[cb.identityKey] = cb
                }
            }
        }
        return latest.map { (key, cb) -> AggregatedAction(key, cb, dates.getValue(key).toList()) }
            .sortedWith(compareByDescending<AggregatedAction> { it.latest.date }.thenBy { it.latest.line })
    }

    /** Only the open ones, newest day first, file order within a day. */
    fun openActions(entries: Iterable<JournalEntry>): List<AggregatedAction> = aggregate(entries).filter { it.isOpen }
}
