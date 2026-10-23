import 'dart:convert';

import 'package:casa_pazza/src/data/auth.dart';
import 'package:casa_pazza/src/data/db/database.dart';
import 'package:casa_pazza/src/data/sync/sync_service.dart';
import 'package:casa_pazza/src/features/shopping/product_lookup.dart';
import 'package:casa_pazza/src/features/shopping/scanned_product_sheet.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;

  Future<void> pumpSheet(
    WidgetTester tester,
    Future<http.Response> Function(http.Request) handler,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          databaseProvider.overrideWithValue(db),
          connectivityProvider.overrideWithValue(const Stream.empty()),
          productLookupProvider.overrideWithValue(
            ProductLookup(MockClient(handler)),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ScannedProductSheet(
              listId: 'list1',
              barcode: '4008400401621',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('prefills a found product and adds it', (tester) async {
    await pumpSheet(
      tester,
      (_) async => http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'status': 1,
            'product': {
              'product_name': 'Nutella',
              'brands': 'Nutella',
              'quantity': '450 g',
            },
          }),
        ),
        200,
      ),
    );

    expect(find.text('Nutella'), findsOneWidget);
    expect(find.text('450 g'), findsOneWidget);
    expect(find.text('Daten: Open Food Facts (ODbL)'), findsOneWidget);

    await tester.tap(find.text('Hinzufügen'));
    await tester.pumpAndSettle();
    final items = await db.select(db.shoppingItems).get();
    expect(items.single.name, 'Nutella');
    expect(items.single.quantity, '450 g');
    expect(items.single.list, 'list1');
  });

  testWidgets('asks for a name when the product is unknown', (tester) async {
    await pumpSheet(tester, (_) async => http.Response('{"status":0}', 200));
    expect(find.textContaining('nicht in Open Food Facts gefunden'), findsOne);

    await tester.enterText(find.widgetWithText(TextField, 'Artikel'), 'Senf');
    await tester.tap(find.text('Hinzufügen'));
    await tester.pumpAndSettle();
    expect((await db.select(db.shoppingItems).get()).single.name, 'Senf');
  });

  testWidgets('works without internet', (tester) async {
    await pumpSheet(tester, (_) => throw http.ClientException('offline'));
    expect(find.textContaining('nicht erreichbar'), findsOneWidget);
  });
}
