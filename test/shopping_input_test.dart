import 'package:casa_pazza/src/features/shopping/shopping_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseItemInput splits quantity and name', () {
    expect(parseItemInput('2 l Milch'), ('Milch', '2 l'));
    expect(parseItemInput('500g Hackfleisch'), ('Hackfleisch', '500g'));
    expect(parseItemInput('Eier 10'), ('Eier', '10'));
    expect(parseItemInput('3x Joghurt'), ('Joghurt', '3x'));
    expect(parseItemInput('  Brot  '), ('Brot', ''));
    expect(parseItemInput('Spülmittel'), ('Spülmittel', ''));
  });

  test('parseItemInput understands spoken units', () {
    expect(parseItemInput('2 Liter Milch'), ('Milch', '2 Liter'));
    expect(parseItemInput('1 Kilo Mehl'), ('Mehl', '1 Kilo'));
    expect(parseItemInput('3 Flaschen Wasser'), ('Wasser', '3 Flaschen'));
    expect(parseItemInput('500 Gramm Hackfleisch'), (
      'Hackfleisch',
      '500 Gramm',
    ));
  });
}
