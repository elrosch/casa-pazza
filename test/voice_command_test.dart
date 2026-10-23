import 'package:casa_pazza/src/data/db/database.dart';
import 'package:casa_pazza/src/features/voice/voice_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Friday, 23 Oct 2026
  final now = DateTime(2026, 10, 23, 18);
  const members = [
    MemberRow(id: 'elias', name: 'Elias Rosch', email: ''),
    MemberRow(id: 'anna', name: 'Anna', email: ''),
  ];

  VoiceCommand? parse(String s) =>
      parseVoiceCommand(s, members: members, myId: 'anna', now: now);

  List<(String, String)> shopping(String s) => [
    for (final i in (parse(s)! as ShoppingVoiceCommand).items)
      (i.name, i.quantity),
  ];

  TaskVoiceCommand task(String s) => parse(s)! as TaskVoiceCommand;

  group('shopping', () {
    test('"auf die Einkaufsliste" phrasings', () {
      expect(shopping('Setze Salz auf die Einkaufsliste'), [('Salz', '')]);
      expect(shopping('Salz auf die Einkaufsliste.'), [('Salz', '')]);
      expect(shopping('Schreib bitte Zucker auf die Einkaufsliste'), [
        ('Zucker', ''),
      ]);
      expect(shopping('Milch zur Einkaufsliste hinzufügen'), [('Milch', '')]);
      expect(shopping('Einkaufsliste: Brot'), [('Brot', '')]);
    });

    test('"kaufen" phrasings', () {
      expect(shopping('2 Liter Milch kaufen'), [('Milch', '2 Liter')]);
      expect(shopping('Wir müssen noch Eier kaufen'), [('Eier', '')]);
      expect(shopping('kaufe Butter'), [('Butter', '')]);
    });

    test('several items at once', () {
      expect(
        shopping('Salz, Pfeffer und 2 Dosen Tomaten auf die Einkaufsliste'),
        [('Salz', ''), ('Pfeffer', ''), ('Tomaten', '2 Dosen')],
      );
    });
  });

  group('tasks', () {
    test('assignee at the start, with prefix and colon', () {
      final t = task('Neues Todo für Elias: Wäsche waschen');
      expect(t.title, 'Wäsche waschen');
      expect(t.assignee, 'elias');
      expect(t.due, isNull);
    });

    test('assignee at the end, full name and "mich"', () {
      expect(task('Wäsche waschen für Elias').assignee, 'elias');
      expect(task('Aufgabe Müll rausbringen für mich').assignee, 'anna');
      expect(
        task('Bad putzen für Elias Rosch').assignee,
        isNull,
        reason: 'only single names at the end',
      );
    });

    test('"für" inside the title stays part of it', () {
      final t = task('Geschenk für Oma kaufen morgen');
      expect(t.title, 'Geschenk für Oma kaufen');
      expect(t.assignee, isNull);
      expect(t.due, DateTime(2026, 10, 24));
    });

    test('unknown names are not assignees', () {
      final t = task('Für Paul Rasen mähen');
      expect(t.title, 'Für Paul Rasen mähen');
      expect(t.assignee, isNull);
    });

    test('dates', () {
      expect(task('Müll rausbringen morgen').due, DateTime(2026, 10, 24));
      expect(task('übermorgen Fenster putzen').due, DateTime(2026, 10, 25));
      expect(task('Reifenwechsel am Montag').title, 'Reifenwechsel');
      expect(task('Reifenwechsel am Montag').due, DateTime(2026, 10, 26));
      expect(task('Steuer bis Freitag').due, DateTime(2026, 10, 23));
      expect(task('Arzt anrufen in 3 Tagen').due, DateTime(2026, 10, 26));
      expect(
        task('Keller aufräumen nächste Woche').due,
        DateTime(2026, 10, 30),
      );
      expect(task('Heute Blumen gießen').title, 'Blumen gießen');
    });

    test('combined', () {
      final t = task('Neue Aufgabe für Elias morgen Wäsche waschen');
      expect(t.title, 'Wäsche waschen');
      expect(t.assignee, 'elias');
      expect(t.due, DateTime(2026, 10, 24));
    });

    test('words containing date names stay intact', () {
      expect(task('Morgenmantel waschen').title, 'Morgenmantel waschen');
      expect(task('Morgenmantel waschen').due, isNull);
    });
  });

  test('empty input', () {
    expect(parse('  '), isNull);
    expect(parse('Neue Aufgabe'), isNull);
  });
}
