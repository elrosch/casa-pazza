import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/sync/sync_service.dart';
import 'features/push/push_service.dart';
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
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<Uri?>? _widgetClicks;
  Future<void> Function()? _stopPushListening;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initialWidgetLaunch().then(_onWidgetLaunch);
    _widgetClicks = widgetClicks().listen(
      _onWidgetLaunch,
      onError: (Object _) {},
    );
    if (ref.read(pushAvailableProvider)) {
      _stopPushListening = listenForPushInteractions(
        onOpen: (taskId) => _openRequest(EditTaskRequest(taskId)),
        onForeground: _showForegroundPush,
      );
    }
  }

  @override
  void dispose() {
    _widgetClicks?.cancel();
    _stopPushListening?.call();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onWidgetLaunch(Uri? uri) {
    if (uri == null || !mounted) return;
    _openRequest(WidgetRequest.fromUri(uri));
  }

  /// Switches to the tasks tab, which opens the requested editor.
  void _openRequest(WidgetRequest? request) {
    if (!mounted) return;
    if (request != null) {
      ref.read(widgetRequestProvider.notifier).request(request);
    }
    ref.read(routerProvider).go(AppRoutes.tasks);
  }

  /// Android shows no notification while the app is open: show a hint
  /// instead (the task itself arrives via realtime sync).
  void _showForegroundPush(RemoteMessage message) {
    final taskId = taskIdOf(message);
    final text = message.notification?.body;
    if (taskId == null || text == null) return;
    _messenger.currentState?.showSnackBar(
      SnackBar(
        content: Text('Neue Aufgabe für dich – $text'),
        action: SnackBarAction(
          label: 'Öffnen',
          onPressed: () => _openRequest(EditTaskRequest(taskId)),
        ),
      ),
    );
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
    ref.watch(pushRegistrationProvider);

    return MaterialApp.router(
      title: 'Casa Pazza',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _messenger,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      locale: const Locale('de'),
      supportedLocales: const [Locale('de')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
