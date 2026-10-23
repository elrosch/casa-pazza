import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/sync/sync_service.dart';

/// Renders an [AsyncValue] with default loading and error states.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({super.key, required this.value, required this.builder});

  final AsyncValue<T> value;
  final Widget Function(T data) builder;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Fehler: $error')),
    );
  }
}

/// Centered hint for empty lists.
class EmptyHint extends StatelessWidget {
  const EmptyHint({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outline;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: color),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small cloud icon in the app bar showing the sync state.
class SyncIndicator extends ConsumerWidget {
  const SyncIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider);
    final (icon, tooltip) = switch (status.phase) {
      SyncPhase.syncing => (Icons.cloud_sync_outlined, 'Synchronisiere …'),
      SyncPhase.offline => (
        Icons.cloud_off_outlined,
        'Offline – Änderungen werden später übertragen',
      ),
      SyncPhase.error => (Icons.error_outline, status.message ?? 'Sync-Fehler'),
      SyncPhase.idle => (Icons.cloud_done_outlined, 'Synchronisiert'),
    };
    return IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: () {
        ref.read(syncServiceProvider)?.syncNow();
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(tooltip)));
      },
    );
  }
}

/// Asks for a single line of text, e.g. a list name.
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
  String confirm = 'Speichern',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) {
      void submit() {
        final text = controller.text.trim();
        if (text.isNotEmpty) Navigator.of(context).pop(text);
      }

      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (_) => submit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(onPressed: submit, child: Text(confirm)),
        ],
      );
    },
  );
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirm = 'Löschen',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// "Heute", "Morgen", "Gestern" or e.g. "Fr., 24.10.".
String formatDueDate(DateTime due, {DateTime? now}) {
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  final days = DateUtils.dateOnly(due).difference(today).inDays;
  return switch (days) {
    0 => 'Heute',
    1 => 'Morgen',
    -1 => 'Gestern',
    _ => DateFormat('E, d.M.', 'de').format(due),
  };
}

bool isOverdue(DateTime due, {DateTime? now}) =>
    DateUtils.dateOnly(due).isBefore(DateUtils.dateOnly(now ?? DateTime.now()));

/// Text field at the top of a list for adding entries with the keyboard.
class QuickAddField extends StatefulWidget {
  const QuickAddField({
    super.key,
    required this.hint,
    required this.onAdd,
    this.trailing,
  });

  final String hint;
  final ValueChanged<String> onAdd;

  /// Optional action next to the field, e.g. a scan button.
  final Widget? trailing;

  @override
  State<QuickAddField> createState() => _QuickAddFieldState();
}

class _QuickAddFieldState extends State<QuickAddField> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    // Keep the keyboard open for the next entry.
    _focus.requestFocus();
    widget.onAdd(text);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          hintText: widget.hint,
          prefixIcon: const Icon(Icons.add),
          suffixIcon: widget.trailing,
          border: InputBorder.none,
        ),
        onSubmitted: (_) => _submit(),
      ),
    );
  }
}
