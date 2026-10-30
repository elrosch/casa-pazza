import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../common/widgets.dart';
import '../../data/auth.dart';
import '../../data/db/database.dart';
import '../../data/repositories.dart';

/// Completions of the last 90 days, newest first.
final recentCompletionsProvider = StreamProvider<List<CompletionRow>>((ref) {
  final db = ref.watch(databaseProvider);
  final since = DateTime.now().subtract(const Duration(days: 90));
  return (db.select(db.completions)
        ..where((c) => c.deleted.not() & c.doneAt.isBiggerOrEqualValue(since))
        ..orderBy([(c) => OrderingTerm.desc(c.doneAt)]))
      .watch();
});

/// Who did what and when: completions per person over the last 30 days and
/// a day-by-day list, filterable by person.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  String? _person;

  @override
  Widget build(BuildContext context) {
    final completions = ref.watch(recentCompletionsProvider);
    final members = ref.watch(membersProvider).value ?? const [];
    final me = ref.watch(authProvider.select((a) => a.userId));
    final lists = {
      for (final l
          in ref.watch(taskListsProvider).value ?? const <TaskListRow>[])
        l.id: l.name,
    };
    final theme = Theme.of(context);

    String nameOf(String id) => id == me ? 'Ich' : members.nameOf(id);

    return Scaffold(
      appBar: AppBar(title: const Text('Verlauf')),
      body: AsyncBody(
        value: completions,
        builder: (all) {
          final monthAgo = DateTime.now().subtract(const Duration(days: 30));
          final counts = <String, int>{};
          for (final c in all.where((c) => c.doneAt.isAfter(monthAgo))) {
            counts[c.user] = (counts[c.user] ?? 0) + 1;
          }
          final shown = _person == null
              ? all
              : all.where((c) => c.user == _person).toList();

          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'Erledigt in den letzten 30 Tagen',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    ChoiceChip(
                      label: Text(
                        'Alle · ${counts.values.fold(0, (a, b) => a + b)}',
                      ),
                      selected: _person == null,
                      onSelected: (_) => setState(() => _person = null),
                    ),
                    for (final m in members)
                      ChoiceChip(
                        label: Text('${nameOf(m.id)} · ${counts[m.id] ?? 0}'),
                        selected: _person == m.id,
                        onSelected: (_) => setState(() => _person = m.id),
                      ),
                  ],
                ),
              ),
              if (shown.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Noch nichts erledigt.',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final (i, c) in shown.indexed) ...[
                if (i == 0 ||
                    !DateUtils.isSameDay(shown[i - 1].doneAt, c.doneAt))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      formatDueDate(c.doneAt),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.task_alt),
                  title: Text(c.title),
                  subtitle: Text(
                    [
                      nameOf(c.user),
                      DateFormat('HH:mm').format(c.doneAt),
                      if (lists[c.list] != null) lists[c.list]!,
                    ].join(' · '),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
