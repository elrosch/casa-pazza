import 'package:casa_pazza/src/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  testWidgets('about section shows version and opens licenses', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'Casa Pazza',
      packageName: 'de.example.casa_pazza',
      version: '1.2.3',
      buildNumber: '1002003',
      buildSignature: '',
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          locale: Locale('de'),
          supportedLocales: [Locale('de')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(body: SingleChildScrollView(child: AboutSection())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Über'), findsOneWidget);
    expect(find.text('Version 1.2.3 (Build 1002003)'), findsOneWidget);
    expect(find.textContaining(sourceCodeUrl), findsOneWidget);

    await tester.tap(find.text('Lizenzen'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.textContaining('GPL-3.0'), findsOneWidget);
  });
}
