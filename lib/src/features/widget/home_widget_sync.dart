import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/auth.dart';
import '../../data/repositories.dart';
import '../../data/task_filter.dart';
import '../../data/sync/sync_service.dart';
import '../../routing/app_router.dart' show AppRoutes;

/// Data keys and receivers, matching TasksWidget.kt and ShoppingWidget.kt.
const _tasksWidget = (
  key: 'tasks_widget',
  receiver: 'de.eliasrosch.casa_pazza.TasksWidgetReceiver',
);
const _shoppingWidget = (
  key: 'shopping_widget',
  receiver: 'de.eliasrosch.casa_pazza.ShoppingWidgetReceiver',
);

/// Builds the JSON the Android widget renders. Date labels are computed
/// natively so they stay correct while the app is closed.
@visibleForTesting
String buildWidgetJson({
  required bool loggedIn,
  String listName = '',
  TaskView view = TaskView.today,
  List<Map<String, Object?>> tasks = const [],
}) => jsonEncode({
  'loggedIn': loggedIn,
  'list': listName,
  // The widget filters itself, so "today" stays right after midnight.
  'until': view.unlimited
      ? 'all'
      : view.until == null
      ? 'today'
      : _isoDate(view.until!),
  'type': view.type.name,
  'tasks': tasks,
});

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Widget data for the open tasks of the selected task list, or null while
/// still loading.
final widgetJsonProvider = Provider<String?>((ref) {
  final auth = ref.watch(authProvider);
  if (!auth.isLoggedIn || !auth.hasHousehold) {
    return buildWidgetJson(loggedIn: false);
  }
  final lists = ref.watch(taskListsProvider).value;
  if (lists == null) return null;
  final list = resolveSelectedList(
    lists,
    ref.watch(selectedListIdProvider('tasks')),
    (l) => l.id,
  );
  if (list == null) return null;
  final tasks = ref.watch(tasksOfListProvider(list.id)).value;
  if (tasks == null) return null;
  final members = ref.watch(membersProvider).value ?? const [];

  return buildWidgetJson(
    loggedIn: true,
    listName: list.name,
    view: ref.watch(taskViewProvider),
    tasks: [
      for (final t in tasks.where((t) => !t.done).take(60))
        {
          'id': t.id,
          'title': t.title,
          'due': t.due == null ? '' : _isoDate(t.due!),
          'assignee': t.assignee == auth.userId
              ? 'Ich'
              : members.nameOf(t.assignee),
          'repeats': t.repeatUnit != null,
        },
    ],
  );
});

/// Widget data for the unchecked items of the selected shopping list, or
/// null while still loading.
final shoppingWidgetJsonProvider = Provider<String?>((ref) {
  final auth = ref.watch(authProvider);
  if (!auth.isLoggedIn || !auth.hasHousehold) {
    return jsonEncode({'loggedIn': false});
  }
  final lists = ref.watch(shoppingListsProvider).value;
  if (lists == null) return null;
  final list = resolveSelectedList(
    lists,
    ref.watch(selectedListIdProvider('shopping')),
    (l) => l.id,
  );
  if (list == null) return null;
  final items = ref.watch(shoppingItemsProvider(list.id)).value;
  if (items == null) return null;
  return jsonEncode({
    'loggedIn': true,
    'list': list.name,
    'items': [
      for (final i in items.where((i) => !i.checked).take(40))
        {'id': i.id, 'name': i.name, 'quantity': i.quantity},
    ],
  });
});

/// Pushes widget data whenever it changes. Watched by the app widget.
final homeWidgetSyncProvider = Provider<void>((ref) {
  ref.listen<String?>(widgetJsonProvider, (previous, json) {
    if (json == null || json == previous) return;
    unawaited(_publish(_tasksWidget, json));
  }, fireImmediately: true);
  ref.listen<String?>(shoppingWidgetJsonProvider, (previous, json) {
    if (json == null || json == previous) return;
    unawaited(_publish(_shoppingWidget, json));
  }, fireImmediately: true);
});

Future<void> _publish(
  ({String key, String receiver}) widget,
  String json,
) async {
  try {
    await HomeWidget.saveWidgetData<String>(widget.key, json);
    await HomeWidget.updateWidget(qualifiedAndroidName: widget.receiver);
  } catch (e) {
    // No widget support (tests, iOS without extension): nothing to update.
    debugPrint('home widget update skipped: $e');
  }
}

// ---------------------------------------------------------------------------
// Widget actions
// ---------------------------------------------------------------------------

/// What the widget asked the app to show.
sealed class WidgetRequest {
  const WidgetRequest();

  /// Parses the launch URIs used by the widgets (TasksWidget.kt,
  /// ShoppingWidget.kt) and the app shortcuts (res/xml/shortcuts.xml).
  static WidgetRequest? fromUri(Uri? uri) => switch (uri?.host) {
    'add-task' => const AddTaskRequest(),
    'edit-task' when uri!.queryParameters['id'] != null => EditTaskRequest(
      uri.queryParameters['id']!,
    ),
    'scan' => const ScanRequest(),
    'voice' => const VoiceRequest(),
    _ => null,
  };

  /// The tab that handles this request.
  String get route => AppRoutes.tasks;
}

class AddTaskRequest extends WidgetRequest {
  const AddTaskRequest();
}

class EditTaskRequest extends WidgetRequest {
  const EditTaskRequest(this.taskId);

  final String taskId;
}

/// The "Per Sprache hinzufügen" app shortcut: open voice input.
class VoiceRequest extends WidgetRequest {
  const VoiceRequest();
}

/// The shopping widget's scan button: open the barcode scanner.
class ScanRequest extends WidgetRequest {
  const ScanRequest();

  @override
  String get route => AppRoutes.shopping;
}

/// Pending request from a widget launch; the tasks tab consumes it.
final widgetRequestProvider =
    NotifierProvider<WidgetRequestNotifier, WidgetRequest?>(
      WidgetRequestNotifier.new,
    );

class WidgetRequestNotifier extends Notifier<WidgetRequest?> {
  @override
  WidgetRequest? build() => null;

  void request(WidgetRequest request) => state = request;

  /// Returns the pending request if it is a [T] and clears it, so each tab
  /// only takes the requests meant for it.
  T? consume<T extends WidgetRequest>() {
    final request = state;
    if (request is! T) return null;
    state = null;
    return request;
  }
}

Future<Uri?> initialWidgetLaunch() async {
  try {
    return await HomeWidget.initiallyLaunchedFromHomeWidget();
  } catch (_) {
    return null;
  }
}

Stream<Uri?> widgetClicks() {
  try {
    return HomeWidget.widgetClicked;
  } catch (_) {
    return const Stream.empty();
  }
}

Future<void> registerWidgetCallbacks() async {
  try {
    await HomeWidget.registerInteractivityCallback(widgetBackgroundCallback);
  } catch (e) {
    debugPrint('home widget callback not registered: $e');
  }
}

/// Runs in a background isolate when a checkbox on a widget is tapped:
/// `casapazza://complete?id=…` completes a task like the app does,
/// `casapazza://check-item?id=…` checks off a shopping item. The widgets are
/// refreshed right away, then the change is synced with the server.
@pragma('vm:entry-point')
Future<void> widgetBackgroundCallback(Uri? uri) async {
  final id = uri?.queryParameters['id'];
  if (id == null) return;

  switch (uri!.host) {
    case 'complete':
      await syncInBackground(
        before: (container) async {
          final db = container.read(databaseProvider);
          final task = await (db.select(
            db.tasks,
          )..where((t) => t.id.equals(id))).getSingleOrNull();
          if (task != null && !task.done && !task.deleted) {
            await container.read(tasksRepositoryProvider).complete(task);
          }
        },
      );
    case 'check-item':
      await syncInBackground(
        before: (container) async {
          final db = container.read(databaseProvider);
          final item = await (db.select(
            db.shoppingItems,
          )..where((i) => i.id.equals(id))).getSingleOrNull();
          if (item != null && !item.checked && !item.deleted) {
            await container.read(shoppingRepositoryProvider).toggle(item);
          }
        },
      );
  }
}

/// Syncs with the server outside the app UI (widget actions, push messages)
/// and refreshes the home screen widgets. [before] runs first, e.g. to apply
/// a local change, and the widget is updated once before and once after
/// the network round trip.
Future<void> syncInBackground({
  Future<void> Function(ProviderContainer container)? before,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  // The app isolate may have changed login or selected list meanwhile.
  await prefs.reload();
  final container = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      connectivityProvider.overrideWithValue(const Stream.empty()),
    ],
  );
  try {
    if (before != null) {
      await before(container);
      await _publishFrom(container);
    }
    final sync = container.read(syncServiceProvider);
    if (sync != null) {
      await sync.syncNow();
      // Let the drift streams deliver pulled changes before rendering.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await _publishFrom(container);
    }
  } finally {
    container.dispose();
  }
}

Future<void> _publishFrom(ProviderContainer container) async {
  final taskLists = await container.read(taskListsProvider.future);
  final taskList = resolveSelectedList(
    taskLists,
    container.read(selectedListIdProvider('tasks')),
    (l) => l.id,
  );
  if (taskList != null) {
    await container.read(tasksOfListProvider(taskList.id).future);
  }
  await container.read(membersProvider.future);
  final tasksJson = container.read(widgetJsonProvider);
  if (tasksJson != null) await _publish(_tasksWidget, tasksJson);

  final shoppingLists = await container.read(shoppingListsProvider.future);
  final shoppingList = resolveSelectedList(
    shoppingLists,
    container.read(selectedListIdProvider('shopping')),
    (l) => l.id,
  );
  if (shoppingList != null) {
    await container.read(shoppingItemsProvider(shoppingList.id).future);
  }
  final shoppingJson = container.read(shoppingWidgetJsonProvider);
  if (shoppingJson != null) await _publish(_shoppingWidget, shoppingJson);
}
