# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[1.0.1]: https://github.com/elrosch/casa-pazza/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/elrosch/casa-pazza/releases/tag/v1.0.0
