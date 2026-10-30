import 'package:casa_pazza/src/data/db/database.dart';
import 'package:casa_pazza/src/data/repositories.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:casa_pazza/src/data/auth.dart';

void main() {
  test('tasks sort by done, priority, due date, title', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    Future<void> add(
      String id,
      String priority, {
      DateTime? due,
      bool done = false,
    }) => db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: id,
            household: 'h',
            list: 'l',
            title: id,
            priority: Value(priority),
            due: Value(due),
            done: Value(done),
          ),
        );
    await add('d-early', 'D', due: DateTime(2026, 10, 1));
    await add('a-undated', 'A');
    await add('a-early', 'A', due: DateTime(2026, 10, 1));
    await add('c', 'C', due: DateTime(2026, 9, 1));
    await add('b-done', 'B', done: true);
    await add('b', 'B', due: DateTime(2026, 12, 1));

    final sub = container.listen(tasksOfListProvider('l'), (_, _) {});
    addTearDown(sub.close);
    final tasks = await container.read(tasksOfListProvider('l').future);
    expect(tasks.map((t) => t.id), [
      'a-early',
      'a-undated',
      'b',
      'c',
      'd-early',
      'b-done',
    ]);
  });
}
