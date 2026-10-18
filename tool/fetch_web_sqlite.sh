#!/bin/sh
# Downloads the sqlite3 WebAssembly module and the drift web worker that the
# web build needs (see https://drift.simonbinder.eu/platforms/web/) into web/.
# Versions follow pubspec.lock, so they always match the Dart packages.
set -eu
cd "$(dirname "$0")/.."

locked() {
    awk -v pkg="$1" '$1 == pkg":" { found = 1 } found && $1 == "version:" { gsub(/"/, "", $2); print $2; exit }' pubspec.lock
}

SQLITE3=$(locked sqlite3)
DRIFT=$(locked drift)

curl -fsSL -o web/sqlite3.wasm \
    "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-$SQLITE3/sqlite3.wasm"
curl -fsSL -o web/drift_worker.js \
    "https://github.com/simolus3/drift/releases/download/drift-$DRIFT/drift_worker.js"
echo "web/sqlite3.wasm (sqlite3 $SQLITE3), web/drift_worker.js (drift $DRIFT)"
