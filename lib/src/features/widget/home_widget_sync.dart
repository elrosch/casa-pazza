import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/auth.dart';
import '../../data/repositories.dart';
import '../../data/sync/sync_service.dart';

/// Must match DATA_KEY and the receiver class in TasksWidget.kt.
const _dataKey = 'tasks_widget';
const _androidReceiver = 'de.eliasrosch.casa_pazza.TasksWidgetReceiver';

/// Builds the JSON the Android widget renders. Date labels are computed
/// natively so they stay correct while the app is closed.
@visibleForTesting
String buildWidgetJson({
  required bool loggedIn,
  String listName = '',
  List<Map<String, Object?>> tasks = const [],
}) => jsonEncode({'loggedIn': loggedIn, 'list': listName, 'tasks': tasks});

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

  String isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  return buildWidgetJson(
    loggedIn: true,
    listName: list.name,
    tasks: [
      for (final t in tasks.where((t) => !t.done).take(30))
        {
          'id': t.id,
          'title': t.title,
          'due': t.due == null ? '' : isoDate(t.due!),
          'assignee': t.assignee == auth.userId
              ? 'Ich'
              : members.nameOf(t.assignee),
          'repeats': t.repeatUnit != null,
        },
    ],
  );
});

/// Pushes widget data whenever it changes. Watched by the app widget.
final homeWidgetSyncProvider = Provider<void>((ref) {
  ref.listen<String?>(widgetJsonProvider, (previous, json) {
    if (json == null || json == previous) return;
    unawaited(_publish(json));
  }, fireImmediately: true);
});

Future<void> _publish(String json) async {
  try {
    await HomeWidget.saveWidgetData<String>(_dataKey, json);
    await HomeWidget.updateWidget(qualifiedAndroidName: _androidReceiver);
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

  /// Parses the launch URIs used in TasksWidget.kt.
  static WidgetRequest? fromUri(Uri? uri) => switch (uri?.host) {
    'add-task' => const AddTaskRequest(),
    'edit-task' when uri!.queryParameters['id'] != null => EditTaskRequest(
      uri.queryParameters['id']!,
    ),
    _ => null,
  };
}

class AddTaskRequest extends WidgetRequest {
  const AddTaskRequest();
}

class EditTaskRequest extends WidgetRequest {
  const EditTaskRequest(this.taskId);

  final String taskId;
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

  /// Returns the pending request and clears it.
  WidgetRequest? consume() {
    final request = state;
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

/// Runs in a background isolate when a checkbox on the widget is tapped
/// (`casapazza://complete?id=…`): completes the task like the app does,
/// refreshes the widget right away and then syncs with the server.
@pragma('vm:entry-point')
Future<void> widgetBackgroundCallback(Uri? uri) async {
  final taskId = uri?.queryParameters['id'];
  if (uri?.host != 'complete' || taskId == null) return;

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
    final db = container.read(databaseProvider);
    final task = await (db.select(
      db.tasks,
    )..where((t) => t.id.equals(taskId))).getSingleOrNull();
    if (task != null && !task.done && !task.deleted) {
      await container.read(tasksRepositoryProvider).complete(task);
    }
    await _publishFrom(container);

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
  final lists = await container.read(taskListsProvider.future);
  final list = resolveSelectedList(
    lists,
    container.read(selectedListIdProvider('tasks')),
    (l) => l.id,
  );
  if (list != null) await container.read(tasksOfListProvider(list.id).future);
  await container.read(membersProvider.future);
  final json = container.read(widgetJsonProvider);
  if (json != null) await _publish(json);
}
