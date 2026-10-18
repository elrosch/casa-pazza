import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth.dart';
import 'db/database.dart';
import 'ids.dart';
import 'recurrence.dart';
import 'sync/sync_service.dart';

/// Local-first writes: every change lands in the local database marked dirty
/// and is pushed by the [SyncService] as soon as the server is reachable.
abstract class _Repository {
  _Repository(this.ref);

  final Ref ref;

  AppDatabase get db => ref.read(databaseProvider);
  AuthState get auth => ref.read(authProvider);

  void pushLater() => ref.read(syncServiceProvider)?.schedulePush();
}

// ---------------------------------------------------------------------------
// Household
// ---------------------------------------------------------------------------

final householdProvider = StreamProvider<HouseholdRow?>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.households).watchSingleOrNull();
});

final membersProvider = StreamProvider<List<MemberRow>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.members,
  )..orderBy([(m) => OrderingTerm.asc(m.name)])).watch();
});

/// Display name for a member id, falls back to the e-mail.
extension MemberNames on List<MemberRow> {
  String nameOf(String? id) {
    if (id == null) return '';
    final m = where((m) => m.id == id).firstOrNull;
    if (m == null) return 'Unbekannt';
    return m.name.isNotEmpty ? m.name : m.email;
  }
}

// ---------------------------------------------------------------------------
// List selection
// ---------------------------------------------------------------------------

/// Remembers the list shown in a tab ("tasks" or "shopping") across restarts.
final selectedListIdProvider =
    NotifierProvider.family<SelectedListId, String?, String>(
      SelectedListId.new,
    );

class SelectedListId extends Notifier<String?> {
  SelectedListId(this.tab);

  final String tab;

  SharedPreferences get _prefs => ref.read(prefsProvider);
  String get _key => 'selected_list_$tab';

  @override
  String? build() => _prefs.getString(_key);

  void select(String id) {
    _prefs.setString(_key, id);
    state = id;
  }
}

/// The selected list if it still exists, otherwise the first one.
T? resolveSelectedList<T>(
  List<T> lists,
  String? selectedId,
  String Function(T) idOf,
) => lists.where((l) => idOf(l) == selectedId).firstOrNull ?? lists.firstOrNull;

// ---------------------------------------------------------------------------
// Tasks
// ---------------------------------------------------------------------------

final tasksRepositoryProvider = Provider(TasksRepository.new);

final taskListsProvider = StreamProvider<List<TaskListRow>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.taskLists)
        ..where((l) => l.deleted.not())
        ..orderBy([
          (l) => OrderingTerm.asc(l.sort),
          (l) => OrderingTerm.asc(l.name),
        ]))
      .watch();
});

/// All non-deleted tasks of a list, open ones first by due date.
final tasksOfListProvider = StreamProvider.family<List<TaskRow>, String>((
  ref,
  listId,
) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.tasks)
        ..where((t) => t.list.equals(listId) & t.deleted.not())
        ..orderBy(_taskOrder))
      .watch();
});

final _taskOrder = <OrderClauseGenerator<$TasksTable>>[
  (t) => OrderingTerm.asc(t.done),
  (t) => OrderingTerm(expression: t.due, nulls: NullsOrder.last),
  (t) => OrderingTerm.asc(t.title),
];

class TasksRepository extends _Repository {
  TasksRepository(super.ref);

  Future<String> createList(String name) async {
    final id = newRecordId();
    await db
        .into(db.taskLists)
        .insert(
          TaskListsCompanion.insert(
            id: id,
            household: auth.householdId,
            name: name.trim(),
            sort: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
            dirty: const Value(true),
          ),
        );
    pushLater();
    return id;
  }

  Future<void> renameList(String id, String name) async {
    await (db.update(db.taskLists)..where((l) => l.id.equals(id))).write(
      TaskListsCompanion(name: Value(name.trim()), dirty: const Value(true)),
    );
    pushLater();
  }

  Future<void> deleteList(String id) async {
    await db.transaction(() async {
      await (db.update(db.taskLists)..where((l) => l.id.equals(id))).write(
        const TaskListsCompanion(deleted: Value(true), dirty: Value(true)),
      );
      await (db.update(db.tasks)..where((t) => t.list.equals(id))).write(
        const TasksCompanion(deleted: Value(true), dirty: Value(true)),
      );
    });
    pushLater();
  }

  Future<void> saveTask({
    String? id,
    required String listId,
    required String title,
    String notes = '',
    String? assignee,
    DateTime? due,
    RepeatUnit? repeatUnit,
    int repeatEvery = 1,
  }) async {
    final fields = TasksCompanion(
      list: Value(listId),
      title: Value(title.trim()),
      notes: Value(notes.trim()),
      assignee: Value(assignee),
      due: Value(due),
      repeatUnit: Value(repeatUnit?.name),
      repeatEvery: Value(repeatUnit == null ? 0 : repeatEvery),
      dirty: const Value(true),
    );
    if (id == null) {
      await db
          .into(db.tasks)
          .insert(
            fields.copyWith(
              id: Value(newRecordId()),
              household: Value(auth.householdId),
              createdBy: Value(auth.userId),
            ),
          );
    } else {
      await (db.update(db.tasks)..where((t) => t.id.equals(id))).write(fields);
    }
    pushLater();
  }

  /// Completes a task. Recurring tasks move on to their next due date and
  /// stay open; returns that date (null for one-off tasks).
  Future<DateTime?> complete(TaskRow task) async {
    final unit = RepeatUnit.fromName(task.repeatUnit);
    final now = DateTime.now();
    DateTime? next;
    if (unit != null) {
      next = nextDueDate(unit: unit, every: task.repeatEvery, now: now);
    }
    await (db.update(db.tasks)..where((t) => t.id.equals(task.id))).write(
      TasksCompanion(
        done: Value(next == null),
        due: next == null ? const Value.absent() : Value(next),
        doneAt: Value(now),
        doneBy: Value(auth.userId),
        dirty: const Value(true),
      ),
    );
    pushLater();
    return next;
  }

  Future<void> reopen(TaskRow task) async {
    await (db.update(db.tasks)..where((t) => t.id.equals(task.id))).write(
      const TasksCompanion(done: Value(false), dirty: Value(true)),
    );
    pushLater();
  }

  Future<void> deleteTask(String id) async {
    await (db.update(db.tasks)..where((t) => t.id.equals(id))).write(
      const TasksCompanion(deleted: Value(true), dirty: Value(true)),
    );
    pushLater();
  }
}

// ---------------------------------------------------------------------------
// Shopping
// ---------------------------------------------------------------------------

final shoppingRepositoryProvider = Provider(ShoppingRepository.new);

final shoppingListsProvider = StreamProvider<List<ShoppingListRow>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.shoppingLists)
        ..where((l) => l.deleted.not())
        ..orderBy([
          (l) => OrderingTerm.asc(l.sort),
          (l) => OrderingTerm.asc(l.name),
        ]))
      .watch();
});

final shoppingItemsProvider =
    StreamProvider.family<List<ShoppingItemRow>, String>((ref, listId) {
      final db = ref.watch(databaseProvider);
      return (db.select(db.shoppingItems)
            ..where((i) => i.list.equals(listId) & i.deleted.not())
            ..orderBy([
              (i) => OrderingTerm.asc(i.checked),
              (i) => OrderingTerm.desc(i.sort),
            ]))
          .watch();
    });

class ShoppingRepository extends _Repository {
  ShoppingRepository(super.ref);

  Future<String> createList(String name) async {
    final id = newRecordId();
    await db
        .into(db.shoppingLists)
        .insert(
          ShoppingListsCompanion.insert(
            id: id,
            household: auth.householdId,
            name: name.trim(),
            sort: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
            dirty: const Value(true),
          ),
        );
    pushLater();
    return id;
  }

  Future<void> renameList(String id, String name) async {
    await (db.update(db.shoppingLists)..where((l) => l.id.equals(id))).write(
      ShoppingListsCompanion(
        name: Value(name.trim()),
        dirty: const Value(true),
      ),
    );
    pushLater();
  }

  Future<void> deleteList(String id) async {
    await db.transaction(() async {
      await (db.update(db.shoppingLists)..where((l) => l.id.equals(id))).write(
        const ShoppingListsCompanion(deleted: Value(true), dirty: Value(true)),
      );
      await (db.update(
        db.shoppingItems,
      )..where((i) => i.list.equals(id))).write(
        const ShoppingItemsCompanion(deleted: Value(true), dirty: Value(true)),
      );
    });
    pushLater();
  }

  Future<void> addItem(
    String listId,
    String name, {
    String quantity = '',
  }) async {
    await db
        .into(db.shoppingItems)
        .insert(
          ShoppingItemsCompanion.insert(
            id: newRecordId(),
            household: auth.householdId,
            list: listId,
            name: name.trim(),
            quantity: Value(quantity.trim()),
            sort: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
            dirty: const Value(true),
          ),
        );
    pushLater();
  }

  Future<void> updateItem(
    String id, {
    required String name,
    String quantity = '',
  }) async {
    await (db.update(db.shoppingItems)..where((i) => i.id.equals(id))).write(
      ShoppingItemsCompanion(
        name: Value(name.trim()),
        quantity: Value(quantity.trim()),
        dirty: const Value(true),
      ),
    );
    pushLater();
  }

  Future<void> toggle(ShoppingItemRow item) async {
    final checked = !item.checked;
    await (db.update(
      db.shoppingItems,
    )..where((i) => i.id.equals(item.id))).write(
      ShoppingItemsCompanion(
        checked: Value(checked),
        checkedBy: Value(checked ? auth.userId : null),
        // Unchecked items move back to the top.
        sort: checked
            ? const Value.absent()
            : Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
        dirty: const Value(true),
      ),
    );
    pushLater();
  }

  Future<void> deleteItem(String id) async {
    await (db.update(db.shoppingItems)..where((i) => i.id.equals(id))).write(
      const ShoppingItemsCompanion(deleted: Value(true), dirty: Value(true)),
    );
    pushLater();
  }

  Future<void> clearChecked(String listId) async {
    await (db.update(
      db.shoppingItems,
    )..where((i) => i.list.equals(listId) & i.checked)).write(
      const ShoppingItemsCompanion(deleted: Value(true), dirty: Value(true)),
    );
    pushLater();
  }
}
