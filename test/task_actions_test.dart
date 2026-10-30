import 'package:casa_pazza/src/data/auth.dart';
import 'package:casa_pazza/src/data/db/database.dart';
import 'package:casa_pazza/src/data/sync/sync_service.dart';
import 'package:casa_pazza/src/features/shopping/shopping_screen.dart';
import 'package:casa_pazza/src/features/tasks/tasks_screen.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;
  final today = DateUtils.dateOnly(DateTime.now());

  Future<void> pump(WidgetTester tester, Widget screen) async {
    await initializeDateFormatting('de');
    SharedPreferences.setMockInitialValues({'task_view_until': 'all'});
    final prefs = await SharedPreferences.getInstance();
    db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.taskLists)
        .insert(
          TaskListsCompanion.insert(id: 'l', household: 'h', name: 'To Do'),
        );
    await db
        .into(db.shoppingLists)
        .insert(
          ShoppingListsCompanion.insert(
            id: 's',
            household: 'h',
            name: 'Einkauf',
          ),
        );
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: 'once',
            household: 'h',
            list: 'l',
            title: 'Reifenwechsel',
            priority: const Value('A'),
            due: Value(today),
          ),
        );
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: 'plain',
            household: 'h',
            list: 'l',
            title: 'Fenster putzen',
            due: Value(today),
          ),
        );
    await db
        .into(db.shoppingItems)
        .insert(
          ShoppingItemsCompanion.insert(
            id: 'milk',
            household: 'h',
            list: 's',
            name: 'Milch',
          ),
        );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          databaseProvider.overrideWithValue(db),
          connectivityProvider.overrideWithValue(const Stream.empty()),
        ],
        child: MaterialApp(home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<TaskRow> taskById(String id) =>
      (db.select(db.tasks)..where((t) => t.id.equals(id))).getSingle();

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  testWidgets('priority letter only for A–C, left of the title', (
    tester,
  ) async {
    await pump(tester, const TasksScreen());
    expect(find.text('A'), findsOneWidget);
    expect(find.text('D'), findsNothing);
    final title = find.textContaining('Reifenwechsel', findRichText: true);
    expect(
      tester.getTopLeft(find.text('A')).dx,
      lessThan(tester.getTopLeft(title).dx + 40),
      reason: 'badge starts the title line',
    );
    expect(
      tester.getTopLeft(find.text('A')).dx,
      lessThan(tester.getCenter(title).dx),
    );
    await finish(tester);
  });

  testWidgets('swipe right completes, undo restores', (tester) async {
    await pump(tester, const TasksScreen());
    await tester.drag(
      find.textContaining('Reifenwechsel', findRichText: true),
      const Offset(500, 0),
    );
    await tester.pumpAndSettle();
    expect((await taskById('once')).done, isTrue);

    final logged = await db.select(db.completions).getSingle();
    expect(logged.title, 'Reifenwechsel');
    expect(logged.deleted, isFalse);

    await tester.tap(find.text('Rückgängig'));
    await tester.pumpAndSettle();
    final restored = await taskById('once');
    expect(restored.done, isFalse);
    expect(restored.doneBy, isNull);
    expect(
      (await db.select(db.completions).getSingle()).deleted,
      isTrue,
      reason: 'undo also removes the history entry',
    );
    await finish(tester);
  });

  testWidgets('swipe left postpones to tomorrow', (tester) async {
    await pump(tester, const TasksScreen());
    await tester.drag(find.text('Fenster putzen'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(
      (await taskById('plain')).due,
      DateTime(today.year, today.month, today.day + 1),
    );
    expect(find.textContaining('auf morgen verschoben'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('shopping: checking off and removing can be undone', (
    tester,
  ) async {
    await pump(tester, const ShoppingScreen());
    Future<ShoppingItemRow> milk() => (db.select(
      db.shoppingItems,
    )..where((i) => i.id.equals('milk'))).getSingle();

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect((await milk()).checked, isTrue);
    await tester.tap(find.text('Rückgängig'));
    await tester.pumpAndSettle();
    expect((await milk()).checked, isFalse);

    await tester.drag(find.text('Milch'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect((await milk()).deleted, isTrue);
    await tester.tap(find.text('Rückgängig'));
    await tester.pumpAndSettle();
    expect((await milk()).deleted, isFalse);
    expect(find.text('Milch'), findsOneWidget);
    await finish(tester);
  });
}
