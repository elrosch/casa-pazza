import 'package:casa_pazza/src/data/recurrence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('addRecurrence', () {
    test('adds days and weeks', () {
      final d = DateTime(2026, 10, 30);
      expect(addRecurrence(d, RepeatUnit.day, 3), DateTime(2026, 11, 2));
      expect(addRecurrence(d, RepeatUnit.week, 2), DateTime(2026, 11, 13));
    });

    test('clamps month ends', () {
      expect(
        addRecurrence(DateTime(2026, 1, 31), RepeatUnit.month, 1),
        DateTime(2026, 2, 28),
      );
      expect(
        addRecurrence(DateTime(2028, 2, 29), RepeatUnit.year, 1),
        DateTime(2029, 2, 28),
      );
    });
  });

  group('nextDueDate', () {
    final now = DateTime(2026, 10, 17, 18);

    test('moves on from the current due date', () {
      expect(
        nextDueDate(
          due: DateTime(2026, 10, 17),
          unit: RepeatUnit.week,
          every: 1,
          now: now,
        ),
        DateTime(2026, 10, 24),
      );
    });

    test('skips missed occurrences of overdue tasks', () {
      expect(
        nextDueDate(
          due: DateTime(2026, 9, 1),
          unit: RepeatUnit.week,
          every: 1,
          now: now,
        ),
        DateTime(2026, 10, 20),
      );
    });

    test('completing early keeps the schedule', () {
      expect(
        nextDueDate(
          due: DateTime(2026, 10, 20),
          unit: RepeatUnit.month,
          every: 1,
          now: now,
        ),
        DateTime(2026, 11, 20),
      );
    });

    test('starts from today without due date', () {
      expect(
        nextDueDate(due: null, unit: RepeatUnit.day, every: 2, now: now),
        DateTime(2026, 10, 19),
      );
    });
  });

  test('describeRecurrence', () {
    expect(describeRecurrence(RepeatUnit.week, 1), 'Wöchentlich');
    expect(describeRecurrence(RepeatUnit.week, 2), 'Alle 2 Wochen');
  });
}
