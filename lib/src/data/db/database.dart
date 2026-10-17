import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// Columns shared by all collections that are synced with PocketBase.
///
/// `updated` holds the server timestamp of the last known server state,
/// `dirty` marks local changes that still have to be pushed.
mixin SyncColumns on Table {
  TextColumn get id => text()();
  TextColumn get household => text()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  TextColumn get updated => text().withDefault(const Constant(''))();
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('MemberRow')
class Members extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get email => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('HouseholdRow')
class Households extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get inviteCode => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('TaskListRow')
class TaskLists extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get color => text().withDefault(const Constant(''))();
  IntColumn get sort => integer().withDefault(const Constant(0))();
}

@DataClassName('TaskRow')
class Tasks extends Table with SyncColumns {
  TextColumn get list => text()();
  TextColumn get title => text()();
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get assignee => text().nullable()();
  DateTimeColumn get due => dateTime().nullable()();
  TextColumn get repeatUnit => text().nullable()();
  IntColumn get repeatEvery => integer().withDefault(const Constant(0))();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  DateTimeColumn get doneAt => dateTime().nullable()();
  TextColumn get doneBy => text().nullable()();
  TextColumn get createdBy => text().nullable()();
}

@DataClassName('ShoppingListRow')
class ShoppingLists extends Table with SyncColumns {
  TextColumn get name => text()();
  IntColumn get sort => integer().withDefault(const Constant(0))();
}

@DataClassName('ShoppingItemRow')
class ShoppingItems extends Table with SyncColumns {
  TextColumn get list => text()();
  TextColumn get name => text()();
  TextColumn get quantity => text().withDefault(const Constant(''))();
  BoolColumn get checked => boolean().withDefault(const Constant(false))();
  TextColumn get checkedBy => text().nullable()();
  IntColumn get sort => integer().withDefault(const Constant(0))();
}

/// Last pulled server `updated` timestamp per collection.
class SyncCursors extends Table {
  TextColumn get collection => text()();
  TextColumn get cursor => text()();

  @override
  Set<Column> get primaryKey => {collection};
}

@DriftDatabase(
  tables: [
    Members,
    Households,
    TaskLists,
    Tasks,
    ShoppingLists,
    ShoppingItems,
    SyncCursors,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'casa_pazza'));

  @override
  int get schemaVersion => 1;

  /// Removes all local data, e.g. on logout or when switching households.
  Future<void> clearAll() => transaction(() async {
    for (final table in allTables) {
      await delete(table).go();
    }
  });
}
