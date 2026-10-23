import 'package:casa_pazza/src/data/auth.dart';
import 'package:casa_pazza/src/data/db/database.dart';
import 'package:casa_pazza/src/data/sync/sync_service.dart';
import 'package:casa_pazza/src/data/task_filter.dart';
import 'package:casa_pazza/src/features/tasks/tasks_screen.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

TaskRow task({DateTime? due}) => TaskRow(
  id: 't',
  household: 'h',
  list: 'l',
  title: 'x',
  notes: '',
  due: due,
  repeatEvery: 0,
  done: false,
  deleted: false,
  updated: '',
  dirty: false,
);

Finder segment(String label) => find.descendant(
  of: find.byType(SegmentedButton<TaskFilter>),
  matching: find.text(label),
);

void main() {
  test('isDueByToday', () {
    final now = DateTime(2026, 10, 23, 20);
    expect(isDueByToday(task(), now), isTrue, reason: 'no date');
    expect(isDueByToday(task(due: DateTime(2026, 10, 23, 23)), now), isTrue);
    expect(isDueByToday(task(due: DateTime(2026, 10, 1)), now), isTrue);
    expect(isDueByToday(task(due: DateTime(2026, 10, 24)), now), isFalse);
  });

  testWidgets('tasks tab shows today by default and all on demand', (
    tester,
  ) async {
    await initializeDateFormatting('de');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final today = DateUtils.dateOnly(DateTime.now());
    await db
        .into(db.taskLists)
        .insert(
          TaskListsCompanion.insert(id: 'l', household: 'h', name: 'To Do'),
        );
    Future<void> add(
      String id,
      String title, {
      DateTime? due,
      bool done = false,
    }) => db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: id,
            household: 'h',
            list: 'l',
            title: title,
            due: Value(due),
            done: Value(done),
          ),
        );
    await add('1', 'Ohne Datum');
    await add('2', 'Heute fällig', due: today);
    await add('3', 'Überfällig', due: today.subtract(const Duration(days: 2)));
    await add('4', 'Nächste Woche', due: today.add(const Duration(days: 7)));
    await add('5', 'Schon erledigt', done: true);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          databaseProvider.overrideWithValue(db),
          connectivityProvider.overrideWithValue(const Stream.empty()),
        ],
        child: const MaterialApp(home: TasksScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ohne Datum'), findsOneWidget);
    expect(find.text('Heute fällig'), findsOneWidget);
    expect(find.text('Überfällig'), findsOneWidget);
    expect(find.text('Nächste Woche'), findsNothing);
    expect(find.text('1 weitere Aufgabe geplant'), findsOneWidget);

    await tester.tap(segment('Alle'));
    await tester.pumpAndSettle();
    expect(find.text('Nächste Woche'), findsOneWidget);
    expect(find.textContaining('weitere Aufgabe'), findsNothing);
    expect(prefs.getString('task_filter'), 'all', reason: 'choice is kept');

    await tester.tap(segment('Heute'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 weitere Aufgabe geplant'));
    await tester.pumpAndSettle();
    expect(find.text('Nächste Woche'), findsOneWidget);

    // Dispose the providers so drift's stream timers finish within the test.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
