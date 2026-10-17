import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../common/widgets.dart';
import '../../data/repositories.dart';
import '../../routing/app_router.dart';
import 'task_tile.dart';

class TaskListsScreen extends ConsumerWidget {
  const TaskListsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = ref.watch(taskListsProvider);
    final myTasks = ref.watch(myTasksProvider).value ?? const [];
    final counts = ref.watch(openTaskCountsProvider).value ?? const {};
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Aufgaben'),
        actions: const [SyncIndicator()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.playlist_add),
        label: const Text('Neue Liste'),
        onPressed: () => _createList(context, ref),
      ),
      body: AsyncBody(
        value: lists,
        builder: (lists) {
          if (lists.isEmpty) {
            return const EmptyHint(
              icon: Icons.checklist,
              text:
                  'Noch keine Listen.\nLege z. B. „Haushalt“ oder „Garten“ an.',
            );
          }
          final listNames = {for (final l in lists) l.id: l.name};
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              if (myTasks.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    'Mir zugewiesen',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                for (final t in myTasks)
                  TaskTile(task: t, listName: listNames[t.list]),
                const Divider(),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('Listen', style: theme.textTheme.titleSmall),
              ),
              for (final l in lists)
                ListTile(
                  leading: const Icon(Icons.checklist),
                  title: Text(l.name),
                  trailing: Badge.count(
                    count: counts[l.id] ?? 0,
                    isLabelVisible: (counts[l.id] ?? 0) > 0,
                    child: const Icon(Icons.chevron_right),
                  ),
                  onTap: () => context.go(AppRoutes.taskList(l.id)),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _createList(BuildContext context, WidgetRef ref) async {
    final name = await showTextInputDialog(
      context,
      title: 'Neue Aufgabenliste',
      hint: 'z. B. Haushalt',
      confirm: 'Anlegen',
    );
    if (name == null) return;
    final id = await ref.read(tasksRepositoryProvider).createList(name);
    if (context.mounted) context.go(AppRoutes.taskList(id));
  }
}
