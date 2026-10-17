# Casa Pazza

Mobile-App für Android und iOS, gebaut mit Flutter.

## Entwicklung

```bash
flutter pub get
flutter run
flutter test
```

## Struktur

```
lib/
  main.dart              Einstiegspunkt
  src/
    app.dart             MaterialApp mit Router und Themes
    routing/             go_router-Konfiguration inkl. Bottom-Navigation
    theme/               Hell-/Dunkel-Theme
    features/<name>/     Screens und Logik je Feature
```
