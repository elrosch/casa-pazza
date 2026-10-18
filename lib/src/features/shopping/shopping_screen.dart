import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/list_switcher.dart';
import '../../common/widgets.dart';
import '../../data/db/database.dart';
import '../../data/repositories.dart';

/// Splits quick-add input like "2 l Milch" or "Milch 2l" into name/quantity.
(String name, String quantity) parseItemInput(String input) {
  final text = input.trim();
  final leading = RegExp(
    r'^(\d+[.,]?\d*\s*(?:x|stk\.?|g|kg|ml|l|pck\.?|dose[n]?|fl\.?)?)\s+(.+)$',
    caseSensitive: false,
  ).firstMatch(text);
  if (leading != null) return (leading.group(2)!, leading.group(1)!);
  final trailing = RegExp(
    r'^(.+?)\s+(\d+[.,]?\d*\s*(?:x|stk\.?|g|kg|ml|l|pck\.?|dose[n]?|fl\.?)?)$',
    caseSensitive: false,
  ).firstMatch(text);
  if (trailing != null) return (trailing.group(1)!, trailing.group(2)!);
  return (text, '');
}

/// Shopping tab: shows the selected shopping list directly.
class ShoppingScreen extends ConsumerWidget {
  const ShoppingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = ref.watch(shoppingListsProvider);
    final selectedId = ref.watch(selectedListIdProvider('shopping'));

    return AsyncBody(
      value: lists,
      builder: (lists) {
        final list = resolveSelectedList(lists, selectedId, (l) => l.id);
        if (list == null) {
          return Scaffold(
            appBar: AppBar(actions: const [SyncIndicator()]),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        return _ShoppingListView(list: list, lists: lists);
      },
    );
  }
}

class _ShoppingListView extends ConsumerWidget {
  const _ShoppingListView({required this.list, required this.lists});

  final ShoppingListRow list;
  final List<ShoppingListRow> lists;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(shoppingItemsProvider(list.id));
    final repo = ref.read(shoppingRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: ListSwitcherTitle(
          current: list.id,
          names: {for (final l in lists) l.id: l.name},
          onSelect: ref
              .read(selectedListIdProvider('shopping').notifier)
              .select,
        ),
        actions: [
          const SyncIndicator(),
          ListMenuButton(
            canDelete: lists.length > 1,
            showClearChecked: true,
            onSelected: (action) => _onMenu(context, ref, action),
          ),
        ],
      ),
      body: Column(
        children: [
          QuickAddField(
            hint: 'Artikel hinzufügen, z. B. 2 l Milch',
            onAdd: (text) {
              final (name, quantity) = parseItemInput(text);
              repo.addItem(list.id, name, quantity: quantity);
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: AsyncBody(
              value: items,
              builder: (items) {
                if (items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Nichts zu kaufen.',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [for (final item in items) _ItemTile(item: item)],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onMenu(
    BuildContext context,
    WidgetRef ref,
    ListAction action,
  ) async {
    final repo = ref.read(shoppingRepositoryProvider);
    switch (action) {
      case ListAction.clearChecked:
        await repo.clearChecked(list.id);
      case ListAction.create:
        final name = await showTextInputDialog(
          context,
          title: 'Weitere Einkaufsliste',
          hint: 'z. B. Drogerie',
          confirm: 'Anlegen',
        );
        if (name == null) return;
        final id = await repo.createList(name);
        ref.read(selectedListIdProvider('shopping').notifier).select(id);
      case ListAction.rename:
        final name = await showTextInputDialog(
          context,
          title: 'Liste umbenennen',
          initial: list.name,
        );
        if (name != null) await repo.renameList(list.id, name);
      case ListAction.delete:
        final ok = await confirmDialog(
          context,
          title: 'Liste löschen?',
          message: '„${list.name}“ wird für alle gelöscht.',
        );
        if (ok) await repo.deleteList(list.id);
    }
  }
}

class _ItemTile extends ConsumerWidget {
  const _ItemTile({required this.item});

  final ShoppingItemRow item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(shoppingRepositoryProvider);
    final theme = Theme.of(context);

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: theme.colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(
          Icons.delete_outline,
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
      onDismissed: (_) => repo.deleteItem(item.id),
      child: CheckboxListTile(
        controlAffinity: ListTileControlAffinity.leading,
        value: item.checked,
        onChanged: (_) => repo.toggle(item),
        title: Text(
          item.name,
          style: item.checked
              ? TextStyle(
                  decoration: TextDecoration.lineThrough,
                  color: theme.colorScheme.outline,
                )
              : null,
        ),
        secondary: item.quantity.isEmpty
            ? null
            : Text(item.quantity, style: theme.textTheme.bodyLarge),
      ),
    );
  }
}
