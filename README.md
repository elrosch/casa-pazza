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

## Sync-Backend (PocketBase)

Das Backend liegt in `server/`. GitHub Actions baut daraus das Image
`ghcr.io/elrosch/casa-pazza-pocketbase` (amd64/arm64). Schema-Migrationen gehören
nach `server/pb_migrations`, Server-Hooks nach `server/pb_hooks`.

Deployment mit Portainer: *Stacks → Add stack → Repository*, Compose-Pfad
`server/docker-compose.yml`, keine Umgebungsvariablen nötig. Beim ersten Start steht in
den Container-Logs ein Installationslink für den Superuser (Host durch die
NAS-Adresse ersetzen). Das Dashboard ist danach unter `http://<nas>:8090/_/` erreichbar.
