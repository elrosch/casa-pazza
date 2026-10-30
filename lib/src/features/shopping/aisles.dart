import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/auth.dart';
import '../../data/repositories.dart' show germanSortKey;

/// Store sections in the order of a typical German supermarket walk.
enum Aisle {
  produce('Obst & Gemüse', [
    'apfel',
    'aepfel',
    'birne',
    'banane',
    'orange',
    'mandarine',
    'zitrone',
    'limette',
    'traube',
    'beere',
    'kiwi',
    'mango',
    'ananas',
    'melone',
    'pfirsich',
    'nektarine',
    'pflaume',
    'kirsche',
    'avocado',
    'obst',
    'tomate',
    'gurke',
    'paprika',
    'zucchini',
    'aubergine',
    'karotte',
    'mohre',
    'kartoffel',
    'zwiebel',
    'knoblauch',
    'ingwer',
    'salat',
    'spinat',
    'brokkoli',
    'blumenkohl',
    'kohl',
    'lauch',
    'porree',
    'sellerie',
    'pilz',
    'champignon',
    'kurbis',
    'radieschen',
    'rucola',
    'gemuse',
    'petersilie',
    'basilikum',
    'schnittlauch',
    'kraut',
    'mais',
  ]),
  bakery('Brot & Backwaren', [
    'brot',
    'brotchen',
    'semmel',
    'toast',
    'baguette',
    'brezel',
    'croissant',
    'kuchen',
    'laugen',
    'wrap',
    'tortilla',
  ]),
  dairy('Kühlregal', [
    'milch',
    'joghurt',
    'jogurt',
    'quark',
    'sahne',
    'schmand',
    'butter',
    'margarine',
    'kase',
    'mozzarella',
    'feta',
    'parmesan',
    'frischkase',
    'ei',
    'eier',
    'skyr',
    'kefir',
    'buttermilch',
    'pudding',
    'tofu',
    'hummus',
    'teig',
  ]),
  meat('Fleisch, Wurst & Fisch', [
    'fleisch',
    'hack',
    'hahnchen',
    'huhn',
    'pute',
    'schnitzel',
    'steak',
    'wurst',
    'salami',
    'schinken',
    'speck',
    'bacon',
    'aufschnitt',
    'lachs',
    'fisch',
    'thunfisch',
    'garnele',
    'bratwurst',
    'wiener',
    'leberkase',
  ]),
  frozen('Tiefkühl', [
    'tiefkuhl',
    'tk ',
    'pizza',
    'eis',
    'eiswurfel',
    'pommes',
    'fischstabchen',
  ]),
  pantry('Vorrat & Konserven', [
    'nudel',
    'pasta',
    'spaghetti',
    'reis',
    'mehl',
    'zucker',
    'salz',
    'pfeffer',
    'gewurz',
    'ol',
    'olivenol',
    'rapsol',
    'sonnenblumenol',
    'speiseol',
    'essig',
    'senf',
    'ketchup',
    'mayo',
    'sosse',
    'sauce',
    'bruhe',
    'dose',
    'konserve',
    'linsen',
    'bohnen',
    'kichererbsen',
    'passierte',
    'tomatenmark',
    'honig',
    'marmelade',
    'konfiture',
    'nutella',
    'musli',
    'mueesli',
    'haferflocken',
    'cornflakes',
    'backpulver',
    'hefe',
    'vanille',
    'kakao',
    'kaffee',
    'tee',
    'nuss',
    'mandel',
    'rosine',
    'suppe',
  ]),
  sweets('Süßes & Snacks', [
    'schokolade',
    'chips',
    'keks',
    'kekse',
    'gummibar',
    'bonbon',
    'riegel',
    'salzstangen',
    'popcorn',
    'cracker',
    'praline',
    'susses',
    'snack',
  ]),
  drinks('Getränke', [
    'wasser',
    'saft',
    'schorle',
    'limo',
    'cola',
    'bier',
    'wein',
    'sekt',
    'sprudel',
    'eistee',
    'getrank',
    'smoothie',
    'hafermilch',
    'sojamilch',
  ]),
  drugstore('Drogerie', [
    'zahnpasta',
    'zahnburste',
    'shampoo',
    'duschgel',
    'seife',
    'deo',
    'creme',
    'sonnencreme',
    'rasier',
    'tampon',
    'binde',
    'windel',
    'taschentuch',
    'watte',
    'pflaster',
    'kosmetik',
    'haargel',
  ]),
  household('Haushalt', [
    'toilettenpapier',
    'klopapier',
    'kuchenrolle',
    'spulmittel',
    'spulmaschine',
    'tabs',
    'waschmittel',
    'weichspuler',
    'reiniger',
    'schwamm',
    'mullbeutel',
    'mullsack',
    'alufolie',
    'frischhaltefolie',
    'backpapier',
    'batterie',
    'gluhbirne',
    'kerze',
    'servietten',
    'katzenfutter',
    'hundefutter',
    'streu',
  ]),
  other('Sonstiges', []);

  const Aisle(this.label, this.keywords);

  final String label;
  final List<String> keywords;
}

/// The aisle for an item name. The longest matching keyword wins, so
/// „Milchschokolade" is a sweet and „Hafermilch" a drink.
Aisle aisleOf(String name) {
  final key = ' ${germanSortKey(name)} ';
  Aisle best = Aisle.other;
  var bestLength = 0;
  for (final aisle in Aisle.values) {
    for (final keyword in aisle.keywords) {
      // Very short keywords (ei, ol, eis, tk) only match whole words.
      final match = keyword.length <= 3
          ? RegExp('[^a-z]${RegExp.escape(keyword.trim())}[^a-z]').hasMatch(key)
          : key.contains(keyword);
      if (match && keyword.length > bestLength) {
        best = aisle;
        bestLength = keyword.length;
      }
    }
  }
  return best;
}

/// Alphabetical (find quickly) or shopping mode (by aisle, screen on).
final shoppingModeProvider = NotifierProvider<ShoppingModeNotifier, bool>(
  ShoppingModeNotifier.new,
);

class ShoppingModeNotifier extends Notifier<bool> {
  static const _key = 'shopping_mode';

  @override
  bool build() => ref.read(prefsProvider).getBool(_key) ?? false;

  void set(bool on) {
    ref.read(prefsProvider).setBool(_key, on);
    state = on;
  }
}
