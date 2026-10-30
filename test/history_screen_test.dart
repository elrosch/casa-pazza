import 'package:casa_pazza/src/data/auth.dart';
import 'package:casa_pazza/src/data/db/database.dart';
import 'package:casa_pazza/src/data/sync/sync_service.dart';
import 'package:casa_pazza/src/features/history/history_screen.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('history counts per person and filters', (tester) async {
    await initializeDateFormatting('de');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db
        .into(db.members)
        .insert(
          MembersCompanion.insert(id: 'elias', name: const Value('Elias')),
        );
    await db
        .into(db.members)
        .insert(
          MembersCompanion.insert(id: 'daria', name: const Value('Daria')),
        );
    final now = DateTime.now();
    var n = 0;
    Future<void> log(String user, String title, DateTime at) => db
        .into(db.completions)
        .insert(
          CompletionsCompanion.insert(
            id: 'c${n++}',
            household: 'h',
            list: 'l',
            title: title,
            user: user,
            doneAt: at,
          ),
        );
    await log('elias', 'Müll rausbringen', now);
    await log(
      'daria',
      'Wäsche waschen',
      now.subtract(const Duration(hours: 1)),
    );
    await log('elias', 'Bad putzen', now.subtract(const Duration(days: 2)));
    await log('elias', 'Uralt', now.subtract(const Duration(days: 200)));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          databaseProvider.overrideWithValue(db),
          connectivityProvider.overrideWithValue(const Stream.empty()),
        ],
        child: const MaterialApp(home: HistoryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alle · 3'), findsOneWidget);
    expect(find.text('Elias · 2'), findsOneWidget);
    expect(find.text('Daria · 1'), findsOneWidget);
    expect(find.text('Heute'), findsOneWidget);
    expect(find.text('Wäsche waschen'), findsOneWidget);
    expect(find.text('Uralt'), findsNothing, reason: 'older than 90 days');

    await tester.tap(find.text('Elias · 2'));
    await tester.pumpAndSettle();
    expect(find.text('Wäsche waschen'), findsNothing);
    expect(find.text('Bad putzen'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
