import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories.dart';
import 'product_lookup.dart';

/// Looks up a scanned [barcode] and lets the user confirm or edit the item
/// before it is added to [listId]. Without a match the name is typed in.
Future<void> showScannedProductSheet(
  BuildContext context, {
  required String listId,
  required String barcode,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => ScannedProductSheet(listId: listId, barcode: barcode),
  );
}

class ScannedProductSheet extends ConsumerStatefulWidget {
  const ScannedProductSheet({
    super.key,
    required this.listId,
    required this.barcode,
  });

  final String listId;
  final String barcode;

  @override
  ConsumerState<ScannedProductSheet> createState() =>
      _ScannedProductSheetState();
}

enum _LookupState { loading, found, notFound, offline }

class _ScannedProductSheetState extends ConsumerState<ScannedProductSheet> {
  final _name = TextEditingController();
  final _quantity = TextEditingController();
  var _state = _LookupState.loading;

  @override
  void initState() {
    super.initState();
    _lookup();
  }

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    _LookupState state;
    try {
      final product = await ref
          .read(productLookupProvider)
          .lookup(widget.barcode);
      if (product != null) {
        _name.text = product.suggestedName;
        _quantity.text = product.packageSize;
      }
      state = product == null ? _LookupState.notFound : _LookupState.found;
    } on ProductLookupException {
      state = _LookupState.offline;
    }
    if (mounted) setState(() => _state = state);
  }

  Future<void> _add() async {
    if (_name.text.trim().isEmpty) return;
    await ref
        .read(shoppingRepositoryProvider)
        .addItem(widget.listId, _name.text, quantity: _quantity.text);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint = switch (_state) {
      _LookupState.loading => null,
      _LookupState.found => null,
      _LookupState.notFound =>
        'Produkt nicht in Open Food Facts gefunden. Bitte Namen eingeben.',
      _LookupState.offline =>
        'Open Food Facts ist nicht erreichbar. Bitte Namen eingeben.',
    };

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Gescannter Artikel', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Barcode ${widget.barcode}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 16),
          if (_state == _LookupState.loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            if (hint != null) ...[Text(hint), const SizedBox(height: 12)],
            TextField(
              controller: _name,
              autofocus: _state != _LookupState.found,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Artikel'),
              onSubmitted: (_) => _add(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _quantity,
              decoration: const InputDecoration(labelText: 'Menge'),
              onSubmitted: (_) => _add(),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (_state == _LookupState.found)
                  Expanded(
                    child: Text(
                      'Daten: Open Food Facts (ODbL)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  )
                else
                  const Spacer(),
                FilledButton(onPressed: _add, child: const Text('Hinzufügen')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
