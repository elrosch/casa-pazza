import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth.dart';
import 'db/database.dart';

/// Which kind of open tasks to show.
enum TaskType {
  all,

  /// Tasks without recurrence.
  oneOff,

  /// Recurring tasks, shown with their next due date.
  recurring,
}

/// What the tasks tab (and the home screen widget) shows: a time range and a
/// task type, chosen independently.
@immutable
class TaskView {
  const TaskView({
    this.until,
    this.unlimited = false,
    this.type = TaskType.all,
  });

  /// Default: due by today (or overdue, or without a date), all types.
  static const today = TaskView();

  /// Last day shown; null means "today" and moves along with the date.
  /// Ignored when [unlimited].
  final DateTime? until;

  /// Show tasks regardless of their due date.
  final bool unlimited;

  final TaskType type;

  /// The last day shown on [now]'s day.
  DateTime untilDate(DateTime now) => until ?? _dateOnly(now);

  /// Whether [task] passes the type filter only (the time range aside).
  bool matchesType(TaskRow task) => switch (type) {
    TaskType.all => true,
    TaskType.oneOff => task.repeatUnit == null,
    TaskType.recurring => task.repeatUnit != null,
  };

  bool shows(TaskRow task, DateTime now) =>
      matchesType(task) && (unlimited || isDueBy(task, untilDate(now)));

  TaskView copyWith({
    DateTime? Function()? until,
    bool? unlimited,
    TaskType? type,
  }) => TaskView(
    until: until == null ? this.until : until(),
    unlimited: unlimited ?? this.unlimited,
    type: type ?? this.type,
  );

  @override
  bool operator ==(Object other) =>
      other is TaskView &&
      other.until == until &&
      other.unlimited == unlimited &&
      other.type == type;

  @override
  int get hashCode => Object.hash(until, unlimited, type);
}

final taskViewProvider = NotifierProvider<TaskViewNotifier, TaskView>(
  TaskViewNotifier.new,
);

class TaskViewNotifier extends Notifier<TaskView> {
  static const _untilKey = 'task_view_until'; // '', 'all' or an ISO date
  static const _typeKey = 'task_view_type';
  // Settings of earlier versions: 'task_filter' ("today"/"all", 1.1.0).
  static const _legacyKey = 'task_filter';

  @override
  TaskView build() {
    final prefs = ref.read(prefsProvider);
    final type =
        TaskType.values
            .where((t) => t.name == prefs.getString(_typeKey))
            .firstOrNull ??
        TaskType.all;
    final stored = prefs.getString(_untilKey);
    if (stored == 'all' ||
        (stored == null && prefs.getString(_legacyKey) == 'all')) {
      return TaskView(unlimited: true, type: type);
    }
    var until = DateTime.tryParse(stored ?? '');
    // A chosen date that has passed falls back to "today".
    if (until != null && until.isBefore(_dateOnly(DateTime.now()))) {
      until = null;
    }
    return TaskView(until: until, type: type);
  }

  void set(TaskView view) {
    final prefs = ref.read(prefsProvider);
    prefs.setString(
      _untilKey,
      view.unlimited ? 'all' : (view.until?.toIso8601String() ?? ''),
    );
    prefs.setString(_typeKey, view.type.name);
    state = view;
  }
}

/// Whether an open task is due on or before [limit]'s day (or has no date).
bool isDueBy(TaskRow task, DateTime limit) {
  final due = task.due;
  if (due == null) return true;
  return _dateOnly(due).compareTo(_dateOnly(limit)) <= 0;
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
