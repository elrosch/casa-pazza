import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/widgets.dart';
import '../../data/auth.dart';
import '../../data/db/database.dart';
import '../../data/recurrence.dart';
import '../../data/repositories.dart';

/// Opens the create/edit sheet. Without [task] a new task is added to [listId].
Future<void> showTaskEditor(
  BuildContext context, {
  required String listId,
  TaskRow? task,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => TaskEditor(listId: listId, task: task),
  );
}

class TaskEditor extends ConsumerStatefulWidget {
  const TaskEditor({super.key, required this.listId, this.task});

  final String listId;
  final TaskRow? task;

  @override
  ConsumerState<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends ConsumerState<TaskEditor> {
  late final _title = TextEditingController(text: widget.task?.title);
  late final _notes = TextEditingController(text: widget.task?.notes);
  late String? _assignee = widget.task?.assignee;
  late DateTime? _due = widget.task?.due;
  late RepeatUnit? _repeatUnit = RepeatUnit.fromName(widget.task?.repeatUnit);
  late int _repeatEvery = (widget.task?.repeatEvery ?? 0) < 1
      ? 1
      : widget.task!.repeatEvery;

  bool get _isNew => widget.task == null;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _due = picked);
  }

  Future<void> _save() async {
    final privateList =
        ref
            .read(taskListsProvider)
            .value
            ?.where((l) => l.id == widget.listId)
            .firstOrNull
            ?.isPrivate ??
        false;
    if (_title.text.trim().isEmpty) return;
    // Recurring tasks need a start date to count from.
    final due = _repeatUnit != null && _due == null
        ? DateUtils.dateOnly(DateTime.now())
        : _due;
    await ref
        .read(tasksRepositoryProvider)
        .saveTask(
          id: widget.task?.id,
          listId: widget.listId,
          title: _title.text,
          notes: _notes.text,
          // Private lists only allow the owner as assignee.
          assignee: privateList && _assignee != ref.read(authProvider).userId
              ? null
              : _assignee,
          due: due,
          repeatUnit: _repeatUnit,
          repeatEvery: _repeatEvery,
        );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'Aufgabe löschen?',
      message: '„${widget.task!.title}“ wird für alle gelöscht.',
    );
    if (!ok) return;
    await ref.read(tasksRepositoryProvider).deleteTask(widget.task!.id);
    if (mounted) Navigator.of(context).pop();
  }

  bool _isInPrivateList() =>
      ref
          .watch(taskListsProvider)
          .value
          ?.where((l) => l.id == widget.listId)
          .firstOrNull
          ?.isPrivate ??
      false;

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(membersProvider).value ?? const [];
    final me = ref.watch(authProvider.select((a) => a.userId));
    final theme = Theme.of(context);
    final privateList = _isInPrivateList();

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isNew ? 'Neue Aufgabe' : 'Aufgabe bearbeiten',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              autofocus: _isNew,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Was ist zu tun?'),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Notizen'),
            ),
            // Private lists are only visible to their owner: no assignment.
            if (!privateList) ...[
              const SizedBox(height: 20),
              Text('Zuständig', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  ChoiceChip(
                    label: const Text('Niemand'),
                    selected: _assignee == null,
                    onSelected: (_) => setState(() => _assignee = null),
                  ),
                  for (final m in members)
                    ChoiceChip(
                      avatar: const Icon(Icons.person_outline, size: 18),
                      label: Text(m.id == me ? 'Ich' : members.nameOf(m.id)),
                      selected: _assignee == m.id,
                      onSelected: (_) => setState(() => _assignee = m.id),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event_outlined),
                    label: Text(
                      _due == null ? 'Fällig am …' : formatDueDate(_due!),
                    ),
                    onPressed: _pickDue,
                  ),
                ),
                if (_due != null)
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Datum entfernen',
                    onPressed: () => setState(() => _due = null),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.repeat),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<RepeatUnit?>(
                    isExpanded: true,
                    value: _repeatUnit,
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Einmalig'),
                      ),
                      for (final u in RepeatUnit.values)
                        DropdownMenuItem(value: u, child: Text(u.adverb)),
                    ],
                    onChanged: (u) => setState(() => _repeatUnit = u),
                  ),
                ),
              ],
            ),
            if (_repeatUnit != null)
              Row(
                children: [
                  const SizedBox(width: 36),
                  Text('Alle'),
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: _repeatEvery > 1
                        ? () => setState(() => _repeatEvery--)
                        : null,
                  ),
                  Text('$_repeatEvery', style: theme.textTheme.titleMedium),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => setState(() => _repeatEvery++),
                  ),
                  Text(
                    _repeatEvery == 1
                        ? _repeatUnit!.singular
                        : _repeatUnit!.plural,
                  ),
                ],
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (!_isNew)
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Löschen'),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    onPressed: _delete,
                  ),
                const Spacer(),
                FilledButton(onPressed: _save, child: const Text('Speichern')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
