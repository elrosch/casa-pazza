import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth.dart';
import 'db/database.dart';

/// Which open tasks the tasks tab (and the home screen widget) shows.
enum TaskFilter {
  /// Due today, overdue or without a date. A recurring task that was just
  /// completed moves to its next date and leaves this view.
  today,

  /// All open tasks, including future ones.
  all,
}

final taskFilterProvider = NotifierProvider<TaskFilterNotifier, TaskFilter>(
  TaskFilterNotifier.new,
);

class TaskFilterNotifier extends Notifier<TaskFilter> {
  static const _key = 'task_filter';

  @override
  TaskFilter build() =>
      ref.read(prefsProvider).getString(_key) == TaskFilter.all.name
      ? TaskFilter.all
      : TaskFilter.today;

  void set(TaskFilter filter) {
    ref.read(prefsProvider).setString(_key, filter.name);
    state = filter;
  }
}

/// Whether an open task belongs into the "Heute" view on [now]'s day.
bool isDueByToday(TaskRow task, DateTime now) {
  final due = task.due;
  if (due == null) return true;
  final today = DateTime(now.year, now.month, now.day);
  return DateTime(due.year, due.month, due.day).compareTo(today) <= 0;
}
