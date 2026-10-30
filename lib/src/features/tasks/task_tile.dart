import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/widgets.dart';
import '../../data/db/database.dart';
import '../../data/recurrence.dart';
import '../../data/repositories.dart';
import '../../theme/app_theme.dart';
import 'task_editor.dart';

/// One task: priority color bar, checkbox, title with priority letter,
/// details. Open tasks can be swiped right to complete, left to postpone.
class TaskTile extends ConsumerWidget {
  const TaskTile({super.key, required this.task});

  final TaskRow task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final members = ref.watch(membersProvider).value ?? const [];
    final unit = RepeatUnit.fromName(task.repeatUnit);
    final due = task.due;

    final details = <InlineSpan>[
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

    final priorityColor = theme.priorityColors.of(task.priority);

    // The priority color marks the row: a bar on the left and the checkbox.
    final tile = DecoratedBox(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: priorityColor, width: 4)),
      ),
      child: ListTile(
        leading: Checkbox(
          value: task.done,
          side: BorderSide(color: priorityColor, width: 2),
          activeColor: priorityColor,
          onChanged: (_) =>
              task.done ? _reopen(context, ref) : _complete(context, ref),
        ),
        title: Text.rich(
          TextSpan(
            text: task.title,
            children: [
              // The letter repeats the color for color blindness and
              // bright sunlight; D (default) needs no extra mark.
              if (task.priority != 'D')
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: _PriorityBadge(
                    priority: task.priority,
                    color: priorityColor,
                  ),
                ),
            ],
          ),
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
      ),
    );

    if (task.done) return tile;
    return Dismissible(
      key: ValueKey('swipe-${task.id}'),
      // The action changes the task; the row itself stays (or moves).
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          await _complete(context, ref);
        } else {
          await _postpone(context, ref);
        }
        return false;
      },
      background: _SwipeBackground(
        color: theme.colorScheme.primaryContainer,
        foreground: theme.colorScheme.onPrimaryContainer,
        icon: Icons.check,
        label: 'Erledigt',
        alignment: Alignment.centerLeft,
      ),
      secondaryBackground: _SwipeBackground(
        color: theme.colorScheme.secondaryContainer,
        foreground: theme.colorScheme.onSecondaryContainer,
        icon: Icons.event_outlined,
        label: 'Morgen',
        alignment: Alignment.centerRight,
      ),
      child: tile,
    );
  }

  Future<void> _complete(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(tasksRepositoryProvider);
    final before = task;
    final next = await repo.complete(task);
    if (!context.mounted) return;
    showUndoSnackBar(
      context,
      next == null
          ? '„${task.title}" erledigt'
          : 'Erledigt – wieder fällig: ${formatDueDate(next)}',
      onUndo: () => repo.undoComplete(before),
    );
  }

  Future<void> _postpone(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(tasksRepositoryProvider);
    final before = task;
    await repo.postpone(task);
    if (!context.mounted) return;
    showUndoSnackBar(
      context,
      '„${task.title}" auf morgen verschoben',
      onUndo: () => repo.restoreTask(before),
    );
  }

  Future<void> _reopen(BuildContext context, WidgetRef ref) =>
      ref.read(tasksRepositoryProvider).reopen(task);

  static List<InlineSpan> _join(List<InlineSpan> parts) => [
    for (var i = 0; i < parts.length; i++) ...[
      if (i > 0) const TextSpan(text: ' · '),
      parts[i],
    ],
  ];
}

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.priority, required this.color});

  final String priority;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        priority,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.color,
    required this.foreground,
    required this.icon,
    required this.label,
    required this.alignment,
  });

  final Color color;
  final Color foreground;
  final IconData icon;
  final String label;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final children = [
      Icon(icon, color: foreground),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(color: foreground)),
    ];
    return Container(
      color: color,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: alignment == Alignment.centerLeft
            ? children
            : children.reversed.toList(),
      ),
    );
  }
}
