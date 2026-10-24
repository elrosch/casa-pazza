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
    final view = ref.watch(taskViewProvider);

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
          _TaskViewChips(view: view),
          Expanded(
            child: AsyncBody(
              value: tasks,
              builder: (tasks) {
                final now = DateTime.now();
                final allOpen = tasks.where((t) => !t.done).toList();
                final open = allOpen.where((t) => view.shows(t, now)).toList();
                // Tasks of the chosen type that are due after the range.
                final later = view.unlimited
                    ? 0
                    : allOpen.where(view.matchesType).length - open.length;
                final done = view.type == TaskType.recurring
                    ? const <TaskRow>[]
                    : tasks
                          .where((t) => t.done && view.matchesType(t))
                          .toList();
                return ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    if (open.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          _emptyText(view),
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
                              ? '1 weitere Aufgabe später'
                              : '$later weitere Aufgaben später',
                        ),
                        onTap: () => ref
                            .read(taskViewProvider.notifier)
                            .set(view.copyWith(unlimited: true)),
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

String _emptyText(TaskView view) {
  final what = switch (view.type) {
    TaskType.all => '',
    TaskType.oneOff => ' Einmaliges',
    TaskType.recurring => ' Wiederkehrendes',
  };
  if (view.unlimited) return 'Nichts$what zu tun.';
  if (view.until == null) return 'Heute nichts$what zu tun.';
  return 'Bis ${formatDueDate(view.until!)} nichts$what zu tun.';
}

/// The task view controls: a time range menu (today, a chosen date, all
/// dates) and which task types to show (one-off and/or recurring).
class _TaskViewChips extends ConsumerWidget {
  const _TaskViewChips({required this.view});

  final TaskView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(taskViewProvider.notifier);

    Future<void> pickDate() async {
      final today = DateUtils.dateOnly(DateTime.now());
      final picked = await showDatePicker(
        context: context,
        initialDate: view.until ?? today,
        firstDate: today,
        lastDate: DateTime(today.year + 2),
        helpText: 'Aufgaben anzeigen bis',
      );
      if (picked == null) return;
      notifier.set(
        view.copyWith(
          until: () => picked == today ? null : picked,
          unlimited: false,
        ),
      );
    }

    final rangeLabel = view.unlimited
        ? 'Alle Termine'
        : view.until == null
        ? 'Bis heute'
        : 'Bis ${formatDueDate(view.until!)}';

    // Two independent toggles; "all" means both are on. The last active one
    // cannot be switched off, which would always show an empty list.
    final showOneOff = view.type != TaskType.recurring;
    final showRecurring = view.type != TaskType.oneOff;
    void setTypes({required bool oneOff, required bool recurring}) {
      if (!oneOff && !recurring) return;
      notifier.set(
        view.copyWith(
          type: oneOff && recurring
              ? TaskType.all
              : oneOff
              ? TaskType.oneOff
              : TaskType.recurring,
        ),
      );
    }

    // Two rows, so all chips fit on a phone without scrolling sideways;
    // aligned to the start, as the tab's column centers its children.
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MenuAnchor(
              menuChildren: [
                MenuItemButton(
                  leadingIcon: const Icon(Icons.today_outlined),
                  onPressed: () => notifier.set(
                    view.copyWith(until: () => null, unlimited: false),
                  ),
                  child: const Text('Bis heute'),
                ),
                MenuItemButton(
                  leadingIcon: const Icon(Icons.edit_calendar_outlined),
                  onPressed: pickDate,
                  child: const Text('Bis Datum …'),
                ),
                MenuItemButton(
                  leadingIcon: const Icon(Icons.all_inclusive),
                  onPressed: () => notifier.set(view.copyWith(unlimited: true)),
                  child: const Text('Alle Termine'),
                ),
              ],
              builder: (context, controller, _) => InputChip(
                avatar: const Icon(Icons.event_outlined, size: 18),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(rangeLabel),
                    const Icon(Icons.arrow_drop_down, size: 18),
                  ],
                ),
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('Einmalig'),
                  showCheckmark: false,
                  selected: showOneOff,
                  onSelected: (on) =>
                      setTypes(oneOff: on, recurring: showRecurring),
                ),
                FilterChip(
                  avatar: const Icon(Icons.repeat, size: 18),
                  label: const Text('Wiederkehrend'),
                  showCheckmark: false,
                  selected: showRecurring,
                  onSelected: (on) =>
                      setTypes(oneOff: showOneOff, recurring: on),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
