import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'db/database.dart';

const defaultServerUrl = 'http://casa-pazza.local:8090';

const _serverUrlKey = 'server_url';
const _authKey = 'pb_auth';

/// Provided in `main()` once SharedPreferences are loaded.
final prefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('prefsProvider must be overridden'),
);

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

@immutable
class AuthState {
  const AuthState({required this.serverUrl, required this.pb, this.user});

  final String serverUrl;
  final PocketBase pb;
  final RecordModel? user;

  bool get isLoggedIn => user != null;
  String get userId => user?.id ?? '';
  String get householdId => user?.get<String>('household', '') ?? '';
  bool get hasHousehold => householdId.isNotEmpty;
}

final authProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

class AuthController extends Notifier<AuthState> {
  SharedPreferences get _prefs => ref.read(prefsProvider);

  @override
  AuthState build() {
    final url = _prefs.getString(_serverUrlKey) ?? defaultServerUrl;
    final pb = _createClient(url);
    if (pb.authStore.isValid) {
      // Refresh in the background: renews the token and picks up household
      // changes. Offline we just keep the stored session.
      Future.microtask(refreshUser);
    }
    return AuthState(
      serverUrl: url,
      pb: pb,
      user: pb.authStore.isValid ? pb.authStore.record : null,
    );
  }

  PocketBase _createClient(String url) {
    final store = AsyncAuthStore(
      save: (data) => _prefs.setString(_authKey, data),
      clear: () => _prefs.remove(_authKey),
      initial: _prefs.getString(_authKey),
    );
    return PocketBase(url, authStore: store);
  }

  Future<void> _useServer(String url) async {
    final normalized = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (normalized == state.serverUrl) return;
    await _prefs.setString(_serverUrlKey, normalized);
    state = AuthState(serverUrl: normalized, pb: _createClient(normalized));
  }

  Future<void> login(String serverUrl, String email, String password) async {
    await _useServer(serverUrl);
    final auth = await state.pb
        .collection('users')
        .authWithPassword(email.trim(), password);
    await _setUser(auth.record);
  }

  Future<void> register(
    String serverUrl,
    String name,
    String email,
    String password,
  ) async {
    await _useServer(serverUrl);
    await state.pb
        .collection('users')
        .create(
          body: {
            'name': name.trim(),
            'email': email.trim(),
            'password': password,
            'passwordConfirm': password,
          },
        );
    await login(serverUrl, email, password);
  }

  Future<void> refreshUser() async {
    try {
      final auth = await state.pb.collection('users').authRefresh();
      if (!ref.mounted) return;
      await _setUser(auth.record);
    } on ClientException catch (e) {
      if (!ref.mounted) return;
      if (e.statusCode == 401 || e.statusCode == 403) await logout();
    }
  }

  Future<void> createHousehold(String name) async {
    await state.pb.collection('households').create(body: {'name': name.trim()});
    await refreshUser();
  }

  Future<void> joinHousehold(String code) async {
    await state.pb.send(
      '/api/casa/join',
      method: 'POST',
      body: {'code': code.trim()},
    );
    await refreshUser();
  }

  Future<void> leaveHousehold() async {
    await state.pb
        .collection('users')
        .update(state.userId, body: {'household': ''});
    await refreshUser();
  }

  Future<void> logout() async {
    state.pb.authStore.clear();
    await ref.read(databaseProvider).clearAll();
    state = AuthState(serverUrl: state.serverUrl, pb: state.pb);
  }

  Future<void> _setUser(RecordModel user) async {
    final previousHousehold = state.householdId;
    final next = AuthState(
      serverUrl: state.serverUrl,
      pb: state.pb,
      user: user,
    );
    if (previousHousehold != next.householdId) {
      // Local data belongs to the old household.
      await ref.read(databaseProvider).clearAll();
    }
    state = next;
  }
}

/// Turns PocketBase/network errors into a short German message.
String describeError(Object error) {
  if (error is ClientException) {
    if (error.statusCode == 0) {
      return 'Server nicht erreichbar. Adresse und WLAN prüfen.';
    }
    final message = error.response['message'];
    final data = error.response['data'];
    if (data is Map && data.isNotEmpty) {
      final first = data.values.first;
      if (first is Map && first['message'] != null) {
        return '${data.keys.first}: ${first['message']}';
      }
    }
    if (error.statusCode == 400 && '$message'.contains('authenticate')) {
      return 'E-Mail oder Passwort falsch.';
    }
    if (message is String && message.isNotEmpty) return message;
  }
  return 'Unbekannter Fehler: $error';
}
