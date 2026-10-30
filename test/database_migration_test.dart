import 'package:casa_pazza/src/data/db/database.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('schema 1 → 4: private lists, priorities, completion log', () async {
    // The relevant tables as created by schema version 1.
    final executor = NativeDatabase.memory(
      setup: (raw) {
        raw.execute('''
          CREATE TABLE task_lists (
            id TEXT NOT NULL PRIMARY KEY, household TEXT NOT NULL,
            deleted INTEGER NOT NULL DEFAULT 0, updated TEXT NOT NULL DEFAULT '',
            dirty INTEGER NOT NULL DEFAULT 0, name TEXT NOT NULL,
            color TEXT NOT NULL DEFAULT '', sort INTEGER NOT NULL DEFAULT 0)
        ''');
        raw.execute('''
          CREATE TABLE tasks (
            id TEXT NOT NULL PRIMARY KEY, household TEXT NOT NULL,
            deleted INTEGER NOT NULL DEFAULT 0, updated TEXT NOT NULL DEFAULT '',
            dirty INTEGER NOT NULL DEFAULT 0, list TEXT NOT NULL,
            title TEXT NOT NULL, notes TEXT NOT NULL DEFAULT '',
            assignee TEXT NULL, due INTEGER NULL, repeat_unit TEXT NULL,
            repeat_every INTEGER NOT NULL DEFAULT 0,
            done INTEGER NOT NULL DEFAULT 0, done_at INTEGER NULL,
            done_by TEXT NULL, created_by TEXT NULL)
        ''');
        raw.execute(
          "INSERT INTO tasks (id, household, list, title) VALUES ('t1', 'h', 'l1', 'Müll')",
        );
        raw.execute(
          'CREATE TABLE sync_cursors (collection TEXT NOT NULL PRIMARY KEY, '
          'cursor TEXT NOT NULL)',
        );
        raw.execute(
          "INSERT INTO task_lists (id, household, name) VALUES ('l1', 'h', 'To Do')",
        );
        raw.execute(
          "INSERT INTO sync_cursors VALUES ('task_lists', '2026-10-01'), "
          "('tasks', '2026-10-01')",
        );
        raw.execute('PRAGMA user_version = 1');
      },
    );
    final db = AppDatabase(executor);
    addTearDown(db.close);

    final list = await db.select(db.taskLists).getSingle();
    expect(list.name, 'To Do');
    expect(list.isPrivate, isFalse);
    expect(list.owner, isNull);

    final cursors = await db.select(db.syncCursors).get();
    expect(cursors.map((c) => c.collection), ['tasks']);

    await (db.update(db.taskLists)..where((l) => l.id.equals('l1'))).write(
      const TaskListsCompanion(isPrivate: Value(true), owner: Value('u1')),
    );
    expect((await db.select(db.taskLists).getSingle()).isPrivate, isTrue);

    // Schema 3: existing tasks get the default priority D.
    expect((await db.select(db.tasks).getSingle()).priority, 'D');

    // Schema 4: the completion log exists and is empty.
    expect(await db.select(db.completions).get(), isEmpty);
  });
}
