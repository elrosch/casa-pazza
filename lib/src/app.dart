import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/sync/sync_service.dart';
import 'features/widget/home_widget_sync.dart';
import 'routing/app_router.dart';
import 'theme/app_theme.dart';

class CasaPazzaApp extends ConsumerStatefulWidget {
  const CasaPazzaApp({super.key});

  @override
  ConsumerState<CasaPazzaApp> createState() => _CasaPazzaAppState();
}

class _CasaPazzaAppState extends ConsumerState<CasaPazzaApp>
    with WidgetsBindingObserver {
  StreamSubscription<Uri?>? _widgetClicks;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initialWidgetLaunch().then(_onWidgetLaunch);
    _widgetClicks = widgetClicks().listen(
      _onWidgetLaunch,
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    _widgetClicks?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onWidgetLaunch(Uri? uri) {
    if (uri == null || !mounted) return;
    final request = WidgetRequest.fromUri(uri);
    if (request != null) {
      ref.read(widgetRequestProvider.notifier).request(request);
    }
    ref.read(routerProvider).go(AppRoutes.tasks);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(syncServiceProvider)?.syncNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keeps the sync engine and the home screen widget updates alive.
    ref.watch(syncServiceProvider);
    ref.watch(homeWidgetSyncProvider);

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
