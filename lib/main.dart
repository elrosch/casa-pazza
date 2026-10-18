import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/app.dart';
import 'src/data/auth.dart';
import 'src/features/push/push_service.dart';
import 'src/features/widget/home_widget_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de');
  final prefs = await SharedPreferences.getInstance();
  unawaited(registerWidgetCallbacks());
  final pushAvailable = await initPush();

  runApp(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        pushAvailableProvider.overrideWithValue(pushAvailable),
      ],
      child: const CasaPazzaApp(),
    ),
  );
}
