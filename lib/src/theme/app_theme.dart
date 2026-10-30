import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth.dart';

/// Color theme chosen in the settings.
enum AppThemeChoice {
  /// The default Casa Pazza colors, light or dark following the system.
  system('System'),
  light('Hell'),
  dark('Dunkel'),
  gruvboxLight('Gruvbox Hell'),
  gruvboxDark('Gruvbox Dunkel');

  const AppThemeChoice(this.label);

  final String label;
}

final themeChoiceProvider =
    NotifierProvider<ThemeChoiceNotifier, AppThemeChoice>(
      ThemeChoiceNotifier.new,
    );

class ThemeChoiceNotifier extends Notifier<AppThemeChoice> {
  static const _key = 'theme';

  @override
  AppThemeChoice build() {
    final stored = ref.read(prefsProvider).getString(_key);
    return AppThemeChoice.values.where((c) => c.name == stored).firstOrNull ??
        AppThemeChoice.system;
  }

  void set(AppThemeChoice choice) {
    ref.read(prefsProvider).setString(_key, choice.name);
    state = choice;
  }
}

/// Colors for task priorities A–D, matching the active theme.
@immutable
class PriorityColors extends ThemeExtension<PriorityColors> {
  const PriorityColors({
    required this.a,
    required this.b,
    required this.c,
    required this.d,
  });

  final Color a; // red
  final Color b; // yellow
  final Color c; // green
  final Color d; // aqua

  Color of(String priority) => switch (priority) {
    'A' => a,
    'B' => b,
    'C' => c,
    _ => d,
  };

  @override
  PriorityColors copyWith({Color? a, Color? b, Color? c, Color? d}) =>
      PriorityColors(
        a: a ?? this.a,
        b: b ?? this.b,
        c: c ?? this.c,
        d: d ?? this.d,
      );

  @override
  PriorityColors lerp(PriorityColors? other, double t) {
    if (other == null) return this;
    return PriorityColors(
      a: Color.lerp(a, other.a, t)!,
      b: Color.lerp(b, other.b, t)!,
      c: Color.lerp(c, other.c, t)!,
      d: Color.lerp(d, other.d, t)!,
    );
  }
}

extension PriorityColorsOf on ThemeData {
  /// The theme's priority colors, or the default ones for themes without
  /// them (e.g. a plain ThemeData in tests).
  PriorityColors get priorityColors =>
      extension<PriorityColors>() ??
      (brightness == Brightness.dark ? AppTheme.dark : AppTheme.light)
          .extension<PriorityColors>()!;
}

abstract final class AppTheme {
  static const _seed = Color(0xFFE2583E);

  static final light = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: _seed),
    extensions: const [
      PriorityColors(
        a: Color(0xFFD32F2F),
        b: Color(0xFFF9A825),
        c: Color(0xFF388E3C),
        d: Color(0xFF00897B),
      ),
    ],
  );

  static final dark = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    ),
    extensions: const [
      PriorityColors(
        a: Color(0xFFEF5350),
        b: Color(0xFFFFCA28),
        c: Color(0xFF66BB6A),
        d: Color(0xFF4DB6AC),
      ),
    ],
  );

  // Gruvbox palette: https://github.com/morhetz/gruvbox
  static final gruvboxDark = _gruvbox(
    brightness: Brightness.dark,
    bg0: const Color(0xFF282828),
    bg1: const Color(0xFF3C3836),
    bg2: const Color(0xFF504945),
    bg3: const Color(0xFF665C54),
    soft: const Color(0xFF32302F),
    fg: const Color(0xFFEBDBB2),
    gray: const Color(0xFF928374),
    red: const Color(0xFFFB4934),
    green: const Color(0xFFB8BB26),
    yellow: const Color(0xFFFABD2F),
    blue: const Color(0xFF83A598),
    aqua: const Color(0xFF8EC07C),
    orange: const Color(0xFFFE8019),
  );

  static final gruvboxLight = _gruvbox(
    brightness: Brightness.light,
    bg0: const Color(0xFFFBF1C7),
    bg1: const Color(0xFFEBDBB2),
    bg2: const Color(0xFFD5C4A1),
    bg3: const Color(0xFFBDAE93),
    soft: const Color(0xFFF2E5BC),
    fg: const Color(0xFF3C3836),
    gray: const Color(0xFF928374),
    red: const Color(0xFF9D0006),
    green: const Color(0xFF79740E),
    yellow: const Color(0xFFB57614),
    blue: const Color(0xFF076678),
    aqua: const Color(0xFF427B58),
    orange: const Color(0xFFAF3A03),
  );

  static ThemeData _gruvbox({
    required Brightness brightness,
    required Color bg0,
    required Color bg1,
    required Color bg2,
    required Color bg3,
    required Color soft,
    required Color fg,
    required Color gray,
    required Color red,
    required Color green,
    required Color yellow,
    required Color blue,
    required Color aqua,
    required Color orange,
  }) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: orange,
      onPrimary: bg0,
      primaryContainer: bg2,
      onPrimaryContainer: fg,
      secondary: blue,
      onSecondary: bg0,
      secondaryContainer: bg2,
      onSecondaryContainer: fg,
      tertiary: aqua,
      onTertiary: bg0,
      error: red,
      onError: bg0,
      surface: bg0,
      onSurface: fg,
      onSurfaceVariant: gray,
      surfaceContainerLowest: bg0,
      surfaceContainerLow: soft,
      surfaceContainer: soft,
      surfaceContainerHigh: bg1,
      surfaceContainerHighest: bg2,
      outline: gray,
      outlineVariant: bg3,
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: bg0,
      extensions: [PriorityColors(a: red, b: yellow, c: green, d: aqua)],
    );
  }
}
