import 'package:casa_pazza/src/features/shopping/shopping_list_screen.dart';
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
}
