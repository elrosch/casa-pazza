import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/sync/sync_service.dart';
import 'routing/app_router.dart';
import 'theme/app_theme.dart';

class CasaPazzaApp extends ConsumerStatefulWidget {
  const CasaPazzaApp({super.key});

  @override
  ConsumerState<CasaPazzaApp> createState() => _CasaPazzaAppState();
}

class _CasaPazzaAppState extends ConsumerState<CasaPazzaApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(syncServiceProvider)?.syncNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keeps the sync engine alive while logged in.
    ref.watch(syncServiceProvider);

    return MaterialApp.router(
      title: 'Casa Pazza',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      locale: const Locale('de'),
      supportedLocales: const [Locale('de')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
