import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/list_switcher.dart';
import '../../common/widgets.dart';
import '../../data/auth.dart';
import '../../data/db/database.dart';
import '../../data/repositories.dart';
import '../../data/task_filter.dart';
import '../voice/voice_input_sheet.dart';
import '../widget/home_widget_sync.dart';
import 'task_editor.dart';
import 'task_tile.dart';

/// Tasks tab: shows the selected task list directly.
class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = ref.watch(taskListsProvider);
    final selectedId = ref.watch(selectedListIdProvider('tasks'));

    return AsyncBody(
      value: lists,
      builder: (lists) {
        final list = resolveSelectedList(lists, selectedId, (l) => l.id);
        if (list == null) {
          // The default list appears with the first sync.
          return Scaffold(
            appBar: AppBar(actions: const [SyncIndicator()]),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        return _TaskListView(list: list, lists: lists);
      },
    );
  }
}

class _TaskListView extends ConsumerStatefulWidget {
  const _TaskListView({required this.list, required this.lists});

  final TaskListRow list;
  final List<TaskListRow> lists;

  @override
  ConsumerState<_TaskListView> createState() => _TaskListViewState();
}

class _TaskListViewState extends ConsumerState<_TaskListView> {
  bool _showDone = false;

  TasksRepository get _repo => ref.read(tasksRepositoryProvider);

  @override
  Widget build(BuildContext context) {
    final list = widget.list;
    final tasks = ref.watch(tasksOfListProvider(list.id));
    final filter = ref.watch(taskFilterProvider);

    // Taps on the home screen widget open the editor.
    final request = ref.watch(widgetRequestProvider);
    if (request is AddTaskRequest ||
        request is EditTaskRequest ||
        request is VoiceRequest) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openWidgetRequest());
    }

    return Scaffold(
      appBar: AppBar(
        title: ListSwitcherTitle(
          current: list.id,
          names: {for (final l in widget.lists) l.id: l.name},
          privateIds: {
            for (final l in widget.lists)
              if (l.isPrivate) l.id,
          },
          onSelect: ref.read(selectedListIdProvider('tasks').notifier).select,
        ),
        actions: [
          const SyncIndicator(),
          ListMenuButton(
            canDelete: widget.lists.length > 1,
            togglePrivateLabel: !_repo.canChangeVisibility(list)
                ? null
                : list.isPrivate
                ? 'Mit Haushalt teilen'
                : 'Privat machen',
            onSelected: _onMenu,
          ),
        ],
      ),
      body: Column(
        children: [
          QuickAddField(
            hint: 'Aufgabe hinzufügen',
            onAdd: (title) => _repo.saveTask(listId: list.id, title: title),
            // Browsers only allow the microphone over HTTPS: Android only.
            trailing: kIsWeb
                ? null
                : IconButton(
                    icon: const Icon(Icons.mic_none),
                    tooltip: 'Per Sprache hinzufügen',
                    onPressed: () => showVoiceInputSheet(context),
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SegmentedButton<TaskFilter>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: TaskFilter.today, label: Text('Heute')),
                ButtonSegment(value: TaskFilter.all, label: Text('Alle')),
              ],
              selected: {filter},
              onSelectionChanged: (s) =>
                  ref.read(taskFilterProvider.notifier).set(s.single),
            ),
          ),
          Expanded(
            child: AsyncBody(
              value: tasks,
              builder: (tasks) {
                final now = DateTime.now();
                final allOpen = tasks.where((t) => !t.done).toList();
                final open = filter == TaskFilter.today
                    ? allOpen.where((t) => isDueByToday(t, now)).toList()
                    : allOpen;
                final later = allOpen.length - open.length;
                final done = tasks.where((t) => t.done).toList();
                return ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    if (open.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          filter == TaskFilter.today
                              ? 'Heute nichts zu tun.'
                              : 'Nichts zu tun.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    for (final t in open) TaskTile(task: t),
                    if (later > 0)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.event_outlined),
                        title: Text(
                          later == 1
                              ? '1 weitere Aufgabe geplant'
                              : '$later weitere Aufgaben geplant',
                        ),
                        onTap: () => ref
                            .read(taskFilterProvider.notifier)
                            .set(TaskFilter.all),
                      ),
                    if (done.isNotEmpty)
                      ListTile(
                        dense: true,
                        title: Text('Erledigt (${done.length})'),
                        trailing: Icon(
                          _showDone ? Icons.expand_less : Icons.expand_more,
                        ),
                        onTap: () => setState(() => _showDone = !_showDone),
                      ),
                    if (_showDone)
                      for (final t in done) TaskTile(task: t),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openWidgetRequest() async {
    if (!mounted) return;
    final requests = ref.read(widgetRequestProvider.notifier);
    final WidgetRequest? request =
        requests.consume<AddTaskRequest>() ??
        requests.consume<EditTaskRequest>() ??
        requests.consume<VoiceRequest>();
    switch (request) {
      case AddTaskRequest():
        await showTaskEditor(context, listId: widget.list.id);
      case VoiceRequest():
        await showVoiceInputSheet(context);
      case EditTaskRequest(:final taskId):
        final db = ref.read(databaseProvider);
        final task = await (db.select(
          db.tasks,
        )..where((t) => t.id.equals(taskId))).getSingleOrNull();
        if (task != null && mounted) {
          await showTaskEditor(context, listId: task.list, task: task);
        }
      case _:
        break;
    }
  }

  Future<void> _onMenu(ListAction action) async {
    final list = widget.list;
    switch (action) {
      case ListAction.create:
        final result = await _showNewListDialog(context);
        if (result == null) return;
        final id = await _repo.createList(
          result.name,
          isPrivate: result.isPrivate,
        );
        ref.read(selectedListIdProvider('tasks').notifier).select(id);
      case ListAction.togglePrivate:
        if (!list.isPrivate) {
          final ok = await confirmDialog(
            context,
            title: 'Liste privat machen?',
            message:
                'Nur du siehst „${list.name}“ dann noch. Andere Mitglieder '
                'verlieren den Zugriff, Zuweisungen an sie werden entfernt.',
            confirm: 'Privat machen',
          );
          if (!ok) return;
        }
        await _repo.setListPrivate(list.id, !list.isPrivate);
      case ListAction.rename:
        final name = await showTextInputDialog(
          context,
          title: 'Liste umbenennen',
          initial: list.name,
        );
        if (name != null) await _repo.renameList(list.id, name);
      case ListAction.delete:
        final ok = await confirmDialog(
          context,
          title: 'Liste löschen?',
          message:
              '„${list.name}“ und alle Aufgaben darin werden für alle gelöscht.',
        );
        if (ok) await _repo.deleteList(list.id);
      case ListAction.clearChecked:
        break;
    }
  }
}

/// Asks for the name of a new task list and whether it is private.
Future<({String name, bool isPrivate})?> _showNewListDialog(
  BuildContext context,
) {
  final controller = TextEditingController();
  var isPrivate = false;
  return showDialog<({String name, bool isPrivate})>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        void submit() {
          final name = controller.text.trim();
          if (name.isEmpty) return;
          Navigator.of(context).pop((name: name, isPrivate: isPrivate));
        }

        return AlertDialog(
          title: const Text('Weitere Aufgabenliste'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'z. B. Garten'),
                onSubmitted: (_) => submit(),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: isPrivate,
                onChanged: (v) => setState(() => isPrivate = v ?? false),
                title: const Text('Privat'),
                subtitle: const Text('Nur für mich sichtbar'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Abbrechen'),
            ),
            FilledButton(onPressed: submit, child: const Text('Anlegen')),
          ],
        );
      },
    ),
  );
}
