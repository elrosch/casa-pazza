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

Das Backend liegt in `server/`: PocketBase als Go-Programm, erweitert um
Push-Benachrichtigungen (`push.go`). GitHub Actions baut daraus das Image
`ghcr.io/elrosch/casa-pazza-pocketbase` (amd64/arm64). Schema-Migrationen gehören
nach `server/pb_migrations`, Server-Hooks nach `server/pb_hooks`.

### Push-Benachrichtigungen (Firebase Cloud Messaging)

- App: `android/app/google-services.json` aus der Firebase-Konsole. Ohne die
  Datei baut die App weiterhin, Push ist dann aus.
- Server: Im PocketBase-Dashboard unter *Collections → app_secrets* beim
  Eintrag `fcm_service_account` den kompletten Inhalt der Service-Account-JSON
  (Firebase → Projekteinstellungen → Dienstkonten) als `value` eintragen.
  Der Schlüssel gehört nicht ins Repo.

Deployment mit Portainer: *Stacks → Add stack → Repository*, Compose-Pfad
`server/docker-compose.yml`, keine Umgebungsvariablen nötig. Beim ersten Start steht in
den Container-Logs ein Installationslink für den Superuser (Host durch die
NAS-Adresse ersetzen). Das Dashboard ist danach unter `http://<nas>:8090/_/` erreichbar.
