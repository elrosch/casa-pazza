import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../common/widgets.dart';
import '../../data/db/database.dart';
import '../../data/repositories.dart';
import '../../routing/app_router.dart';

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

class ShoppingListScreen extends ConsumerStatefulWidget {
  const ShoppingListScreen({super.key, required this.listId});

  final String listId;

  @override
  ConsumerState<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends ConsumerState<ShoppingListScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final (name, quantity) = parseItemInput(_input.text);
    if (name.isEmpty) return;
    _input.clear();
    _focus.requestFocus();
    await ref
        .read(shoppingRepositoryProvider)
        .addItem(widget.listId, name, quantity: quantity);
  }

  @override
  Widget build(BuildContext context) {
    final list = ref
        .watch(shoppingListsProvider)
        .value
        ?.where((l) => l.id == widget.listId)
        .firstOrNull;
    final items = ref.watch(shoppingItemsProvider(widget.listId));
    final repo = ref.read(shoppingRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(list?.name ?? ''),
        actions: [
          const SyncIndicator(),
          PopupMenuButton<String>(
            onSelected: (action) => switch (action) {
              'clear' => repo.clearChecked(widget.listId),
              'rename' => _rename(list?.name ?? ''),
              'delete' => _delete(list?.name ?? ''),
              _ => null,
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'clear', child: Text('Erledigte entfernen')),
              PopupMenuItem(value: 'rename', child: Text('Umbenennen')),
              PopupMenuItem(value: 'delete', child: Text('Liste löschen')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    focusNode: _focus,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      hintText: 'Artikel hinzufügen, z. B. 2 l Milch',
                      prefixIcon: Icon(Icons.add),
                    ),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  tooltip: 'Hinzufügen',
                  onPressed: _add,
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncBody(
              value: items,
              builder: (items) {
                if (items.isEmpty) {
                  return const EmptyHint(
                    icon: Icons.shopping_basket_outlined,
                    text: 'Die Liste ist leer.',
                  );
                }
                return ListView(
                  children: [for (final item in items) _ItemTile(item: item)],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(String current) async {
    final name = await showTextInputDialog(
      context,
      title: 'Liste umbenennen',
      initial: current,
    );
    if (name != null) {
      await ref
          .read(shoppingRepositoryProvider)
          .renameList(widget.listId, name);
    }
  }

  Future<void> _delete(String name) async {
    final ok = await confirmDialog(
      context,
      title: 'Liste löschen?',
      message: '„$name“ wird für alle gelöscht.',
    );
    if (!ok) return;
    await ref.read(shoppingRepositoryProvider).deleteList(widget.listId);
    if (mounted) context.go(AppRoutes.shopping);
  }
}

class _ItemTile extends ConsumerWidget {
  const _ItemTile({required this.item});

  final ShoppingItemRow item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(shoppingRepositoryProvider);
    final theme = Theme.of(context);
    final members = ref.watch(membersProvider).value ?? const [];

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
        subtitle: item.checked && item.checkedBy != null
            ? Text('von ${members.nameOf(item.checkedBy)}')
            : null,
        secondary: item.quantity.isEmpty
            ? null
            : Text(item.quantity, style: theme.textTheme.bodyLarge),
      ),
    );
  }
}
