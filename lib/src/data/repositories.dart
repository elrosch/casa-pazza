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

/// Open before done; then priority A–D, due date (undated last) and title.
final _taskOrder = <OrderClauseGenerator<$TasksTable>>[
  (t) => OrderingTerm.asc(t.done),
  (t) => OrderingTerm.asc(t.priority),
  (t) => OrderingTerm(expression: t.due, nulls: NullsOrder.last),
  (t) => OrderingTerm.asc(t.title),
];

class TasksRepository extends _Repository {
  TasksRepository(super.ref);

  Future<String> createList(String name, {bool isPrivate = false}) async {
    final id = newRecordId();
    await db
        .into(db.taskLists)
        .insert(
          TaskListsCompanion.insert(
            id: id,
            household: auth.householdId,
            name: name.trim(),
            sort: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
            isPrivate: Value(isPrivate),
            owner: Value(auth.userId),
            dirty: const Value(true),
          ),
        );
    pushLater();
    return id;
  }

  /// Makes a list private (only the current user sees it) or shares it with
  /// the household again. Only the list's owner may do this; an ownerless
  /// list is claimed by the current user.
  Future<void> setListPrivate(String id, bool isPrivate) async {
    await db.transaction(() async {
      await (db.update(db.taskLists)..where((l) => l.id.equals(id))).write(
        TaskListsCompanion(
          isPrivate: Value(isPrivate),
          owner: Value(auth.userId),
          dirty: const Value(true),
        ),
      );
      if (isPrivate) {
        // Assignments to others are not allowed in private lists.
        await (db.update(db.tasks)..where(
              (t) =>
                  t.list.equals(id) &
                  t.assignee.isNotNull() &
                  t.assignee.equals(auth.userId).not(),
            ))
            .write(
              const TasksCompanion(assignee: Value(null), dirty: Value(true)),
            );
      }
    });
    pushLater();
  }

  /// Whether the current user may change the visibility of [list].
  bool canChangeVisibility(TaskListRow list) =>
      list.owner == null || list.owner == auth.userId;

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
    String? priority,
  }) async {
    final fields = TasksCompanion(
      // Keeps the stored priority (or the default D) when not given.
      list: Value(listId),
      title: Value(title.trim()),
      notes: Value(notes.trim()),
      assignee: Value(assignee),
      due: Value(due),
      repeatUnit: Value(repeatUnit?.name),
      repeatEvery: Value(repeatUnit == null ? 0 : repeatEvery),
      priority: priority == null ? const Value.absent() : Value(priority),
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
    await db.transaction(() async {
      await (db.update(db.tasks)..where((t) => t.id.equals(task.id))).write(
        TasksCompanion(
          done: Value(next == null),
          due: next == null ? const Value.absent() : Value(next),
          doneAt: Value(now),
          doneBy: Value(auth.userId),
          dirty: const Value(true),
        ),
      );
      // Log the completion for the history ("Verlauf").
      await db
          .into(db.completions)
          .insert(
            CompletionsCompanion.insert(
              id: newRecordId(),
              household: task.household,
              task: Value(task.id),
              list: task.list,
              title: task.title,
              user: auth.userId,
              doneAt: now,
              dirty: const Value(true),
            ),
          );
    });
    pushLater();
    return next;
  }

  /// Undo of [complete]: restores the task and drops its newest completion
  /// entry by the current user.
  Future<void> undoComplete(TaskRow before) async {
    await db.transaction(() async {
      await db.update(db.tasks).replace(before.copyWith(dirty: true));
      final latest =
          await (db.select(db.completions)
                ..where(
                  (c) =>
                      c.task.equals(before.id) &
                      c.user.equals(auth.userId) &
                      c.deleted.not(),
                )
                ..orderBy([(c) => OrderingTerm.desc(c.doneAt)])
                ..limit(1))
              .getSingleOrNull();
      if (latest != null) {
        await (db.update(
          db.completions,
        )..where((c) => c.id.equals(latest.id))).write(
          const CompletionsCompanion(deleted: Value(true), dirty: Value(true)),
        );
      }
    });
    pushLater();
  }

  /// Moves a task's due date to tomorrow ("Morgen" swipe).
  Future<void> postpone(TaskRow task) async {
    final now = DateTime.now();
    await (db.update(db.tasks)..where((t) => t.id.equals(task.id))).write(
      TasksCompanion(
        due: Value(DateTime(now.year, now.month, now.day + 1)),
        dirty: const Value(true),
      ),
    );
    pushLater();
  }

  /// Puts a task back into an earlier state: undo of complete, postpone or
  /// delete.
  Future<void> restoreTask(TaskRow before) async {
    await db.update(db.tasks).replace(before.copyWith(dirty: true));
    pushLater();
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
            ..where((i) => i.list.equals(listId) & i.deleted.not()))
          .watch()
          .map((items) => items..sort(compareShoppingItems));
    });

/// Open items first, then checked ones; each group alphabetically, with
/// umlauts sorted like their base letters (Äpfel next to Apfelsaft).
int compareShoppingItems(ShoppingItemRow a, ShoppingItemRow b) {
  if (a.checked != b.checked) return a.checked ? 1 : -1;
  final byName = germanSortKey(a.name).compareTo(germanSortKey(b.name));
  return byName != 0 ? byName : a.id.compareTo(b.id);
}

/// Case-insensitive sort key that treats ä/ö/ü/ß like a/o/u/ss.
String germanSortKey(String s) => s
    .trim()
    .toLowerCase()
    .replaceAll('ä', 'a')
    .replaceAll('ö', 'o')
    .replaceAll('ü', 'u')
    .replaceAll('ß', 'ss');

/// What [ShoppingRepository.addItem] did.
enum AddItemResult {
  added,

  /// Already open on the list; only a given quantity was taken over.
  alreadyOnList,

  /// Was checked off ("im Wagen") and is open again.
  reactivated;

  /// Hint for the user, null for a plain add.
  String? hint(String name) => switch (this) {
    added => null,
    alreadyOnList => '„$name" steht schon auf der Liste',
    reactivated => '„$name" wieder auf der Liste',
  };
}

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

  /// Adds an item unless it is already on the list (same name, ignoring
  /// case and umlauts): an open duplicate only takes over a given quantity,
  /// a checked one ("im Wagen") becomes open again.
  Future<AddItemResult> addItem(
    String listId,
    String name, {
    String quantity = '',
  }) async {
    final key = germanSortKey(name);
    final qty = quantity.trim();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final result = await db.transaction(() async {
      final existing =
          (await (db.select(
                db.shoppingItems,
              )..where((i) => i.list.equals(listId) & i.deleted.not())).get())
              .where((i) => germanSortKey(i.name) == key)
              .toList();
      final open = existing.where((i) => !i.checked).firstOrNull;
      if (open != null) {
        if (qty.isNotEmpty && qty != open.quantity) {
          await (db.update(
            db.shoppingItems,
          )..where((i) => i.id.equals(open.id))).write(
            ShoppingItemsCompanion(
              quantity: Value(qty),
              dirty: const Value(true),
            ),
          );
        }
        return AddItemResult.alreadyOnList;
      }
      final inCart = existing.firstOrNull;
      if (inCart != null) {
        await (db.update(
          db.shoppingItems,
        )..where((i) => i.id.equals(inCart.id))).write(
          ShoppingItemsCompanion(
            checked: const Value(false),
            checkedBy: const Value(null),
            quantity: qty.isEmpty ? const Value.absent() : Value(qty),
            sort: Value(now),
            dirty: const Value(true),
          ),
        );
        return AddItemResult.reactivated;
      }
      await db
          .into(db.shoppingItems)
          .insert(
            ShoppingItemsCompanion.insert(
              id: newRecordId(),
              household: auth.householdId,
              list: listId,
              name: name.trim(),
              quantity: Value(qty),
              sort: Value(now),
              dirty: const Value(true),
            ),
          );
      return AddItemResult.added;
    });
    pushLater();
    return result;
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

  /// Puts an item back into an earlier state: undo of check-off or delete.
  Future<void> restoreItem(ShoppingItemRow before) async {
    await db.update(db.shoppingItems).replace(before.copyWith(dirty: true));
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
