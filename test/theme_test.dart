import 'package:casa_pazza/src/data/auth.dart';
import 'package:casa_pazza/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('every theme provides priority colors', () {
    for (final theme in [
      AppTheme.light,
      AppTheme.dark,
      AppTheme.gruvboxLight,
      AppTheme.gruvboxDark,
    ]) {
      final colors = theme.priorityColors;
      expect({
        colors.of('A'),
        colors.of('B'),
        colors.of('C'),
        colors.of('D'),
      }, hasLength(4));
      expect(colors.of(''), colors.d, reason: 'unknown means D');
    }
    expect(AppTheme.gruvboxDark.priorityColors.a, const Color(0xFFFB4934));
    expect(
      AppTheme.gruvboxDark.scaffoldBackgroundColor,
      const Color(0xFF282828),
    );
    expect(AppTheme.gruvboxLight.colorScheme.brightness, Brightness.light);
  });

  test('theme choice is stored and defaults to system', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [prefsProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    expect(container.read(themeChoiceProvider), AppThemeChoice.system);
    container
        .read(themeChoiceProvider.notifier)
        .set(AppThemeChoice.gruvboxDark);
    expect(prefs.getString('theme'), 'gruvboxDark');

    final reloaded = ProviderContainer(
      overrides: [prefsProvider.overrideWithValue(prefs)],
    );
    addTearDown(reloaded.dispose);
    expect(reloaded.read(themeChoiceProvider), AppThemeChoice.gruvboxDark);
  });
}
