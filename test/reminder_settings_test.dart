import 'package:casa_pazza/src/features/reminders/reminder_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('enabling before the time keeps today open', () {
    final body = reminderUpdate(
      const ReminderSettings(time: '08:00', scope: 'mine'),
      now: DateTime(2026, 10, 30, 7, 30),
    );
    expect(body['reminder_time'], '08:00');
    expect(body['reminder_scope'], 'mine');
    expect(body['reminder_last'], '');
    expect(body['reminder_tz_offset'], isA<int>());
  });

  test('enabling after the time does not send right away', () {
    final body = reminderUpdate(
      const ReminderSettings(time: '08:00', scope: 'household'),
      now: DateTime(2026, 10, 30, 20, 0),
    );
    expect(body['reminder_last'], '2026-10-30');
  });

  test('switching off clears the time', () {
    final body = reminderUpdate(
      const ReminderSettings(time: '', scope: 'mine'),
      now: DateTime(2026, 10, 30, 20, 0),
    );
    expect(body['reminder_time'], '');
    expect(body['reminder_last'], '');
  });

  test('formatHm pads', () => expect(formatHm(7, 5), '07:05'));
}
