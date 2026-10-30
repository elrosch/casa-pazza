import 'package:casa_pazza/src/data/auth.dart';
import 'package:casa_pazza/src/data/db/database.dart';
import 'package:casa_pazza/src/data/sync/sync_service.dart';
import 'package:casa_pazza/src/features/shopping/aisles.dart';
import 'package:casa_pazza/src/features/shopping/shopping_screen.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('aisles from item names', () {
    expect(aisleOf('Äpfel'), Aisle.produce);
    expect(aisleOf('Vollmilch'), Aisle.dairy);
    expect(aisleOf('Milchschokolade'), Aisle.sweets);
    expect(aisleOf('Hafermilch'), Aisle.drinks);
    expect(aisleOf('Hackfleisch'), Aisle.meat);
    expect(aisleOf('Eier'), Aisle.dairy);
    expect(aisleOf('Eis'), Aisle.frozen);
    expect(aisleOf('Reis'), Aisle.pantry, reason: '"eis" only as a word');
    expect(aisleOf('Olivenöl'), Aisle.pantry);
    expect(aisleOf('Klopapier'), Aisle.household);
    expect(aisleOf('Batterien AA'), Aisle.household);
    expect(aisleOf('Geschenkpapier'), Aisle.other);
  });

  testWidgets('shopping mode groups by aisle and keeps the screen on', (
    tester,
  ) async {
    final screenCalls = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('casa_pazza/screen'),
      (call) async {
        screenCalls.add(call.arguments);
        return null;
      },
    );

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
    var n = 0;
    for (final (name, checked) in [
      ('Zucker', false),
      ('Äpfel', false),
      ('Milch', false),
      ('Brot', true),
    ]) {
      await db
          .into(db.shoppingItems)
          .insert(
            ShoppingItemsCompanion.insert(
              id: 'i${n++}',
              household: 'h',
              list: 's',
              name: name,
              checked: Value(checked),
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

    double y(String text) => tester.getTopLeft(find.text(text)).dy;

    // Alphabetical by default, no headers, screen not kept on.
    expect(find.text('Obst & Gemüse'), findsNothing);
    expect(y('Äpfel'), lessThan(y('Milch')));
    expect(y('Milch'), lessThan(y('Zucker')));
    expect(screenCalls.where((c) => c == true), isEmpty);

    await tester.tap(find.byTooltip('Alphabetisch – tippen für Einkaufsmodus'));
    await tester.pumpAndSettle();
    expect(prefs.getBool('shopping_mode'), isTrue);
    expect(screenCalls.last, isTrue);
    // Store order: produce, dairy, pantry, then the cart.
    expect(y('Obst & Gemüse'), lessThan(y('Äpfel')));
    expect(y('Äpfel'), lessThan(y('Kühlregal')));
    expect(y('Milch'), lessThan(y('Vorrat & Konserven')));
    expect(y('Zucker'), lessThan(y('Im Wagen')));
    expect(y('Im Wagen'), lessThan(y('Brot')));

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(screenCalls.last, isFalse, reason: 'released when leaving');
  });
}
