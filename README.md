# Casa Pazza

A family and household organizer: shared to-do lists with one-off and
recurring tasks, shared shopping lists, an interactive Android home screen
widget and push notifications when someone assigns you a task.

The Flutter app works offline first and syncs with a small self-hosted
[PocketBase](https://pocketbase.io) server, for example on a NAS at home.

- [Features](#features)
- [Architecture](#architecture)
- [Repository layout](#repository-layout)
- [App development](#app-development)
- [Server development](#server-development)
- [Deployment on a NAS with Portainer](#deployment-on-a-nas-with-portainer)
- [Push notifications (Firebase Cloud Messaging)](#push-notifications-firebase-cloud-messaging)
- [CI/CD](#cicd)
- [How sync works](#how-sync-works)
- [Troubleshooting](#troubleshooting)
- [License](#license)

## Features

**Households and accounts**
- Every family member has their own account (e-mail and password).
- One person creates a household; the others join it with an 8-character
  invite code from the settings screen. The code can be regenerated.
- Each user belongs to exactly one household; all data is scoped to it.

**Tasks**
- The tasks tab opens the current list directly. Add tasks by typing in the
  field at the top; tap a task to edit details.
- Tasks can be assigned to a household member and have an optional due date.
  Overdue tasks are highlighted.
- Recurring tasks (every N days, weeks, months or years). When a recurring
  task is completed, it stays open and is due again N units **after the day
  of completion**, whether it was done early, on time or late.
- Additional lists can be created from the overflow menu (⋮). Once there is
  more than one list, tapping the title switches between them.

**Shopping lists**
- Quick add with quantity detection, e.g. `2 l Milch`, `500g Hackfleisch`
  or `Eier 10`.
- Tap to check off, swipe to delete, "remove checked" from the menu.
- Multiple lists work like task lists.

**Home screen widget (Android)**
- Shows the open tasks of the current list with due date, assignee and a
  recurrence marker.
- The checkbox completes a task in the background without opening the app.
- Tapping a task opens its editor; `+` opens the editor for a new task,
  including assignment.

**Push notifications**
- The assignee gets a notification when someone else assigns a task to
  them. Tapping it opens the task.
- A push also syncs the app in the background, so the widget shows the new
  task right away.

**Offline first**
- Everything works without a connection to the server; changes are synced
  automatically once it is reachable again (e.g. back in the home Wi-Fi).

## Architecture

```
┌──────────────────────────────┐          ┌──────────────────────────────┐
│ Flutter app (Android)        │  REST +  │ PocketBase (Go) on the NAS   │
│                              │  SSE     │                              │
│ UI ── Riverpod ── drift DB ◄─┼──────────┼─► SQLite, API rules,         │
│                 (SQLite)     │  sync    │   JS migrations + hooks      │
│ Home screen widget (Glance) ◄┤          │                              │
│ Firebase Messaging          ◄┼──┐       │ push.go ──► FCM HTTP v1 API  │
└──────────────────────────────┘  │       └──────────────┬───────────────┘
                                  │                      │
                                  └──── Google FCM ◄─────┘
```

- **App:** Flutter with [Riverpod](https://riverpod.dev) for state,
  [drift](https://drift.simonbinder.eu) as the local SQLite database,
  [go_router](https://pub.dev/packages/go_router) for navigation and the
  [PocketBase Dart SDK](https://pub.dev/packages/pocketbase) for the API.
- **Widget:** Jetpack Glance (Kotlin), connected to Flutter via
  [home_widget](https://pub.dev/packages/home_widget). The app writes the
  widget data as JSON; checkbox taps run a Dart callback in a background
  isolate.
- **Server:** PocketBase built as a Go program, so it can sign the OAuth
  tokens needed for Firebase Cloud Messaging. The schema lives in JS
  migrations, business rules in JS hooks and API rules.
- **Push:** Firebase Cloud Messaging. Only the notification passes through
  Google; all other data stays on the server at home.

## Repository layout

```
lib/
  main.dart                    Entry point: preferences, widget callbacks, Firebase
  src/
    app.dart                   MaterialApp, lifecycle sync, widget/push launches
    routing/app_router.dart    Routes and login/household redirects
    theme/                     Light and dark theme
    common/                    Shared widgets (list switcher, dialogs, quick add)
    data/
      auth.dart                Login, registration, household create/join/leave
      db/database.dart         drift tables (generated: database.g.dart)
      sync/sync_service.dart   Push/pull/realtime sync engine
      repositories.dart        Local-first reads and writes for the UI
      recurrence.dart          Recurrence rules and next due date
      ids.dart                 Client-side PocketBase record ids
    features/
      auth/                    Login and registration screen
      household/               Create or join a household
      tasks/                   Task list, task tile, task editor
      shopping/                Shopping list
      settings/                Invite code, members, sync status, logout
      widget/                  Home screen widget data, actions, background sync
      push/                    Firebase Messaging registration and handling
android/
  app/src/main/kotlin/…/TasksWidget.kt   Glance home screen widget
  app/src/main/kotlin/…/MainActivity.kt  Notification channel
  app/google-services.json               Firebase app config (optional)
server/
  main.go                      PocketBase with JS plugins and push
  push.go                      FCM notifications on task assignment
  push_test.go                 Unit tests for the push logic
  pb_migrations/               Schema (collections, API rules, indexes)
  pb_hooks/                    Invite codes, join endpoint, guards
  Dockerfile, entrypoint.sh    Container image
  docker-compose.yml           Stack for Portainer
test/                          Flutter unit, widget and sync integration tests
.github/workflows/             CI, server image and release workflows
```

## App development

### Prerequisites

- Flutter (stable, see `FLUTTER_VERSION` in `.github/workflows/ci.yml`)
- Android SDK and an Android phone with USB debugging, or an emulator
- Optional: Docker, to run the server locally

### Run

```bash
flutter pub get
flutter run
```

On first start, the login screen asks for the server address (default
`http://casa-pazza.local:8090`). If Android cannot resolve `.local` names in
your network, use the IP address instead, e.g. `http://192.168.1.10:8090`.
Plain HTTP is allowed because the server runs in the home network.

### Code generation

The drift database code (`database.g.dart`) is generated. After changing
tables in `lib/src/data/db/database.dart`, run:

```bash
dart run build_runner build --delete-conflicting-outputs
```

Bump `schemaVersion` and add a migration when changing tables of an
existing release.

### Tests

```bash
dart format --set-exit-if-changed lib test
flutter analyze
flutter test
```

`test/sync_integration_test.dart` simulates two phones syncing through a real
PocketBase. It is skipped unless `PB_TEST_URL` points to a server with this
repository's schema (see [Server development](#server-development)):

```bash
PB_TEST_URL=http://127.0.0.1:8090 flutter test
```

## Server development

The server in `server/` is PocketBase as a Go module (the PocketBase version
is pinned in `server/go.mod`). It accepts the same flags as the official
binary.

### Run locally

With Go installed:

```bash
cd server
go run . serve --http=127.0.0.1:8090 --dir=/tmp/pb_data \
  --migrationsDir=pb_migrations --hooksDir=pb_hooks
```

Or with Docker:

```bash
docker build -t casa-pazza-pocketbase server
docker run --rm -p 8090:8090 casa-pazza-pocketbase
```

The dashboard is at `http://127.0.0.1:8090/_/`. On first start the log
prints a link to create the superuser. Alternatively set `PB_ADMIN_EMAIL`
and `PB_ADMIN_PASSWORD` (at least 10 characters) for the container.

### Tests

```bash
cd server
gofmt -l .
go vet ./...
go test ./...
```

### Data model

| Collection       | Purpose                                                   |
|------------------|-----------------------------------------------------------|
| `users`          | Accounts; `household` links each user to one household     |
| `households`     | Name and invite code                                       |
| `task_lists`     | Task lists of a household                                  |
| `tasks`          | Title, notes, assignee, due date, recurrence, done state   |
| `shopping_lists` | Shopping lists of a household                              |
| `shopping_items` | Name, quantity, checked state                              |
| `devices`        | FCM tokens per user (private to their owner)               |
| `app_secrets`    | Server-side secrets, superusers only                       |

All shared collections carry a `household` relation, a `deleted` flag (soft
delete) and `created`/`updated` timestamps. API rules restrict every request
to the caller's household. Users cannot set their household directly; they
create one or join via `POST /api/casa/join` with an invite code.
`POST /api/casa/invite-code` regenerates the code.

### Schema changes

Add a new file to `server/pb_migrations/` (never edit migrations that are
already deployed). PocketBase applies pending migrations on start, so
deploying a new image is enough.

## Deployment on a NAS with Portainer

The server image `ghcr.io/elrosch/casa-pazza-pocketbase` (amd64 and arm64)
is built by GitHub Actions on every push to `main` that touches `server/`.

### 1. Registry access

The repository is private, so the image is private as well. Create a
**classic** GitHub personal access token with only the `read:packages` scope
(GitHub → Settings → Developer settings → Personal access tokens → Tokens
(classic)) and add it in Portainer under *Registries → Add registry*:

- Registry URL: `ghcr.io`
- Username: your GitHub user
- Password: the token

### 2. Create the stack

In Portainer go to *Stacks → Add stack* and choose **Web editor**. Paste
the content of [`server/docker-compose.yml`](server/docker-compose.yml);
no environment variables are needed:

```yaml
services:
  pocketbase:
    image: ghcr.io/elrosch/casa-pazza-pocketbase:latest
    container_name: casa-pazza-pocketbase
    restart: unless-stopped
    ports:
      - "8090:8090"
    volumes:
      - pb_data:/pb_data

volumes:
  pb_data:
```

A *Repository* stack works too, but then Portainer also needs read access to
the private repository (a fine-grained token with *Contents: read-only*).

### 3. Create the superuser

Open the container logs in Portainer. On first start PocketBase prints an
installer link like `http://0.0.0.0:8090/_/#/pbinstall/…`. Replace
`0.0.0.0` with the address of the NAS and open it to create the superuser.
Afterwards the dashboard is available at `http://<nas>:8090/_/`.

### 4. Updating

After a new image has been built, open the stack in Portainer, click
**Update the stack** and enable **Re-pull image**. Migrations run
automatically on start; the data in the `pb_data` volume is kept.

### Backups

All data lives in the `pb_data` volume. PocketBase can also create and
schedule backups in the dashboard under *Settings → Backups*.

## Push notifications (Firebase Cloud Messaging)

Push is optional: without the configuration below the app works normally,
just without notifications. FCM is free of charge.

### Firebase project

1. Create a project in the [Firebase console](https://console.firebase.google.com)
   (Google Analytics is not needed).
2. Add an Android app with the package name `de.eliasrosch.casa_pazza` and
   download `google-services.json` to `android/app/google-services.json`.
   The Google Services Gradle plugin is only applied when this file exists.
3. Under *Project settings → Service accounts* generate a new private key.
   **Keep this JSON file secret and never commit it.**

### Server configuration

In the PocketBase dashboard open *Collections → app_secrets*, edit the record
with key `fcm_service_account` and paste the complete content of the service
account JSON into `value`. The server reads it on the next notification; no
restart is needed.

### What gets sent

- A notification is sent when a task is created or changed so that it is
  assigned to a different user than before, and that user is not the one
  making the change. Completed or deleted tasks do not notify.
- Text: "Neue Aufgabe für dich", body `<name of the assigner>: <task title>`.
  The task title passes through Google's servers; nothing else does.
- Tokens that FCM reports as unregistered are deleted. Logging out removes
  the phone's token.

On Android the notifications use the channel "Aufgaben", which can be
configured in the system settings of the app.

## CI/CD

| Workflow           | Trigger                         | What it does                                                                                     |
|--------------------|---------------------------------|--------------------------------------------------------------------------------------------------|
| `ci.yml`           | Push to `main`, pull requests   | Format check, `flutter analyze`, Go vet/tests, Flutter tests incl. sync test against the Go server, Android debug APK, unsigned iOS build |
| `server-image.yml` | Changes in `server/`, `v*` tags | Builds the multi-arch server image and pushes it to GHCR (`latest`, `sha-…`, version tags)        |
| `release.yml`      | `v*` tags                       | Builds a release APK and AAB and attaches them to a GitHub Release                               |

### Releases

```bash
git tag v1.0.0
git push origin v1.0.0
```

Without signing secrets the release is signed with debug keys. For a
properly signed release add these repository secrets:

| Secret                       | Content                                  |
|------------------------------|------------------------------------------|
| `ANDROID_KEYSTORE_BASE64`    | The upload keystore, base64 encoded      |
| `ANDROID_KEYSTORE_PASSWORD`  | Keystore password                        |
| `ANDROID_KEY_ALIAS`          | Key alias                                |
| `ANDROID_KEY_PASSWORD`       | Key password                             |

Locally, the same signing config is read from `android/key.properties`
(ignored by git).

## How sync works

- Every change is written to the local drift database first and marked
  `dirty`. Records get their PocketBase id on the phone, so they can be
  created offline.
- The sync engine pushes dirty rows (update, or create if the record does
  not exist yet), then pulls everything with an `updated` timestamp newer
  than the last pull per collection, then subscribes to realtime events.
- Sync runs on start, when the app returns to the foreground, when the
  network changes, every five minutes, shortly after local edits, after
  widget actions and when a push arrives.
- Conflicts resolve as last write wins. Pending local changes are never
  overwritten by pulled data.
- Deletions are soft deletes (`deleted = true`), so other devices learn
  about them during the pull.
- Each household gets a default task list and shopping list whose id equals
  the household id, so two phones creating them at the same time end up
  with the same record.

## Troubleshooting

- **"Server nicht erreichbar"**: check the address in the login screen
  (with `http://` and port). Try the NAS IP instead of `casa-pazza.local`.
  From another device, `http://<nas>:8090/api/health` should return
  `API is healthy`.
- **Widget shows old data**: the widget is updated by the app, by widget
  actions and by push messages. Opening the app always refreshes it.
- **No notifications**: check that the app may post notifications, that
  `fcm_service_account` is filled in `app_secrets`, and look for
  "push notification failed" in the dashboard under *Logs*. Assigning a
  task to yourself never notifies.
- **Portainer cannot pull the image**: the GHCR registry with a
  `read:packages` token must be configured (see
  [Registry access](#1-registry-access)).

## License

GPL-3.0, see [LICENSE](LICENSE).
