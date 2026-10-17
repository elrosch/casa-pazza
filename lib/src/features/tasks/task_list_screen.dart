import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../common/widgets.dart';
import '../../data/repositories.dart';
import '../../routing/app_router.dart';
import 'task_editor.dart';
import 'task_tile.dart';

class TaskListScreen extends ConsumerStatefulWidget {
  const TaskListScreen({super.key, required this.listId});

  final String listId;

  @override
  ConsumerState<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends ConsumerState<TaskListScreen> {
  bool _showDone = false;

  @override
  Widget build(BuildContext context) {
    final list = ref
        .watch(taskListsProvider)
        .value
        ?.where((l) => l.id == widget.listId)
        .firstOrNull;
    final tasks = ref.watch(tasksOfListProvider(widget.listId));

    return Scaffold(
      appBar: AppBar(
        title: Text(list?.name ?? ''),
        actions: [
          const SyncIndicator(),
          PopupMenuButton<String>(
            onSelected: (action) => switch (action) {
              'rename' => _rename(list?.name ?? ''),
              'delete' => _delete(list?.name ?? ''),
              _ => null,
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Umbenennen')),
              PopupMenuItem(value: 'delete', child: Text('Liste löschen')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Aufgabe hinzufügen',
        onPressed: () => showTaskEditor(context, listId: widget.listId),
        child: const Icon(Icons.add),
      ),
      body: AsyncBody(
        value: tasks,
        builder: (tasks) {
          final open = tasks.where((t) => !t.done).toList();
          final done = tasks.where((t) => t.done).toList();
          if (tasks.isEmpty) {
            return const EmptyHint(
              icon: Icons.task_alt,
              text: 'Keine Aufgaben. Tippe auf +, um eine hinzuzufügen.',
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              if (open.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Alles erledigt 🎉', textAlign: TextAlign.center),
                ),
              for (final t in open) TaskTile(task: t),
              if (done.isNotEmpty)
                ListTile(
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
    );
  }

  Future<void> _rename(String current) async {
    final name = await showTextInputDialog(
      context,
      title: 'Liste umbenennen',
      initial: current,
    );
    if (name != null) {
      await ref.read(tasksRepositoryProvider).renameList(widget.listId, name);
    }
  }

  Future<void> _delete(String name) async {
    final ok = await confirmDialog(
      context,
      title: 'Liste löschen?',
      message: '„$name“ und alle Aufgaben darin werden für alle gelöscht.',
    );
    if (!ok) return;
    await ref.read(tasksRepositoryProvider).deleteList(widget.listId);
    if (mounted) context.go(AppRoutes.tasks);
  }
}
