import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/widgets.dart';
import '../../data/db/database.dart';
import '../../data/recurrence.dart';
import '../../data/repositories.dart';
import 'task_editor.dart';

class TaskTile extends ConsumerWidget {
  const TaskTile({super.key, required this.task, this.listName});

  final TaskRow task;

  /// Shown in the subtitle when tasks of several lists are mixed.
  final String? listName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final members = ref.watch(membersProvider).value ?? const [];
    final unit = RepeatUnit.fromName(task.repeatUnit);
    final due = task.due;

    final details = <InlineSpan>[
      if (listName != null) TextSpan(text: listName),
      if (due != null)
        TextSpan(
          text: formatDueDate(due),
          style: !task.done && isOverdue(due)
              ? TextStyle(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                )
              : null,
        ),
      if (unit != null)
        TextSpan(text: describeRecurrence(unit, task.repeatEvery)),
      if (task.assignee != null) TextSpan(text: members.nameOf(task.assignee)),
    ];

    return ListTile(
      leading: Checkbox(
        value: task.done,
        onChanged: (_) => _toggle(context, ref),
      ),
      title: Text(
        task.title,
        style: task.done
            ? TextStyle(
                decoration: TextDecoration.lineThrough,
                color: theme.colorScheme.outline,
              )
            : null,
      ),
      subtitle: details.isEmpty
          ? null
          : Text.rich(TextSpan(children: _join(details))),
      trailing: unit != null ? const Icon(Icons.repeat, size: 18) : null,
      onTap: () => showTaskEditor(context, listId: task.list, task: task),
    );
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(tasksRepositoryProvider);
    if (task.done) {
      await repo.reopen(task);
      return;
    }
    final next = await repo.complete(task);
    if (next != null && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Erledigt – wieder fällig: ${formatDueDate(next)}'),
          ),
        );
    }
  }

  static List<InlineSpan> _join(List<InlineSpan> parts) => [
    for (var i = 0; i < parts.length; i++) ...[
      if (i > 0) const TextSpan(text: ' · '),
      parts[i],
    ],
  ];
}
