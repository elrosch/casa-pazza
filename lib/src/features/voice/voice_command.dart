import 'package:flutter/foundation.dart';

import '../../data/db/database.dart';
import '../shopping/shopping_screen.dart' show parseItemInput;

/// What a spoken sentence asks for.
sealed class VoiceCommand {
  const VoiceCommand();
}

/// "Salz und Pfeffer auf die Einkaufsliste" → two shopping items.
@immutable
class ShoppingVoiceCommand extends VoiceCommand {
  const ShoppingVoiceCommand(this.items);

  final List<({String name, String quantity})> items;
}

/// "Neues Todo für Elias: Wäsche waschen morgen" → task with assignee/due.
@immutable
class TaskVoiceCommand extends VoiceCommand {
  const TaskVoiceCommand({required this.title, this.assignee, this.due});

  final String title;

  /// Member id, null when nobody was named.
  final String? assignee;
  final DateTime? due;
}

const _weekdays = {
  'montag': DateTime.monday,
  'dienstag': DateTime.tuesday,
  'mittwoch': DateTime.wednesday,
  'donnerstag': DateTime.thursday,
  'freitag': DateTime.friday,
  'samstag': DateTime.saturday,
  'sonntag': DateTime.sunday,
};

final _shoppingPatterns = [
  // "(setze) Salz auf die Einkaufsliste (setzen)"
  RegExp(
    r'^(?:setz\w*|schreib\w*|pack\w*|füg\w*|tu\w*)?\s*(.+?)\s+(?:auf|zur|in)\s+(?:die\s+|der\s+)?einkaufsliste(?:\s+(?:setzen|schreiben|packen|hinzufügen|hinzu))?$',
    caseSensitive: false,
  ),
  // "Einkaufsliste: Salz", "Einkauf Salz"
  RegExp(r'^einkauf(?:sliste)?\s*:?\s+(.+)$', caseSensitive: false),
  // "(wir müssen) Milch kaufen", "kaufe Milch"
  RegExp(
    r'^(?:(?:ich|wir)\s+(?:muss|müssen)\s+(?:noch\s+)?)?(.+?)\s+kaufen$',
    caseSensitive: false,
  ),
  RegExp(r'^kauf(?:e|en)?\s+(.+)$', caseSensitive: false),
];

final _taskPrefix = RegExp(
  r'^(?:(?:eine?|ein|neue[snr]?)\s+)?(?:todo|to-do|to do|aufgabe)\b\s*(?:hinzufügen\s*)?:?\s*',
  caseSensitive: false,
);

/// Parses a recognized sentence. [members] resolve `für <Name>`, [myId] is
/// used for "für mich", [now] anchors relative dates. Returns null for an
/// empty sentence.
VoiceCommand? parseVoiceCommand(
  String sentence, {
  required List<MemberRow> members,
  required String myId,
  required DateTime now,
}) {
  var text = sentence
      .trim()
      .replaceAll(RegExp(r'[.!?]+$'), '')
      .replaceAll(RegExp(r'\bbitte\b,?\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (text.isEmpty) return null;

  for (final pattern in _shoppingPatterns) {
    final match = pattern.firstMatch(text);
    if (match != null) {
      final items = [
        for (final part
            in match.group(1)!.split(RegExp(r'\s*(?:,|\bund\b)\s*')))
          if (part.trim().isNotEmpty) parseItemInput(_capitalize(part.trim())),
      ];
      if (items.isNotEmpty) {
        return ShoppingVoiceCommand([
          for (final (name, quantity) in items)
            (name: name, quantity: quantity),
        ]);
      }
    }
  }

  text = text.replaceFirst(_taskPrefix, '');

  // Assignee: "für Elias …" at the start or "… für Elias" at the end, so a
  // title like "Geschenk für Oma kaufen" stays intact.
  String? assignee;
  String? resolve(String name) {
    final lower = name.toLowerCase();
    if (lower == 'mich') return myId;
    for (final m in members) {
      final full = m.name.toLowerCase();
      if (full.isNotEmpty &&
          (full == lower || full.split(' ').first == lower)) {
        return m.id;
      }
    }
    return null;
  }

  final leading = RegExp(
    r'^für\s+(\S+?)\s*:?\s+',
    caseSensitive: false,
  ).firstMatch(text);
  final leadingId = leading == null ? null : resolve(leading.group(1)!);
  if (leadingId != null) {
    assignee = leadingId;
    text = text.substring(leading!.end);
  } else {
    final trailing = RegExp(
      r'\s+für\s+(\S+)$',
      caseSensitive: false,
    ).firstMatch(text);
    final trailingId = trailing == null ? null : resolve(trailing.group(1)!);
    if (trailingId != null) {
      assignee = trailingId;
      text = text.substring(0, trailing!.start);
    }
  }

  final (title, due) = _extractDue(text, now);
  final cleaned = title.replaceAll(RegExp(r'^[\s:,-]+|[\s:,-]+$'), '');
  if (cleaned.isEmpty) return null;
  return TaskVoiceCommand(
    title: _capitalize(cleaned),
    assignee: assignee,
    due: due,
  );
}

// Word boundaries that also count German umlauts as letters (`\b` does not).
const _start = r'(?<![\wäöüÄÖÜß])';
const _end = r'(?![\wäöüÄÖÜß])';

/// Finds and removes a date phrase: heute, morgen, übermorgen, (am/bis)
/// `Wochentag`, nächste Woche, in N Tagen.
(String, DateTime?) _extractDue(String text, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  // Calendar days, not 24 h steps, so daylight saving changes are harmless.
  DateTime inDays(int days) =>
      DateTime(today.year, today.month, today.day + days);
  DateTime? due;

  // Wraps a phrase in word boundaries that also respect umlauts.
  RegExp phrase(String pattern) =>
      RegExp('$_start$pattern$_end', caseSensitive: false);

  final patterns = <RegExp, DateTime Function(Match)>{
    phrase(r'(?:bis\s+)?übermorgen'): (_) => inDays(2),
    phrase(r'(?:bis\s+)?morgen'): (_) => inDays(1),
    phrase(r'(?:bis\s+)?heute'): (_) => today,
    phrase(r'(?:bis\s+)?nächste\s+woche'): (_) => inDays(7),
    phrase(r'in\s+(\d+)\s+tag(?:en)?'): (m) => inDays(int.parse(m.group(1)!)),
    phrase(
      r'(?:am|bis|bis\s+zum|kommenden?)\s+'
      r'(montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonntag)',
    ): (m) {
      final target = _weekdays[m.group(1)!.toLowerCase()]!;
      final days = (target - today.weekday) % 7;
      return inDays(days);
    },
  };

  for (final entry in patterns.entries) {
    final match = entry.key.firstMatch(text);
    if (match != null) {
      due = entry.value(match);
      text = (text.substring(0, match.start) + text.substring(match.end))
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      break;
    }
  }
  return (text, due);
}

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
