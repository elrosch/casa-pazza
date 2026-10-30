import 'package:casa_pazza/src/data/auth.dart';
import 'package:casa_pazza/src/data/db/database.dart';
import 'package:casa_pazza/src/data/sync/sync_service.dart';
import 'package:casa_pazza/src/features/shopping/shopping_screen.dart';
import 'package:casa_pazza/src/features/shopping/shopping_suggestions.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

ShoppingItemRow item(
  String id,
  String name, {
  String quantity = '',
  int sort = 0,
  bool deleted = true,
}) => ShoppingItemRow(
  id: id,
  household: 'h',
  list: 's',
  name: name,
  quantity: quantity,
  checked: true,
  checkedBy: null,
  sort: sort,
  deleted: deleted,
  updated: '',
  dirty: false,
);

void main() {
  final history = buildSuggestions([
    item('1', 'Milch', quantity: '1 l', sort: 1),
    item('2', 'milch', quantity: '2 l', sort: 5),
    item('3', 'Milch', sort: 3),
    item('4', 'Äpfel', sort: 2),
    item('5', 'Brot', sort: 4),
    item('6', 'Brot', sort: 6),
  ]);

  test('most frequent first; the latest entry sets spelling and quantity', () {
    expect(history.map((s) => (s.name, s.quantity, s.count)), [
      ('milch', '2 l', 3),
      ('Brot', '', 2),
      ('Äpfel', '', 1),
    ]);
  });

  test('matching ignores case and umlauts and skips open items', () {
    expect(matchSuggestions(history, 'apf', openKeys: {}).map((s) => s.name), [
      'Äpfel',
    ]);
    expect(
      matchSuggestions(history, '', openKeys: {'brot'}).map((s) => s.name),
      ['milch', 'Äpfel'],
    );
  });

  testWidgets('tapping a frequent item adds it with its quantity', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.shoppingLists)
        .insert(
          ShoppingListsCompanion.insert(
            id: 's',
            household: 'h',
            name: 'Einkauf',
          ),
        );
    // Bought (and cleared) twice before.
    for (final id in ['a', 'b']) {
      await db
          .into(db.shoppingItems)
          .insert(
            ShoppingItemsCompanion.insert(
              id: id,
              household: 'h',
              list: 's',
              name: 'Milch',
              quantity: const Value('2 l'),
              checked: const Value(true),
              deleted: const Value(true),
            ),
          );
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          databaseProvider.overrideWithValue(db),
          connectivityProvider.overrideWithValue(const Stream.empty()),
        ],
        child: const MaterialApp(home: ShoppingScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Häufig:'), findsNothing, reason: 'only when focused');

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.text('Häufig:'), findsOneWidget);
    await tester.tap(find.text('Milch · 2 l'));
    await tester.pumpAndSettle();

    final open = await (db.select(
      db.shoppingItems,
    )..where((i) => i.deleted.not())).get();
    expect(open.map((i) => (i.name, i.quantity)), [('Milch', '2 l')]);
    // Now on the list, so no longer suggested.
    expect(find.text('Milch · 2 l'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
