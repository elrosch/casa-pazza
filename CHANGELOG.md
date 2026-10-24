# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-10-24

### Added

- Task view controls: show tasks due by today, by any chosen date or all
  dates, and independently one-off and/or recurring tasks. The choice is
  remembered and the task widget follows it.

### Fixed

- Widget buttons (scan, add task, edit task) and app shortcuts did nothing
  when the app was already running in the background.
- After the app had been closed by the system, reopening it could repeat the
  last widget action (e.g. open „Neue Aufgabe" again).

## [1.1.0] - 2026-10-24

### Added

- Barcode scanning for shopping lists: product names and package sizes are
  looked up in [Open Food Facts](https://world.openfoodfacts.org) and can be
  edited before adding.
- Shopping list home screen widget: see open items, check them off and start
  a barcode scan right from the home screen.
- Voice input: say „Salz auf die Einkaufsliste" or „Neues Todo für Elias:
  Wäsche waschen morgen"; the app understands shopping items, assignees and
  due dates and shows the result for a quick check before adding.
- App shortcuts (long-press the app icon): voice input, barcode scan and new
  task.
- Private task lists, visible only to their owner. Lists can be made private
  or shared again from the list menu.
- „Heute" view for tasks (default): shows tasks due today, overdue or without
  a date; „Alle" shows everything including future tasks. The task widget
  follows the same choice.

### Changed

- Checking off a recurring task in the „Heute" view moves it out of the view
  until it is due again, instead of showing it unchecked right away.
- Quantity detection understands spoken units like „2 Liter Milch" or
  „3 Flaschen Wasser".

### Upgrade notes

- Private task lists need the new server image: update the server before
  using them, otherwise private lists are still visible to the household.

## [1.0.1] - 2026-10-18

### Added

- About section in the settings with the app version, a link to the source
  code and the licenses.

### Changed

- Casa Pazza app icon instead of the Flutter default: adaptive and themed
  launcher icon on Android, matching notification icon.
- The web app uses the same icon for its favicon and when installed.

## [1.0.0] - 2026-10-18

### Added

- Households with personal accounts; members join with an invite code.
- Task lists with one-off and recurring tasks (every N days, weeks, months or
  years), due dates and assignees.
- Shopping lists with quick add and quantity detection (`2 l Milch`).
- Android home screen widget to see, check off, edit and add tasks.
- Push notifications for task assignments via Firebase Cloud Messaging
  (optional).
- Offline-first sync with a self-hosted PocketBase server, published as a
  Docker image.
- Web app for tasks and shopping lists, served by the same server.

[1.2.0]: https://github.com/elrosch/casa-pazza/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/elrosch/casa-pazza/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/elrosch/casa-pazza/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/elrosch/casa-pazza/releases/tag/v1.0.0
