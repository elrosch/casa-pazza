import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase/pocketbase.dart';

import '../auth.dart';
import '../db/database.dart';

const defaultTaskListName = 'Aufgaben';
const defaultShoppingListName = 'Einkauf';

enum SyncPhase { idle, syncing, offline, error }

@immutable
class SyncStatus {
  const SyncStatus(this.phase, {this.lastSync, this.message});

  final SyncPhase phase;
  final DateTime? lastSync;
  final String? message;
}

final syncStatusProvider = NotifierProvider<SyncStatusNotifier, SyncStatus>(
  SyncStatusNotifier.new,
);

class SyncStatusNotifier extends Notifier<SyncStatus> {
  @override
  SyncStatus build() => const SyncStatus(SyncPhase.idle);

  void set(SyncStatus status) => state = status;
}

/// Network changes trigger a sync; overridden in tests.
final connectivityProvider = Provider<Stream<List<ConnectivityResult>>>(
  (ref) => Connectivity().onConnectivityChanged,
);

/// Running sync engine for the current user/household, null when there is
/// nothing to sync yet.
final syncServiceProvider = Provider<SyncService?>((ref) {
  final (pb, userId, householdId) = ref.watch(
    authProvider.select((a) => (a.pb, a.userId, a.householdId)),
  );
  if (userId.isEmpty || householdId.isEmpty) return null;

  final service = SyncService(
    pb: pb,
    db: ref.read(databaseProvider),
    householdId: householdId,
    connectivity: ref.read(connectivityProvider),
    onStatus: ref.read(syncStatusProvider.notifier).set,
  );
  // Started after the provider is built: sync updates syncStatusProvider.
  Future.microtask(service.start);
  ref.onDispose(service.dispose);
  return service;
});

/// Maps one PocketBase collection onto its local drift table.
class _SyncedCollection<T extends Table, R extends DataClass> {
  _SyncedCollection({
    required this.name,
    required this.table,
    required this.fromRecord,
    required this.toBody,
  });

  final String name;
  final TableInfo<T, R> table;

  /// Builds a clean (non-dirty) local row from a server record.
  final Insertable<R> Function(RecordModel record) fromRecord;

  /// Serializes a local row for create/update requests.
  final Map<String, dynamic> Function(R row) toBody;

  String get sqlName => table.actualTableName;

  // Called through `_SyncedCollection<Table, DataClass>`; reading the typed
  // function field from outside would fail the covariance check.
  Map<String, dynamic> bodyOf(DataClass row) => toBody(row as R);
}

/// Offline-first sync: local writes mark rows `dirty`, [push] sends them,
/// [pull] fetches everything changed since the last cursor and realtime
/// events keep the tables current while the app is open.
///
/// Conflicts resolve as last-write-wins; pending local changes are never
/// overwritten by pulled data.
class SyncService {
  SyncService({
    required this.pb,
    required this.db,
    required this.householdId,
    required this.connectivity,
    required this.onStatus,
  });

  final PocketBase pb;
  final AppDatabase db;
  final String householdId;
  final Stream<List<ConnectivityResult>> connectivity;
  final void Function(SyncStatus) onStatus;

  final _unsubscribers = <UnsubscribeFunc>[];
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _periodic;
  Timer? _debounce;
  Future<void>? _running;
  bool _again = false;
  bool _disposed = false;
  DateTime? _lastSync;

  late final List<_SyncedCollection> _collections = [
    _SyncedCollection<$TaskListsTable, TaskListRow>(
      name: 'task_lists',
      table: db.taskLists,
      fromRecord: (r) => TaskListsCompanion.insert(
        id: r.id,
        household: r.get<String>('household'),
        name: r.get<String>('name'),
        color: Value(r.get<String>('color', '')),
        sort: Value(r.get<num>('sort', 0).toInt()),
        isPrivate: Value(r.get<bool>('private', false)),
        owner: Value(_nullIfEmpty(r.get<String>('owner', ''))),
        deleted: Value(r.get<bool>('deleted', false)),
        updated: Value(r.get<String>('updated')),
        dirty: const Value(false),
      ),
      toBody: (row) => {
        'household': row.household,
        'name': row.name,
        'color': row.color,
        'sort': row.sort,
        'private': row.isPrivate,
        'owner': row.owner ?? '',
        'deleted': row.deleted,
      },
    ),
    _SyncedCollection<$TasksTable, TaskRow>(
      name: 'tasks',
      table: db.tasks,
      fromRecord: (r) => TasksCompanion.insert(
        id: r.id,
        household: r.get<String>('household'),
        list: r.get<String>('list'),
        title: r.get<String>('title'),
        notes: Value(r.get<String>('notes', '')),
        assignee: Value(_nullIfEmpty(r.get<String>('assignee', ''))),
        due: Value(_parseDate(r.get<String>('due', ''))),
        repeatUnit: Value(_nullIfEmpty(r.get<String>('repeat_unit', ''))),
        repeatEvery: Value(r.get<num>('repeat_every', 0).toInt()),
        done: Value(r.get<bool>('done', false)),
        doneAt: Value(_parseDate(r.get<String>('done_at', ''))),
        doneBy: Value(_nullIfEmpty(r.get<String>('done_by', ''))),
        createdBy: Value(_nullIfEmpty(r.get<String>('created_by', ''))),
        deleted: Value(r.get<bool>('deleted', false)),
        updated: Value(r.get<String>('updated')),
        dirty: const Value(false),
      ),
      toBody: (row) => {
        'household': row.household,
        'list': row.list,
        'title': row.title,
        'notes': row.notes,
        'assignee': row.assignee ?? '',
        'due': _formatDate(row.due),
        'repeat_unit': row.repeatUnit ?? '',
        'repeat_every': row.repeatEvery,
        'done': row.done,
        'done_at': _formatDate(row.doneAt),
        'done_by': row.doneBy ?? '',
        'created_by': row.createdBy ?? '',
        'deleted': row.deleted,
      },
    ),
    _SyncedCollection<$ShoppingListsTable, ShoppingListRow>(
      name: 'shopping_lists',
      table: db.shoppingLists,
      fromRecord: (r) => ShoppingListsCompanion.insert(
        id: r.id,
        household: r.get<String>('household'),
        name: r.get<String>('name'),
        sort: Value(r.get<num>('sort', 0).toInt()),
        deleted: Value(r.get<bool>('deleted', false)),
        updated: Value(r.get<String>('updated')),
        dirty: const Value(false),
      ),
      toBody: (row) => {
        'household': row.household,
        'name': row.name,
        'sort': row.sort,
        'deleted': row.deleted,
      },
    ),
    _SyncedCollection<$ShoppingItemsTable, ShoppingItemRow>(
      name: 'shopping_items',
      table: db.shoppingItems,
      fromRecord: (r) => ShoppingItemsCompanion.insert(
        id: r.id,
        household: r.get<String>('household'),
        list: r.get<String>('list'),
        name: r.get<String>('name'),
        quantity: Value(r.get<String>('quantity', '')),
        checked: Value(r.get<bool>('checked', false)),
        checkedBy: Value(_nullIfEmpty(r.get<String>('checked_by', ''))),
        sort: Value(r.get<num>('sort', 0).toInt()),
        deleted: Value(r.get<bool>('deleted', false)),
        updated: Value(r.get<String>('updated')),
        dirty: const Value(false),
      ),
      toBody: (row) => {
        'household': row.household,
        'list': row.list,
        'name': row.name,
        'quantity': row.quantity,
        'checked': row.checked,
        'checked_by': row.checkedBy ?? '',
        'sort': row.sort,
        'deleted': row.deleted,
      },
    ),
  ];

  void start() {
    if (_disposed) return;
    _connectivitySub = connectivity.listen((results) {
      if (!results.contains(ConnectivityResult.none)) syncNow();
    });
    _periodic = Timer.periodic(const Duration(minutes: 5), (_) => syncNow());
    syncNow();
  }

  void dispose() {
    _disposed = true;
    _periodic?.cancel();
    _debounce?.cancel();
    _connectivitySub?.cancel();
    for (final unsubscribe in _unsubscribers) {
      unsubscribe().ignore();
    }
    _unsubscribers.clear();
  }

  /// Call after local writes: pushes shortly afterwards, batching quick edits.
  void schedulePush() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), syncNow);
  }

  /// Runs a full push + pull. Concurrent calls coalesce into one extra run.
  Future<void> syncNow() {
    if (_disposed) return Future.value();
    if (_running != null) {
      _again = true;
      return _running!;
    }
    _running = _run().whenComplete(() {
      _running = null;
      if (_again && !_disposed) {
        _again = false;
        syncNow();
      }
    });
    return _running!;
  }

  Future<void> _run() async {
    onStatus(SyncStatus(SyncPhase.syncing, lastSync: _lastSync));
    try {
      await _push();
      await _pullHousehold();
      for (final c in _collections) {
        await _pull(c);
      }
      await _dropHiddenTaskLists();
      if (await _ensureDefaultLists()) await _push();
      await _ensureRealtime();
      _lastSync = DateTime.now();
      onStatus(SyncStatus(SyncPhase.idle, lastSync: _lastSync));
    } on ClientException catch (e) {
      final offline = e.statusCode == 0;
      onStatus(
        SyncStatus(
          offline ? SyncPhase.offline : SyncPhase.error,
          lastSync: _lastSync,
          message: offline ? null : describeError(e),
        ),
      );
    }
  }

  Future<void> _push() async {
    for (final c in _collections) {
      final rows = await db
          .customSelect(
            'SELECT * FROM ${c.sqlName} WHERE dirty = 1',
            readsFrom: {c.table},
          )
          .asyncMap((row) async => c.table.map(row.data))
          .get();

      for (final row in rows) {
        final id = (row as dynamic).id as String;
        final body = c.bodyOf(row);
        RecordModel saved;
        try {
          saved = await pb.collection(c.name).update(id, body: body);
        } on ClientException catch (e) {
          if (e.statusCode == 404) {
            try {
              saved = await pb
                  .collection(c.name)
                  .create(body: {'id': id, ...body});
            } on ClientException catch (e) {
              if (e.statusCode == 0) rethrow;
              await _markClean(c, id, e);
              continue;
            }
          } else if (e.statusCode == 0) {
            rethrow;
          } else {
            await _markClean(c, id, e);
            continue;
          }
        }
        await _storeIfUnchanged(c, row, saved);
      }
    }
  }

  /// The server rejected a change permanently; stop retrying it.
  Future<void> _markClean(_SyncedCollection c, String id, ClientException e) {
    debugPrint('sync: ${c.name}/$id rejected: ${describeError(e)}');
    return db.customUpdate(
      'UPDATE ${c.sqlName} SET dirty = 0 WHERE id = ?',
      variables: [Variable.withString(id)],
      updates: {c.table},
    );
  }

  /// Stores the server echo unless the row was edited again meanwhile.
  Future<void> _storeIfUnchanged(
    _SyncedCollection c,
    DataClass pushed,
    RecordModel saved,
  ) async {
    await db.transaction(() async {
      final current = await db
          .customSelect(
            'SELECT * FROM ${c.sqlName} WHERE id = ?',
            variables: [Variable.withString(saved.id)],
            readsFrom: {c.table},
          )
          .asyncMap((row) async => c.table.map(row.data))
          .getSingleOrNull();
      if (current == pushed) {
        await db.into(c.table).insertOnConflictUpdate(c.fromRecord(saved));
      }
    });
  }

  /// Every household has one task list and one shopping list to start with.
  ///
  /// Runs only after a successful pull, so it never shadows lists that exist
  /// on the server. The default lists reuse the household id: devices that
  /// create them concurrently end up with the same record instead of two.
  Future<bool> _ensureDefaultLists() async {
    var created = false;
    final hasTaskList =
        await (db.select(db.taskLists)
              ..where((l) => l.deleted.not())
              ..limit(1))
            .getSingleOrNull();
    if (hasTaskList == null) {
      await db
          .into(db.taskLists)
          .insertOnConflictUpdate(
            TaskListsCompanion.insert(
              id: householdId,
              household: householdId,
              name: defaultTaskListName,
              deleted: const Value(false),
              dirty: const Value(true),
            ),
          );
      created = true;
    }
    final hasShoppingList =
        await (db.select(db.shoppingLists)
              ..where((l) => l.deleted.not())
              ..limit(1))
            .getSingleOrNull();
    if (hasShoppingList == null) {
      await db
          .into(db.shoppingLists)
          .insertOnConflictUpdate(
            ShoppingListsCompanion.insert(
              id: householdId,
              household: householdId,
              name: defaultShoppingListName,
              deleted: const Value(false),
              dirty: const Value(true),
            ),
          );
      created = true;
    }
    return created;
  }

  Future<void> _pullHousehold() async {
    final household = await pb.collection('households').getOne(householdId);
    final members = await pb.collection('users').getFullList();
    await db.transaction(() async {
      await db.delete(db.households).go();
      await db
          .into(db.households)
          .insert(
            HouseholdsCompanion.insert(
              id: household.id,
              name: household.get<String>('name'),
              inviteCode: Value(household.get<String>('invite_code', '')),
            ),
          );
      await db.delete(db.members).go();
      for (final m in members) {
        await db
            .into(db.members)
            .insert(
              MembersCompanion.insert(
                id: m.id,
                name: Value(m.get<String>('name', '')),
                email: Value(m.get<String>('email', '')),
              ),
            );
      }
    });
  }

  /// Lists that became private for someone else are no longer returned by
  /// the server (and send no realtime event), so remove local copies that
  /// the server does not know anymore, together with their tasks.
  Future<void> _dropHiddenTaskLists() async {
    final visible = await pb
        .collection('task_lists')
        .getFullList(batch: 500, fields: 'id');
    final visibleIds = {for (final r in visible) r.id};
    await db.transaction(() async {
      final local = await (db.select(
        db.taskLists,
      )..where((l) => l.dirty.not())).get();
      for (final list in local.where((l) => !visibleIds.contains(l.id))) {
        await (db.delete(
          db.tasks,
        )..where((t) => t.list.equals(list.id) & t.dirty.not())).go();
        await (db.delete(
          db.taskLists,
        )..where((l) => l.id.equals(list.id))).go();
      }
    });
  }

  Future<void> _pull(_SyncedCollection c) async {
    final cursorRow = await (db.select(
      db.syncCursors,
    )..where((t) => t.collection.equals(c.name))).getSingleOrNull();
    final cursor = cursorRow?.cursor ?? '';

    final records = await pb
        .collection(c.name)
        .getFullList(
          batch: 500,
          sort: 'updated',
          filter: cursor.isEmpty
              ? null
              : pb.filter('updated >= {:c}', {'c': cursor}),
        );
    if (records.isEmpty) return;

    await db.transaction(() async {
      for (final r in records) {
        await _upsertClean(c, r);
      }
      await db
          .into(db.syncCursors)
          .insertOnConflictUpdate(
            SyncCursorsCompanion.insert(
              collection: c.name,
              cursor: records.last.get<String>('updated'),
            ),
          );
    });
  }

  /// Applies a server record unless the local row has pending changes.
  Future<void> _upsertClean(_SyncedCollection c, RecordModel r) async {
    final dirty = await db
        .customSelect(
          'SELECT 1 FROM ${c.sqlName} WHERE id = ? AND dirty = 1',
          variables: [Variable.withString(r.id)],
        )
        .getSingleOrNull();
    if (dirty == null) {
      await db.into(c.table).insertOnConflictUpdate(c.fromRecord(r));
    }
  }

  Future<void> _ensureRealtime() async {
    if (_unsubscribers.isNotEmpty) return;
    for (final c in _collections) {
      _unsubscribers.add(
        await pb.collection(c.name).subscribe('*', (e) {
          final record = e.record;
          if (record == null || _disposed) return;
          if (e.action == 'delete') {
            db.customUpdate(
              'DELETE FROM ${c.sqlName} WHERE id = ?',
              variables: [Variable.withString(record.id)],
              updates: {c.table},
            );
          } else {
            _upsertClean(c, record);
          }
        }),
      );
    }
    _unsubscribers.add(
      await pb.collection('users').subscribe('*', (_) => _pullHousehold()),
    );
  }
}

String? _nullIfEmpty(String value) => value.isEmpty ? null : value;

DateTime? _parseDate(String value) =>
    value.isEmpty ? null : DateTime.tryParse(value)?.toLocal();

String _formatDate(DateTime? value) =>
    value == null ? '' : value.toUtc().toIso8601String();
