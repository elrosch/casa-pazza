import 'package:casa_pazza/src/data/auth.dart';
import 'package:drift/drift.dart' show Value;
import 'package:casa_pazza/src/data/db/database.dart';
import 'package:casa_pazza/src/data/sync/sync_service.dart';
import 'package:casa_pazza/src/features/voice/speech_recognizer.dart';
import 'package:casa_pazza/src/features/voice/voice_input_sheet.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pretends the user said [sentence].
class FakeRecognizer implements SpeechRecognizer {
  FakeRecognizer(this.sentence);

  final String sentence;

  @override
  Future<bool> start({
    required void Function(String text, bool isFinal) onText,
    required void Function(String message) onError,
  }) async {
    onText(sentence, true);
    return true;
  }

  @override
  Future<void> stop() async {}
}

String fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

void main() {
  late AppDatabase db;

  Future<void> pumpSheet(WidgetTester tester, String sentence) async {
    await initializeDateFormatting('de');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.members)
        .insert(
          MembersCompanion.insert(id: 'elias', name: const Value('Elias')),
        );
    await db
        .into(db.taskLists)
        .insert(
          TaskListsCompanion.insert(id: 'tl', household: 'h', name: 'To Do'),
        );
    await db
        .into(db.shoppingLists)
        .insert(
          ShoppingListsCompanion.insert(
            id: 'sl',
            household: 'h',
            name: 'Einkauf',
          ),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          databaseProvider.overrideWithValue(db),
          connectivityProvider.overrideWithValue(const Stream.empty()),
          speechRecognizerProvider.overrideWithValue(FakeRecognizer(sentence)),
        ],
        child: const MaterialApp(home: Scaffold(body: VoiceInputSheet())),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  testWidgets('task with assignee and due date', (tester) async {
    await pumpSheet(tester, 'Neues Todo für Elias: Wäsche waschen morgen');

    expect(fieldText(tester), 'Wäsche waschen');
    expect(find.text('Fällig: Morgen'), findsOneWidget);
    final chip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Elias'),
    );
    expect(chip.selected, isTrue);

    await tester.tap(find.text('Hinzufügen'));
    await tester.pumpAndSettle();
    final task = await db.select(db.tasks).getSingle();
    expect(task.title, 'Wäsche waschen');
    expect(task.assignee, 'elias');
    expect(task.list, 'tl');
    expect(task.due, isNotNull);
    await finish(tester);
  });

  testWidgets('several shopping items', (tester) async {
    await pumpSheet(tester, 'Salz und 2 Liter Milch auf die Einkaufsliste');

    expect(fieldText(tester), 'Salz, 2 Liter Milch');
    await tester.tap(find.text('Hinzufügen'));
    await tester.pumpAndSettle();
    final items = await db.select(db.shoppingItems).get();
    expect(items.map((i) => (i.name, i.quantity, i.list)), [
      ('Salz', '', 'sl'),
      ('Milch', '2 Liter', 'sl'),
    ]);
    await finish(tester);
  });

  testWidgets('misclassified sentence can be switched', (tester) async {
    await pumpSheet(tester, 'Batterien');
    // Understood as a task; the user switches to shopping.
    await tester.tap(find.text('Einkauf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hinzufügen'));
    await tester.pumpAndSettle();
    expect((await db.select(db.shoppingItems).getSingle()).name, 'Batterien');
    expect(await db.select(db.tasks).get(), isEmpty);
    await finish(tester);
  });
}
