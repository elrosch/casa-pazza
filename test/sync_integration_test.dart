// End-to-end sync test against a real PocketBase with the schema from
// server/pb_migrations. Runs only when PB_TEST_URL is set, e.g.:
//
//   PB_TEST_URL=http://127.0.0.1:18096 flutter test test/sync_integration_test.dart
@TestOn('vm')
library;

import 'dart:io';
import 'dart:math';

import 'package:casa_pazza/src/data/auth.dart';
import 'package:casa_pazza/src/data/db/database.dart';
import 'package:casa_pazza/src/data/recurrence.dart';
import 'package:casa_pazza/src/data/repositories.dart';
import 'package:casa_pazza/src/data/sync/sync_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final serverUrl = Platform.environment['PB_TEST_URL'];

/// One simulated phone: own local database, preferences and login.
class Device {
  Device._(this.container, this.db);

  final ProviderContainer container;
  final AppDatabase db;

  static Future<Device> create() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        databaseProvider.overrideWithValue(db),
        connectivityProvider.overrideWithValue(const Stream.empty()),
      ],
    );
    // Keep the sync engine alive like the app widget does.
    container.listen(syncServiceProvider, (_, _) {});
    return Device._(container, db);
  }

  AuthController get auth => container.read(authProvider.notifier);
  TasksRepository get tasks => container.read(tasksRepositoryProvider);
  ShoppingRepository get shopping => container.read(shoppingRepositoryProvider);
  String get userId => container.read(authProvider).userId;

  Future<void> sync() => container.read(syncServiceProvider)!.syncNow();

  Future<void> dispose() async {
    container.dispose();
    await db.close();
  }
}

void main() {
  final suffix = Random().nextInt(1 << 32).toRadixString(36);
  late Device anna;
  late Device ben;

  setUpAll(() async {
    anna = await Device.create();
    ben = await Device.create();
  });

  tearDownAll(() async {
    await anna.dispose();
    await ben.dispose();
  });

  test(
    'two devices share tasks and shopping lists',
    () async {
      await anna.auth.register(
        serverUrl!,
        'Anna',
        'anna-$suffix@example.test',
        'test-pass-123',
      );
      await ben.auth.register(
        serverUrl!,
        'Ben',
        'ben-$suffix@example.test',
        'test-pass-123',
      );

      await anna.auth.createHousehold('Familie $suffix');
      await anna.sync();
      final household = await anna.db.select(anna.db.households).getSingle();
      expect(household.inviteCode, hasLength(8));

      await ben.auth.joinHousehold(household.inviteCode);
      await ben.sync();
      final benMembers = await ben.db.select(ben.db.members).get();
      expect(benMembers.map((m) => m.name), unorderedEquals(['Anna', 'Ben']));

      // Both devices got the same default lists, no duplicates.
      for (final device in [anna, ben]) {
        final taskLists = await device.db.select(device.db.taskLists).get();
        expect(taskLists.map((l) => (l.id, l.name)), [
          (household.id, 'Aufgaben'),
        ]);
        final shopLists = await device.db.select(device.db.shoppingLists).get();
        expect(shopLists.map((l) => (l.id, l.name)), [
          (household.id, 'Einkauf'),
        ]);
      }

      // Anna creates a recurring task for Ben in a second list.
      final listId = await anna.tasks.createList('Garten');
      await anna.tasks.saveTask(
        listId: listId,
        title: 'Müll rausbringen',
        assignee: ben.userId,
        due: DateTime(2026, 10, 1),
        repeatUnit: RepeatUnit.week,
      );
      await anna.sync();
      final pending = await (anna.db.select(
        anna.db.tasks,
      )..where((t) => t.dirty)).get();
      expect(pending, isEmpty, reason: 'all local changes pushed');

      await ben.sync();
      final benTasks = await ben.db.select(ben.db.tasks).get();
      expect(benTasks.single.title, 'Müll rausbringen');
      expect(benTasks.single.assignee, ben.userId);
      expect(benTasks.single.repeatUnit, 'week');

      // Ben completes it: it stays open and moves on by one week.
      final next = await ben.tasks.complete(benTasks.single);
      // Overdue since 1.10. – next due date counts from today.
      final now = DateTime.now();
      expect(next, DateTime(now.year, now.month, now.day + 7));
      await ben.sync();
      await anna.sync();
      final annaTask = await anna.db.select(anna.db.tasks).getSingle();
      expect(annaTask.done, isFalse);
      expect(annaTask.due, next);
      expect(annaTask.doneBy, ben.userId);

      // Shopping list round trip including check-off and deletion.
      final shopId = household.id;
      await ben.shopping.addItem(shopId, 'Milch', quantity: '2 l');
      await ben.shopping.addItem(shopId, 'Brot');
      await ben.sync();
      await anna.sync();
      final annaItems = await anna.db.select(anna.db.shoppingItems).get();
      expect(annaItems.map((i) => i.name), unorderedEquals(['Milch', 'Brot']));

      await anna.shopping.toggle(
        annaItems.firstWhere((i) => i.name == 'Milch'),
      );
      await anna.sync();
      await ben.sync();
      final milk = await (ben.db.select(
        ben.db.shoppingItems,
      )..where((i) => i.name.equals('Milch'))).getSingle();
      expect(milk.checked, isTrue);
      expect(milk.checkedBy, anna.userId);

      await ben.shopping.clearChecked(shopId);
      await ben.tasks.deleteList(listId);
      await ben.sync();
      await anna.sync();
      final visibleItems = await (anna.db.select(
        anna.db.shoppingItems,
      )..where((i) => i.deleted.not())).get();
      expect(visibleItems.map((i) => i.name), ['Brot']);
      final garden = await (anna.db.select(
        anna.db.taskLists,
      )..where((l) => l.id.equals(listId))).getSingle();
      expect(garden.deleted, isTrue);

      // Pending local edits win over older server state during pull.
      await anna.shopping.updateItem(
        visibleItems.single.id,
        name: 'Vollkornbrot',
      );
      await anna.container.read(syncServiceProvider)!.syncNow();
      final bread = await (anna.db.select(
        anna.db.shoppingItems,
      )..where((i) => i.id.equals(visibleItems.single.id))).getSingle();
      expect(bread.name, 'Vollkornbrot');
      expect(bread.dirty, isFalse);

      expect(anna.container.read(syncStatusProvider).phase, SyncPhase.idle);
    },
    skip: serverUrl == null ? 'PB_TEST_URL not set' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
