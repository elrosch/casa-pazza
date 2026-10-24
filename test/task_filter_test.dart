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

TaskRow task({DateTime? due, String? repeatUnit}) => TaskRow(
  id: 't',
  household: 'h',
  list: 'l',
  title: 'x',
  notes: '',
  due: due,
  repeatUnit: repeatUnit,
  repeatEvery: 0,
  done: false,
  deleted: false,
  updated: '',
  dirty: false,
);

Finder chip(String label) => find.widgetWithText(FilterChip, label);

void main() {
  group('TaskView.shows', () {
    final now = DateTime(2026, 10, 23, 20);

    test('until today, all types (default)', () {
      const view = TaskView.today;
      expect(view.shows(task(), now), isTrue, reason: 'no date');
      expect(view.shows(task(due: DateTime(2026, 10, 23, 23)), now), isTrue);
      expect(view.shows(task(due: DateTime(2026, 10, 1)), now), isTrue);
      expect(view.shows(task(due: DateTime(2026, 10, 24)), now), isFalse);
    });

    test('until a chosen date', () {
      final view = TaskView(until: DateTime(2026, 10, 30));
      expect(view.shows(task(due: DateTime(2026, 10, 30)), now), isTrue);
      expect(view.shows(task(due: DateTime(2026, 10, 31)), now), isFalse);
    });

    test('type filters combine with the range', () {
      const recurringAll = TaskView(unlimited: true, type: TaskType.recurring);
      const oneOffToday = TaskView(type: TaskType.oneOff);
      final weekly = task(due: DateTime(2027, 1, 1), repeatUnit: 'week');
      final once = task(due: DateTime(2026, 10, 20));
      expect(recurringAll.shows(weekly, now), isTrue);
      expect(recurringAll.shows(once, now), isFalse);
      expect(oneOffToday.shows(once, now), isTrue);
      expect(oneOffToday.shows(task(repeatUnit: 'day'), now), isFalse);
    });
  });

  group('TaskViewNotifier', () {
    Future<ProviderContainer> container(Map<String, Object> prefs) async {
      SharedPreferences.setMockInitialValues(prefs);
      final c = ProviderContainer(
        overrides: [
          prefsProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('keeps the 1.1.0 "Alle" setting', () async {
      final c = await container({'task_filter': 'all'});
      expect(c.read(taskViewProvider), const TaskView(unlimited: true));
    });

    test('a past date falls back to today', () async {
      final c = await container({
        'task_view_until': '2020-01-01T00:00:00.000',
        'task_view_type': 'recurring',
      });
      expect(
        c.read(taskViewProvider),
        const TaskView(type: TaskType.recurring),
      );
    });

    test('settings are stored', () async {
      final c = await container({});
      c
          .read(taskViewProvider.notifier)
          .set(const TaskView(unlimited: true, type: TaskType.oneOff));
      final prefs = c.read(prefsProvider);
      expect(prefs.getString('task_view_until'), 'all');
      expect(prefs.getString('task_view_type'), 'oneOff');
    });
  });

  testWidgets('tasks tab: time range and type', (tester) async {
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
      String? repeatUnit,
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
            repeatUnit: Value(repeatUnit),
          ),
        );
    await add('1', 'Ohne Datum');
    await add('2', 'Heute fällig', due: today);
    await add('3', 'Überfällig', due: today.subtract(const Duration(days: 2)));
    await add('4', 'Nächste Woche', due: today.add(const Duration(days: 7)));
    await add('5', 'Schon erledigt', done: true);
    await add(
      '6',
      'Müll rausbringen',
      due: today.add(const Duration(days: 3)),
      repeatUnit: 'week',
    );

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

    // Chips start at the left edge (16 px padding), not centered.
    expect(tester.getTopLeft(find.text('Bis heute')).dx, lessThan(60));
    expect(tester.getTopLeft(chip('Einmalig')).dx, lessThan(30));

    // Default: until today, all types.
    expect(find.text('Ohne Datum'), findsOneWidget);
    expect(find.text('Heute fällig'), findsOneWidget);
    expect(find.text('Überfällig'), findsOneWidget);
    expect(find.text('Nächste Woche'), findsNothing);
    expect(find.text('Müll rausbringen'), findsNothing);
    expect(find.text('2 weitere Aufgaben später'), findsOneWidget);

    // Switch off one-off tasks: only recurring, nothing due today, one later.
    await tester.tap(chip('Einmalig'));
    await tester.pumpAndSettle();
    expect(find.text('Heute nichts Wiederkehrendes zu tun.'), findsOneWidget);
    expect(find.textContaining('Erledigt'), findsNothing);
    await tester.tap(find.text('1 weitere Aufgabe später'));
    await tester.pumpAndSettle();
    expect(find.text('Müll rausbringen'), findsOneWidget);
    expect(find.text('Ohne Datum'), findsNothing);
    expect(find.text('Alle Termine'), findsOneWidget);

    // The last active type cannot be switched off.
    await tester.tap(chip('Wiederkehrend'));
    await tester.pumpAndSettle();
    expect(find.text('Müll rausbringen'), findsOneWidget);

    // Only one-off tasks, all dates.
    await tester.tap(chip('Einmalig'));
    await tester.pumpAndSettle();
    await tester.tap(chip('Wiederkehrend'));
    await tester.pumpAndSettle();
    expect(find.text('Nächste Woche'), findsOneWidget);
    expect(find.text('Müll rausbringen'), findsNothing);

    // Back to "Bis heute" via the range menu.
    await tester.tap(find.text('Alle Termine'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bis heute').last);
    await tester.pumpAndSettle();
    expect(find.text('Nächste Woche'), findsNothing);
    expect(prefs.getString('task_view_until'), '');
    expect(prefs.getString('task_view_type'), 'oneOff');

    // Dispose the providers so drift's stream timers finish within the test.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
