import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/auth.dart';

/// The daily digest settings stored on the user record (see the server's
/// reminders.go). [time] is "HH:MM" local time, empty when off.
@immutable
class ReminderSettings {
  const ReminderSettings({required this.time, required this.scope});

  factory ReminderSettings.of(AuthState auth) => ReminderSettings(
    time: auth.user?.get<String>('reminder_time', '') ?? '',
    scope: (auth.user?.get<String>('reminder_scope', '') ?? '').isEmpty
        ? 'mine'
        : auth.user!.get<String>('reminder_scope'),
  );

  final String time;

  /// "mine" (assigned to me) or "household" (all visible tasks).
  final String scope;

  bool get enabled => time.isNotEmpty;
}

String formatHm(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

/// Body for saving the settings. The UTC offset lets the server send at the
/// right local time; if today's time has already passed, today counts as
/// done so enabling at 20:00 does not send a digest right away.
@visibleForTesting
Map<String, dynamic> reminderUpdate(
  ReminderSettings settings, {
  required DateTime now,
}) {
  final passed =
      settings.enabled &&
      formatHm(now.hour, now.minute).compareTo(settings.time) >= 0;
  return {
    'reminder_time': settings.time,
    'reminder_scope': settings.scope,
    'reminder_tz_offset': now.timeZoneOffset.inMinutes,
    'reminder_last': passed ? _isoDate(now) : '',
  };
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Saves the digest settings on the server (needs a connection).
Future<void> saveReminderSettings(
  WidgetRef ref,
  ReminderSettings settings,
) async {
  final auth = ref.read(authProvider);
  await auth.pb
      .collection('users')
      .update(auth.userId, body: reminderUpdate(settings, now: DateTime.now()));
  await ref.read(authProvider.notifier).refreshUser();
}

/// Keeps the stored UTC offset current (daylight saving time, travel) while
/// the digest is enabled. Watched by the app widget.
final reminderOffsetSyncProvider = Provider<void>((ref) {
  final auth = ref.watch(authProvider);
  final settings = ReminderSettings.of(auth);
  if (!settings.enabled) return;
  final offset = DateTime.now().timeZoneOffset.inMinutes;
  final stored = auth.user?.get<num>('reminder_tz_offset', 0).toInt() ?? 0;
  if (offset == stored) return;
  Future.microtask(() async {
    try {
      await auth.pb
          .collection('users')
          .update(auth.userId, body: {'reminder_tz_offset': offset});
      await ref.read(authProvider.notifier).refreshUser();
    } catch (e) {
      debugPrint('reminder offset update skipped: $e');
    }
  });
});
