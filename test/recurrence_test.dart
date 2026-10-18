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

  group('nextDueDate counts from the completion day', () {
    final now = DateTime(2026, 10, 17, 18);
    DateTime next(RepeatUnit unit, int every) =>
        nextDueDate(unit: unit, every: every, now: now);

    test('every 3 days, done today', () {
      expect(next(RepeatUnit.day, 3), DateTime(2026, 10, 20));
    });

    test('weekly and monthly from today', () {
      expect(next(RepeatUnit.week, 1), DateTime(2026, 10, 24));
      expect(next(RepeatUnit.month, 1), DateTime(2026, 11, 17));
    });

    test('ignores the time of day', () {
      expect(
        nextDueDate(
          unit: RepeatUnit.day,
          every: 1,
          now: DateTime(2026, 10, 17, 23, 59),
        ),
        DateTime(2026, 10, 18),
      );
    });
  });

  test('describeRecurrence', () {
    expect(describeRecurrence(RepeatUnit.week, 1), 'Wöchentlich');
    expect(describeRecurrence(RepeatUnit.week, 2), 'Alle 2 Wochen');
  });
}
