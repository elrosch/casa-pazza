import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:casa_pazza/src/app.dart';

void main() {
  testWidgets('zeigt Startseite und wechselt zu Einstellungen', (tester) async {
    await tester.pumpWidget(const CasaPazzaApp());

    expect(find.text('Willkommen bei Casa Pazza'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Über die App'), findsOneWidget);
  });
}
