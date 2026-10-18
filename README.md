# Casa Pazza

A family and household organizer for Android: shared to-do lists, recurring
chores and shopping lists, synced through a server you host yourself.

## Features

- **Households:** everyone has their own account; family members join a
  household with an invite code.
- **Tasks:** one-off and recurring tasks (every N days, weeks, months or
  years), with due dates and an assignee. A recurring task is due again N
  units after the day it was completed.
- **Shopping lists:** quick add with quantity detection (`2 l Milch`),
  check off, swipe to delete.
- **Home screen widget:** see open tasks, check them off, edit them or add a
  new one with assignment, without opening the app.
- **Push notifications:** the assignee is notified when someone assigns them
  a task (optional, via Firebase Cloud Messaging).
- **Offline first:** everything works without a connection; changes sync
  automatically once the server is reachable again.

## How it works

The Flutter app keeps all data in a local database and syncs it with a
[PocketBase](https://pocketbase.io) server. The server is a single container
that stores everything in SQLite, so a small home server or NAS is enough.
Only push notifications go through Google; all other data stays on your
server.

## Self-hosting

### 1. Run the server

The server image is built from [`server/`](server) by GitHub Actions and
published to the GitHub Container Registry of the repository. Run it with
Docker Compose (or paste the file into a Portainer stack):

```yaml
services:
  pocketbase:
    image: ghcr.io/<owner>/casa-pazza-pocketbase:latest
    container_name: casa-pazza-pocketbase
    restart: unless-stopped
    ports:
      - "8090:8090"
    volumes:
      - pb_data:/pb_data

volumes:
  pb_data:
```

Replace `<owner>` with the GitHub account that hosts the repository (your
fork if you build the image yourself), or build it locally with
`docker build -t casa-pazza-pocketbase server`. If the image is private,
log in to `ghcr.io` with a token that has the `read:packages` scope.

On first start the container log prints a link to create the admin account
(replace `0.0.0.0` with your server's address). The admin dashboard is then
available at `http://<server>:8090/_/`. All data lives in the `pb_data`
volume; backups can be configured in the dashboard.

To update, pull the new image and recreate the container. Database
migrations run automatically on start.

### 2. Install the app

Download the APK from the [releases](../../releases) and install it on each
phone. On first start, enter your server address (e.g.
`http://192.168.1.10:8090`), create an account and either create a household
or join one with the invite code shown in another member's settings.

The app allows plain HTTP for use inside a home network. To use it on the
go, make the server reachable through a VPN or a reverse proxy with HTTPS.

### 3. Push notifications (optional)

1. Create a project in the [Firebase console](https://console.firebase.google.com)
   and add an Android app with the package name `de.eliasrosch.casa_pazza`.
2. Build the app with the downloaded `google-services.json` in
   `android/app/` (for releases, store its content in the repository secret
   `GOOGLE_SERVICES_JSON`).
3. In Firebase under *Project settings → Service accounts*, generate a
   private key. In the PocketBase dashboard open the `app_secrets`
   collection and paste the key's JSON into the `value` of
   `fcm_service_account`. Keep this key secret.

## Building releases

Publishing a GitHub Release with a tag like `v1.2.0` builds an APK with that
version and attaches it to the release. For APKs that can be updated in
place, sign them with your own key via these repository secrets:
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`
and `ANDROID_KEY_PASSWORD`.

## Development

```bash
flutter pub get
flutter run
flutter test
```

The server is PocketBase as a Go module with the schema in
`server/pb_migrations` and hooks in `server/pb_hooks`:

```bash
cd server
go test ./...
go run . serve --migrationsDir=pb_migrations --hooksDir=pb_hooks
```

## License

GPL-3.0, see [LICENSE](LICENSE).
