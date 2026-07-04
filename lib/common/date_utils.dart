// Small date helpers used across the app. We store and compare days at local
// midnight so time-of-day never affects day grouping or lookups.

/// Strips the time component, returning local midnight of [d].
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// True if [a] and [b] fall on the same calendar day.
bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Whole-day difference (b - a), ignoring time-of-day.
int daysBetween(DateTime a, DateTime b) =>
    dateOnly(b).difference(dateOnly(a)).inDays;
