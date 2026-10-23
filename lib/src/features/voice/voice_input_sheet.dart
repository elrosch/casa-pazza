import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/widgets.dart';
import '../../data/auth.dart';
import '../../data/repositories.dart';
import '../shopping/shopping_screen.dart' show parseItemInput;
import 'speech_recognizer.dart';
import 'voice_command.dart';

/// Listens for a sentence like "Salz auf die Einkaufsliste" or "Neues Todo
/// für Elias: Wäsche waschen", shows the understood item for a quick check
/// and adds it to the current task or shopping list.
Future<void> showVoiceInputSheet(BuildContext context) async {
  final added = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => const VoiceInputSheet(),
  );
  if (added != null && context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(added)));
  }
}

enum _Kind { task, shopping }

class VoiceInputSheet extends ConsumerStatefulWidget {
  const VoiceInputSheet({super.key});

  @override
  ConsumerState<VoiceInputSheet> createState() => _VoiceInputSheetState();
}

class _VoiceInputSheetState extends ConsumerState<VoiceInputSheet> {
  final _text = TextEditingController();
  late final _recognizer = ref.read(speechRecognizerProvider);
  var _listening = false;
  var _heard = '';
  String? _error;

  // Result, editable before adding.
  _Kind? _kind;
  String? _assignee;
  DateTime? _due;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void dispose() {
    _recognizer.stop();
    _text.dispose();
    super.dispose();
  }

  Future<void> _listen() async {
    setState(() {
      _listening = true;
      _heard = '';
      _error = null;
      _kind = null;
    });
    final ok = await _recognizer.start(
      onText: (text, isFinal) {
        if (!mounted) return;
        setState(() => _heard = text);
        if (isFinal) unawaited(_understand(text));
      },
      onError: (message) {
        if (!mounted) return;
        setState(() {
          _listening = false;
          _error = message;
        });
      },
    );
    if (!ok && mounted) {
      setState(() {
        _listening = false;
        _error = 'Spracherkennung ist auf diesem Gerät nicht verfügbar.';
      });
    }
  }

  Future<void> _understand(String sentence) async {
    // Members may still be loading right after a cold start (shortcut).
    final members = await ref.read(membersProvider.future);
    if (!mounted) return;
    final command = parseVoiceCommand(
      sentence,
      members: members,
      myId: ref.read(authProvider).userId,
      now: DateTime.now(),
    );
    setState(() {
      _listening = false;
      switch (command) {
        case ShoppingVoiceCommand(:final items):
          _kind = _Kind.shopping;
          _text.text = items
              .map((i) => [i.quantity, i.name].where((s) => s.isNotEmpty))
              .map((parts) => parts.join(' '))
              .join(', ');
        case TaskVoiceCommand(:final title, :final assignee, :final due):
          _kind = _Kind.task;
          _text.text = title;
          _assignee = assignee;
          _due = due;
        case null:
          _error = 'Nichts verstanden.';
      }
    });
  }

  void _switchKind(_Kind kind) => setState(() => _kind = kind);

  Future<void> _add() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    final String message;
    if (_kind == _Kind.shopping) {
      final lists = await ref.read(shoppingListsProvider.future);
      final list = resolveSelectedList(
        lists,
        ref.read(selectedListIdProvider('shopping')),
        (l) => l.id,
      );
      if (list == null) return;
      final repo = ref.read(shoppingRepositoryProvider);
      final items = text.split(RegExp(r'\s*,\s*')).where((s) => s.isNotEmpty);
      for (final item in items) {
        final (name, quantity) = parseItemInput(item);
        await repo.addItem(list.id, name, quantity: quantity);
      }
      message = 'Auf „${list.name}“: ${items.join(', ')}';
    } else {
      final list = await _taskList();
      if (list == null) return;
      await ref
          .read(tasksRepositoryProvider)
          .saveTask(
            listId: list.id,
            title: text,
            assignee: _assignee,
            due: _due,
          );
      message = 'Aufgabe „$text“ in „${list.name}“';
    }
    if (mounted) Navigator.of(context).pop(message);
  }

  /// The selected task list; a task for someone else goes into a shared
  /// list, since private lists cannot have other assignees.
  Future<({String id, String name})?> _taskList() async {
    final lists = await ref.read(taskListsProvider.future);
    final selected = resolveSelectedList(
      lists,
      ref.read(selectedListIdProvider('tasks')),
      (l) => l.id,
    );
    final me = ref.read(authProvider).userId;
    final forOthers = _assignee != null && _assignee != me;
    final list = selected != null && (!selected.isPrivate || !forOthers)
        ? selected
        : lists.where((l) => !l.isPrivate).firstOrNull;
    return list == null ? null : (id: list.id, name: list.name);
  }

  @override
  Widget build(BuildContext context) {
    // Keep the data needed for parsing and adding loaded while open.
    ref.watch(membersProvider);
    ref.watch(taskListsProvider);
    ref.watch(shoppingListsProvider);
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_kind == null) ...[
              Icon(
                _listening ? Icons.mic : Icons.mic_none,
                size: 56,
                color: _listening
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text(
                _error ??
                    (_heard.isEmpty
                        ? 'Sag z. B. „Salz auf die Einkaufsliste“ oder '
                              '„Wäsche waschen für Elias morgen“'
                        : _heard),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              if (_listening)
                OutlinedButton(
                  onPressed: _recognizer.stop,
                  child: const Text('Fertig'),
                )
              else
                FilledButton.icon(
                  icon: const Icon(Icons.mic),
                  label: const Text('Nochmal'),
                  onPressed: _listen,
                ),
            ] else
              ..._result(theme),
          ],
        ),
      ),
    );
  }

  List<Widget> _result(ThemeData theme) {
    final members = ref.watch(membersProvider).value ?? const [];
    final me = ref.watch(authProvider.select((a) => a.userId));
    return [
      SegmentedButton<_Kind>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: _Kind.task, label: Text('Aufgabe')),
          ButtonSegment(value: _Kind.shopping, label: Text('Einkauf')),
        ],
        selected: {_kind!},
        onSelectionChanged: (s) => _switchKind(s.single),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _text,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: _kind == _Kind.task ? 'Aufgabe' : 'Artikel',
          helperText: _kind == _Kind.shopping
              ? 'Mehrere Artikel mit Komma trennen'
              : null,
        ),
      ),
      if (_kind == _Kind.task) ...[
        const SizedBox(height: 16),
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
                label: Text(m.id == me ? 'Ich' : members.nameOf(m.id)),
                selected: _assignee == m.id,
                onSelected: (_) => setState(() => _assignee = m.id),
              ),
          ],
        ),
        if (_due != null) ...[
          const SizedBox(height: 8),
          InputChip(
            avatar: const Icon(Icons.event_outlined, size: 18),
            label: Text('Fällig: ${formatDueDate(_due!)}'),
            onDeleted: () => setState(() => _due = null),
          ),
        ],
      ],
      const SizedBox(height: 20),
      Row(
        children: [
          TextButton.icon(
            icon: const Icon(Icons.mic),
            label: const Text('Nochmal'),
            onPressed: _listen,
          ),
          const Spacer(),
          FilledButton(onPressed: _add, child: const Text('Hinzufügen')),
        ],
      ),
    ];
  }
}
