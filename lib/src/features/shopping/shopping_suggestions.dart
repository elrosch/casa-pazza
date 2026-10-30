import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/auth.dart';
import '../../data/db/database.dart';
import '../../data/repositories.dart' show germanSortKey;

/// Something bought before, with how often and the last quantity used.
@immutable
class ShoppingSuggestion {
  const ShoppingSuggestion({
    required this.name,
    required this.quantity,
    required this.count,
  });

  final String name;
  final String quantity;
  final int count;

  String get key => germanSortKey(name);
}

/// Builds suggestions from all shopping items ever added (checked and
/// removed ones are only soft-deleted), most frequent first.
@visibleForTesting
List<ShoppingSuggestion> buildSuggestions(List<ShoppingItemRow> items) {
  final byKey = <String, List<ShoppingItemRow>>{};
  for (final item in items) {
    final key = germanSortKey(item.name);
    if (key.isEmpty) continue;
    byKey.putIfAbsent(key, () => []).add(item);
  }
  final suggestions = [
    for (final group in byKey.values)
      () {
        // The most recently added entry decides spelling and quantity.
        final latest = group.reduce((a, b) => a.sort >= b.sort ? a : b);
        return ShoppingSuggestion(
          name: latest.name,
          quantity: latest.quantity,
          count: group.length,
        );
      }(),
  ];
  suggestions.sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    return byCount != 0 ? byCount : a.key.compareTo(b.key);
  });
  return suggestions;
}

final shoppingSuggestionsProvider = StreamProvider<List<ShoppingSuggestion>>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  return db.select(db.shoppingItems).watch().map(buildSuggestions);
});

/// Suggestions matching [input] that are not already open on the list
/// ([openKeys]); the most frequent first.
List<ShoppingSuggestion> matchSuggestions(
  List<ShoppingSuggestion> all,
  String input, {
  required Set<String> openKeys,
  int limit = 6,
}) {
  final query = germanSortKey(input);
  return all
      .where((s) => !openKeys.contains(s.key))
      .where((s) => query.isEmpty || s.key.contains(query))
      .take(limit)
      .toList();
}
