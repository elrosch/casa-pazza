/// Recurrence units as stored in `tasks.repeat_unit`.
enum RepeatUnit {
  day('Tag', 'Tage', 'Täglich'),
  week('Woche', 'Wochen', 'Wöchentlich'),
  month('Monat', 'Monate', 'Monatlich'),
  year('Jahr', 'Jahre', 'Jährlich');

  const RepeatUnit(this.singular, this.plural, this.adverb);

  final String singular;
  final String plural;
  final String adverb;

  static RepeatUnit? fromName(String? name) =>
      RepeatUnit.values.where((u) => u.name == name).firstOrNull;
}

/// Human readable recurrence, e.g. "Wöchentlich" or "Alle 2 Wochen".
String describeRecurrence(RepeatUnit unit, int every) =>
    every <= 1 ? unit.adverb : 'Alle $every ${unit.plural}';

/// Adds [every] [unit]s to [date]. Month/year steps clamp to the last day of
/// the target month (31. Jan + 1 Monat = 28./29. Feb).
DateTime addRecurrence(DateTime date, RepeatUnit unit, int every) {
  final n = every < 1 ? 1 : every;
  switch (unit) {
    case RepeatUnit.day:
      return DateTime(
        date.year,
        date.month,
        date.day + n,
        date.hour,
        date.minute,
      );
    case RepeatUnit.week:
      return DateTime(
        date.year,
        date.month,
        date.day + 7 * n,
        date.hour,
        date.minute,
      );
    case RepeatUnit.month:
      return _addMonths(date, n);
    case RepeatUnit.year:
      return _addMonths(date, 12 * n);
  }
}

DateTime _addMonths(DateTime date, int months) {
  final firstOfTarget = DateTime(date.year, date.month + months);
  final lastDay = DateTime(firstOfTarget.year, firstOfTarget.month + 1, 0).day;
  final day = date.day > lastDay ? lastDay : date.day;
  return DateTime(
    firstOfTarget.year,
    firstOfTarget.month,
    day,
    date.hour,
    date.minute,
  );
}

/// Next due date after completing a recurring task on [now].
///
/// Advances from the current due date (or today) until the date lies after
/// today, so an overdue weekly task does not pile up missed occurrences.
DateTime nextDueDate({
  required DateTime? due,
  required RepeatUnit unit,
  required int every,
  required DateTime now,
}) {
  final today = DateTime(now.year, now.month, now.day);
  var next = addRecurrence(due ?? today, unit, every);
  while (!next.isAfter(today)) {
    next = addRecurrence(next, unit, every);
  }
  return next;
}
