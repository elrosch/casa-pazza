import 'package:casa_pazza/src/data/auth.dart';
import 'package:casa_pazza/src/data/db/database.dart';
import 'package:casa_pazza/src/data/repositories.dart';
import 'package:casa_pazza/src/data/sync/sync_service.dart';
import 'package:casa_pazza/src/features/shopping/shopping_screen.dart';
import 'package:drift/drift.dart' show BooleanExpressionOperators;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        databaseProvider.overrideWithValue(db),
        connectivityProvider.overrideWithValue(const Stream.empty()),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<List<ShoppingItemRow>> visible() =>
      (db.select(db.shoppingItems)..where((i) => i.deleted.not())).get();

  test('an open item is not added twice; a quantity is taken over', () async {
    final repo = container.read(shoppingRepositoryProvider);
    expect(await repo.addItem('s', 'Milch'), AddItemResult.added);
    expect(await repo.addItem('s', 'milch'), AddItemResult.alreadyOnList);
    expect(
      await repo.addItem('s', 'MILCH', quantity: '2 l'),
      AddItemResult.alreadyOnList,
    );
    final items = await visible();
    expect(items.map((i) => (i.name, i.quantity)), [('Milch', '2 l')]);
  });

  test('umlauts count like their spelled-out form in the key', () async {
    final repo = container.read(shoppingRepositoryProvider);
    await repo.addItem('s', 'Äpfel');
    expect(await repo.addItem('s', 'äpfel'), AddItemResult.alreadyOnList);
    expect(await visible(), hasLength(1));
  });

  test('a checked item becomes open again instead of a duplicate', () async {
    final repo = container.read(shoppingRepositoryProvider);
    await repo.addItem('s', 'Brot');
    await repo.toggle((await visible()).single);
    expect((await visible()).single.checked, isTrue);

    expect(await repo.addItem('s', 'Brot'), AddItemResult.reactivated);
    final items = await visible();
    expect(items, hasLength(1));
    expect(items.single.checked, isFalse);
  });

  test('other lists and removed items do not count', () async {
    final repo = container.read(shoppingRepositoryProvider);
    await repo.addItem('s', 'Salz');
    expect(await repo.addItem('other', 'Salz'), AddItemResult.added);
    await repo.deleteItem(
      (await visible()).firstWhere((i) => i.list == 's').id,
    );
    expect(await repo.addItem('s', 'Salz'), AddItemResult.added);
  });

  testWidgets('quick add shows a hint for duplicates', (tester) async {
    await db
        .into(db.shoppingLists)
        .insert(
          ShoppingListsCompanion.insert(
            id: 's',
            household: '',
            name: 'Einkauf',
          ),
        );
    await container.read(shoppingRepositoryProvider).addItem('s', 'Milch');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ShoppingScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'milch');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('„milch" steht schon auf der Liste'), findsOneWidget);
    expect(await visible(), hasLength(1));

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
