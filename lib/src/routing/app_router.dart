import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/auth.dart';
import '../features/auth/login_screen.dart';
import '../features/household/household_setup_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shopping/shopping_list_screen.dart';
import '../features/shopping/shopping_lists_screen.dart';
import '../features/tasks/task_list_screen.dart';
import '../features/tasks/task_lists_screen.dart';

abstract final class AppRoutes {
  static const login = '/login';
  static const householdSetup = '/household';
  static const tasks = '/tasks';
  static const shopping = '/shopping';
  static const settings = '/settings';

  static String taskList(String id) => '$tasks/$id';
  static String shoppingList(String id) => '$shopping/$id';
}

final routerProvider = Provider<GoRouter>((ref) {
  // Re-evaluates redirects whenever login or household state changes.
  final refresh = ValueNotifier(0);
  ref.listen(
    authProvider.select((a) => (a.isLoggedIn, a.hasHousehold)),
    (_, _) => refresh.value++,
  );
  ref.onDispose(refresh.dispose);

  final router = GoRouter(
    initialLocation: AppRoutes.tasks,
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final location = state.matchedLocation;
      if (!auth.isLoggedIn) {
        return location == AppRoutes.login ? null : AppRoutes.login;
      }
      if (!auth.hasHousehold) {
        return location == AppRoutes.householdSetup
            ? null
            : AppRoutes.householdSetup;
      }
      if (location == AppRoutes.login || location == AppRoutes.householdSetup) {
        return AppRoutes.tasks;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.householdSetup,
        builder: (context, state) => const HouseholdSetupScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _ScaffoldWithNavBar(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.tasks,
                builder: (context, state) => const TaskListsScreen(),
                routes: [
                  GoRoute(
                    path: ':listId',
                    builder: (context, state) =>
                        TaskListScreen(listId: state.pathParameters['listId']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.shopping,
                builder: (context, state) => const ShoppingListsScreen(),
                routes: [
                  GoRoute(
                    path: ':listId',
                    builder: (context, state) => ShoppingListScreen(
                      listId: state.pathParameters['listId']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.settings,
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class _ScaffoldWithNavBar extends StatelessWidget {
  const _ScaffoldWithNavBar({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (index) =>
            shell.goBranch(index, initialLocation: index == shell.currentIndex),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.check_circle_outline),
            selectedIcon: Icon(Icons.check_circle),
            label: 'Aufgaben',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_cart_outlined),
            selectedIcon: Icon(Icons.shopping_cart),
            label: 'Einkauf',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Einstellungen',
          ),
        ],
      ),
    );
  }
}
