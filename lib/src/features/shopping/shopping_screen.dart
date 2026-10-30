import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/list_switcher.dart';
import '../../common/widgets.dart';
import '../../data/db/database.dart';
import '../../data/repositories.dart';
import '../voice/voice_input_sheet.dart';
import '../widget/home_widget_sync.dart';
import '../../common/keep_screen_on.dart';
import 'aisles.dart';
import 'barcode_scanner_screen.dart';
import 'shopping_suggestions.dart';
import 'scanned_product_sheet.dart';

/// Splits quick-add input like "2 l Milch" or "Milch 2l" into name/quantity.
(String name, String quantity) parseItemInput(String input) {
  final text = input.trim();
  final leading = RegExp(
    r'^(\d+[.,]?\d*\s*(?:liter|kilo(?:gramm)?|gramm|packung(?:en)?|päckchen|flasche[n]?|stück|becher|gläser|glas|tüte[n]?|x|stk\.?|kg|g|ml|l|pck\.?|dose[n]?|fl\.?)?)\s+(.+)$',
    caseSensitive: false,
  ).firstMatch(text);
  if (leading != null) return (leading.group(2)!, leading.group(1)!);
  final trailing = RegExp(
    r'^(.+?)\s+(\d+[.,]?\d*\s*(?:liter|kilo(?:gramm)?|gramm|packung(?:en)?|päckchen|flasche[n]?|stück|becher|gläser|glas|tüte[n]?|x|stk\.?|kg|g|ml|l|pck\.?|dose[n]?|fl\.?)?)$',
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

    // The scan button on the home screen widget opens the scanner directly.
    // Scan and mic buttons on the home screen widget open scanner or voice.
    final request = ref.watch(widgetRequestProvider);
    if (request is ScanRequest || request is ShoppingVoiceRequest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final requests = ref.read(widgetRequestProvider.notifier);
        if (!context.mounted) return;
        if (requests.consume<ScanRequest>() != null) {
          _scan(context);
        } else if (requests.consume<ShoppingVoiceRequest>() != null) {
          showVoiceInputSheet(context, preferShopping: true);
        }
      });
    }

    final shoppingMode = ref.watch(shoppingModeProvider);

    return KeepScreenOn(
      active: shoppingMode,
      child: Scaffold(
        appBar: AppBar(
          title: ListSwitcherTitle(
            current: list.id,
            names: {for (final l in lists) l.id: l.name},
            onSelect: ref
                .read(selectedListIdProvider('shopping').notifier)
                .select,
          ),
          actions: [
            IconButton(
              icon: Icon(
                shoppingMode
                    ? Icons.shopping_cart_checkout
                    : Icons.sort_by_alpha,
              ),
              isSelected: shoppingMode,
              tooltip: shoppingMode
                  ? 'Einkaufsmodus (nach Abteilung) – tippen für A–Z'
                  : 'Alphabetisch – tippen für Einkaufsmodus',
              onPressed: () {
                ref.read(shoppingModeProvider.notifier).set(!shoppingMode);
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(
                        shoppingMode
                            ? 'Alphabetisch sortiert'
                            : 'Einkaufsmodus: nach Abteilung, Bildschirm bleibt an',
                      ),
                    ),
                  );
              },
            ),
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
              onAdd: (text) async {
                final (name, quantity) = parseItemInput(text);
                final result = await repo.addItem(
                  list.id,
                  name,
                  quantity: quantity,
                );
                final hint = result.hint(name);
                if (hint != null && context.mounted) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(content: Text(hint)));
                }
              },
              // Browsers only allow the camera over HTTPS; the home server
              // usually serves plain HTTP, so scanning is Android only.
              trailing: kIsWeb
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.mic_none),
                          tooltip: 'Per Sprache hinzufügen',
                          onPressed: () => showVoiceInputSheet(
                            context,
                            preferShopping: true,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.qr_code_scanner),
                          tooltip: 'Barcode scannen',
                          onPressed: () => _scan(context),
                        ),
                      ],
                    ),
              below: (text, focused, clear) => _SuggestionChips(
                text: text,
                visible: focused,
                openItems: items.value ?? const [],
                onPick: (s) {
                  repo.addItem(list.id, s.name, quantity: s.quantity);
                  clear();
                },
              ),
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
                  if (!shoppingMode) {
                    return ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        for (final item in items) _ItemTile(item: item),
                      ],
                    );
                  }
                  // Shopping mode: open items grouped by aisle in store
                  // order (alphabetical within), checked ones at the end.
                  final byAisle = <Aisle, List<ShoppingItemRow>>{};
                  for (final item in items.where((i) => !i.checked)) {
                    byAisle.putIfAbsent(aisleOf(item.name), () => []).add(item);
                  }
                  final checked = items.where((i) => i.checked).toList();
                  return ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      for (final aisle in Aisle.values)
                        if (byAisle[aisle] case final aisleItems?) ...[
                          _GroupHeader(aisle.label),
                          for (final item in aisleItems) _ItemTile(item: item),
                        ],
                      if (checked.isNotEmpty) ...[
                        const _GroupHeader('Im Wagen'),
                        for (final item in checked) _ItemTile(item: item),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _scan(BuildContext context) async {
    final barcode = await scanProductBarcode(context);
    if (barcode == null || !context.mounted) return;
    await showScannedProductSheet(context, listId: list.id, barcode: barcode);
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
      case ListAction.togglePrivate || ListAction.history:
        break; // Not offered for shopping lists.
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
      onDismissed: (_) {
        repo.deleteItem(item.id);
        showUndoSnackBar(
          context,
          '„${item.name}" entfernt',
          onUndo: () => repo.restoreItem(item),
        );
      },
      child: CheckboxListTile(
        controlAffinity: ListTileControlAffinity.leading,
        value: item.checked,
        onChanged: (_) {
          repo.toggle(item);
          if (!item.checked) {
            showUndoSnackBar(
              context,
              '„${item.name}" abgehakt',
              onUndo: () => repo.restoreItem(item),
            );
          }
        },
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

/// Earlier purchases matching the input; with an empty, focused field the
/// most frequent ones („Häufig gekauft"). Items already open are skipped.
class _SuggestionChips extends ConsumerWidget {
  const _SuggestionChips({
    required this.text,
    required this.visible,
    required this.openItems,
    required this.onPick,
  });

  final String text;
  final bool visible;
  final List<ShoppingItemRow> openItems;
  final ValueChanged<ShoppingSuggestion> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!visible) return const SizedBox.shrink();
    final all = ref.watch(shoppingSuggestionsProvider).value ?? const [];
    final (name, _) = parseItemInput(text);
    final suggestions = matchSuggestions(
      all,
      name,
      openKeys: {
        for (final i in openItems)
          if (!i.checked) germanSortKey(i.name),
      },
      limit: text.trim().isEmpty ? 8 : 6,
    );
    if (suggestions.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          if (text.trim().isEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(
                  'Häufig:',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ),
          for (final s in suggestions)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: const Icon(Icons.history, size: 18),
                label: Text(
                  s.quantity.isEmpty ? s.name : '${s.name} · ${s.quantity}',
                ),
                onPressed: () => onPick(s),
              ),
            ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
