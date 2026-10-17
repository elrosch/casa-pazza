import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../common/widgets.dart';
import '../../data/repositories.dart';
import '../../routing/app_router.dart';

class ShoppingListsScreen extends ConsumerWidget {
  const ShoppingListsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = ref.watch(shoppingListsProvider);
    final counts = ref.watch(openItemCountsProvider).value ?? const {};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Einkaufslisten'),
        actions: const [SyncIndicator()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text('Neue Liste'),
        onPressed: () => _createList(context, ref),
      ),
      body: AsyncBody(
        value: lists,
        builder: (lists) {
          if (lists.isEmpty) {
            return const EmptyHint(
              icon: Icons.shopping_basket_outlined,
              text: 'Noch keine Einkaufslisten.\nLege z. B. „Supermarkt“ an.',
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              for (final l in lists)
                ListTile(
                  leading: const Icon(Icons.shopping_cart_outlined),
                  title: Text(l.name),
                  subtitle: Text(_itemsLabel(counts[l.id] ?? 0)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go(AppRoutes.shoppingList(l.id)),
                ),
            ],
          );
        },
      ),
    );
  }

  static String _itemsLabel(int count) => switch (count) {
    0 => 'Nichts zu kaufen',
    1 => '1 Artikel',
    _ => '$count Artikel',
  };

  Future<void> _createList(BuildContext context, WidgetRef ref) async {
    final name = await showTextInputDialog(
      context,
      title: 'Neue Einkaufsliste',
      hint: 'z. B. Supermarkt',
      confirm: 'Anlegen',
    );
    if (name == null) return;
    final id = await ref.read(shoppingRepositoryProvider).createList(name);
    if (context.mounted) context.go(AppRoutes.shoppingList(id));
  }
}
