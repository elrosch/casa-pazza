import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/list_switcher.dart';
import '../../common/widgets.dart';
import '../../data/auth.dart';
import '../../data/db/database.dart';
import '../../data/repositories.dart';
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

    // Taps on the home screen widget open the editor.
    if (ref.watch(widgetRequestProvider) != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openWidgetRequest());
    }

    return Scaffold(
      appBar: AppBar(
        title: ListSwitcherTitle(
          current: list.id,
          names: {for (final l in widget.lists) l.id: l.name},
          onSelect: ref.read(selectedListIdProvider('tasks').notifier).select,
        ),
        actions: [
          const SyncIndicator(),
          ListMenuButton(
            canDelete: widget.lists.length > 1,
            onSelected: _onMenu,
          ),
        ],
      ),
      body: Column(
        children: [
          QuickAddField(
            hint: 'Aufgabe hinzufügen',
            onAdd: (title) => _repo.saveTask(listId: list.id, title: title),
          ),
          const Divider(height: 1),
          Expanded(
            child: AsyncBody(
              value: tasks,
              builder: (tasks) {
                final open = tasks.where((t) => !t.done).toList();
                final done = tasks.where((t) => t.done).toList();
                return ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    if (open.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'Nichts zu tun.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    for (final t in open) TaskTile(task: t),
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
    final request = ref.read(widgetRequestProvider.notifier).consume();
    switch (request) {
      case AddTaskRequest():
        await showTaskEditor(context, listId: widget.list.id);
      case EditTaskRequest(:final taskId):
        final db = ref.read(databaseProvider);
        final task = await (db.select(
          db.tasks,
        )..where((t) => t.id.equals(taskId))).getSingleOrNull();
        if (task != null && mounted) {
          await showTaskEditor(context, listId: task.list, task: task);
        }
      case null:
        break;
    }
  }

  Future<void> _onMenu(ListAction action) async {
    final list = widget.list;
    switch (action) {
      case ListAction.create:
        final name = await showTextInputDialog(
          context,
          title: 'Weitere Aufgabenliste',
          hint: 'z. B. Garten',
          confirm: 'Anlegen',
        );
        if (name == null) return;
        final id = await _repo.createList(name);
        ref.read(selectedListIdProvider('tasks').notifier).select(id);
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
