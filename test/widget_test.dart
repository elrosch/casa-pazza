import 'package:casa_pazza/src/app.dart';
import 'package:casa_pazza/src/data/auth.dart';
import 'package:casa_pazza/src/data/db/database.dart';
import 'package:casa_pazza/src/data/sync/sync_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows login when signed out', (tester) async {
    await initializeDateFormatting('de');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          databaseProvider.overrideWithValue(db),
          connectivityProvider.overrideWithValue(const Stream.empty()),
        ],
        child: const CasaPazzaApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Anmelden'), findsWidgets);
    expect(find.text('Noch kein Konto? Registrieren'), findsOneWidget);

    await tester.tap(find.text('Noch kein Konto? Registrieren'));
    await tester.pumpAndSettle();
    expect(find.text('Name'), findsOneWidget);
  });
}
