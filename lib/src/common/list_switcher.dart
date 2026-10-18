import 'package:flutter/material.dart';

/// App bar title for a tab showing one list. With several lists, tapping the
/// title opens a picker; with a single list it is plain text.
class ListSwitcherTitle extends StatelessWidget {
  const ListSwitcherTitle({
    super.key,
    required this.current,
    required this.names,
    required this.onSelect,
  });

  final String current;

  /// List id → name, in display order.
  final Map<String, String> names;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final name = names[current] ?? '';
    if (names.length <= 1) return Text(name);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _pick(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
          const Icon(Icons.arrow_drop_down),
        ],
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final entry in names.entries)
              ListTile(
                title: Text(entry.value),
                trailing: entry.key == current ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(entry.key),
              ),
          ],
        ),
      ),
    );
    if (id != null) onSelect(id);
  }
}

enum ListAction { create, rename, delete, clearChecked }

/// Overflow menu with the rarely needed list management actions.
class ListMenuButton extends StatelessWidget {
  const ListMenuButton({
    super.key,
    required this.onSelected,
    this.canDelete = false,
    this.showClearChecked = false,
  });

  final ValueChanged<ListAction> onSelected;
  final bool canDelete;
  final bool showClearChecked;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ListAction>(
      onSelected: onSelected,
      itemBuilder: (_) => [
        if (showClearChecked)
          const PopupMenuItem(
            value: ListAction.clearChecked,
            child: Text('Erledigte entfernen'),
          ),
        const PopupMenuItem(
          value: ListAction.rename,
          child: Text('Liste umbenennen'),
        ),
        const PopupMenuItem(
          value: ListAction.create,
          child: Text('Weitere Liste anlegen'),
        ),
        if (canDelete)
          const PopupMenuItem(
            value: ListAction.delete,
            child: Text('Liste löschen'),
          ),
      ],
    );
  }
}
