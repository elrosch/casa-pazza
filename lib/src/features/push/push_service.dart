import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../data/auth.dart';
import '../widget/home_widget_sync.dart' show syncInBackground;

/// Initializes Firebase; returns false where it is not configured (tests,
/// builds without google-services.json), in which case push stays off.
Future<bool> initPush() async {
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(pushBackgroundHandler);
    return true;
  } catch (e) {
    debugPrint('push disabled: $e');
    return false;
  }
}

/// Set in main() from [initPush].
final pushAvailableProvider = Provider<bool>((ref) => false);

/// A push arrived while the app was closed or in the background: sync so the
/// new task is there and the home screen widget shows it.
@pragma('vm:entry-point')
Future<void> pushBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await syncInBackground();
}

/// Task to open for a push message, null for unrelated messages.
String? taskIdOf(RemoteMessage message) =>
    message.data['type'] == 'task_assigned' ? message.data['task_id'] : null;

/// Registers this phone for push while a user with a household is logged in
/// and keeps the token current. Watched by the app widget.
///
/// Uses classic FCM registration tokens (getToken/onTokenRefresh), which the
/// server sends to via the HTTP v1 API. firebase_messaging 17 deprecates
/// them in favour of installation ids (register/onRegistered); switch once
/// the server side is moved over as well.
final pushRegistrationProvider = Provider<void>((ref) {
  if (!ref.watch(pushAvailableProvider)) return;
  final (pb, userId, householdId) = ref.watch(
    authProvider.select((a) => (a.pb, a.userId, a.householdId)),
  );
  if (userId.isEmpty || householdId.isEmpty) return;

  final messaging = FirebaseMessaging.instance;
  Future<void> register(String? token) async {
    if (token == null) return;
    try {
      // The server moves an existing token to this user.
      await pb
          .collection('devices')
          .create(
            body: {'user': userId, 'token': token, 'platform': 'android'},
          );
    } on ClientException catch (e) {
      // Already registered (e.g. getToken and onTokenRefresh racing).
      if ('${e.response['data']}'.contains('validation_not_unique')) return;
      debugPrint('push registration failed: $e');
    }
  }

  unawaited(() async {
    final settings = await messaging.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;
    // ignore: deprecated_member_use
    await register(await messaging.getToken());
  }());
  // ignore: deprecated_member_use
  final sub = messaging.onTokenRefresh.listen(register);
  ref.onDispose(sub.cancel);
});

/// Removes this phone's token on logout, so pushes for the old account stop.
Future<void> unregisterPushDevice(PocketBase pb) async {
  try {
    // ignore: deprecated_member_use
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    final devices = await pb
        .collection('devices')
        .getFullList(filter: pb.filter('token = {:t}', {'t': token}));
    for (final d in devices) {
      await pb.collection('devices').delete(d.id);
    }
  } catch (e) {
    debugPrint('push unregister skipped: $e');
  }
}

/// Calls [onOpen] when a notification about a task is tapped and
/// [onForeground] for pushes received while the app is open. Returns a
/// function that stops listening.
Future<void> Function() listenForPushInteractions({
  required void Function(String taskId) onOpen,
  required void Function(RemoteMessage message) onForeground,
}) {
  void open(RemoteMessage? message) {
    final taskId = message == null ? null : taskIdOf(message);
    if (taskId != null) onOpen(taskId);
  }

  FirebaseMessaging.instance.getInitialMessage().then(open);
  final subs = [
    FirebaseMessaging.onMessageOpenedApp.listen(open),
    FirebaseMessaging.onMessage.listen(onForeground),
  ];
  return () => Future.wait(subs.map((s) => s.cancel()));
}
