#!/usr/bin/env bash
# After applying an update that only changes code (no new packages), copy the sources
# into the Flutter app and refresh it. For updates that add packages, run ./setup.sh instead.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf app/lib app/test
cp -R app_src/lib app/lib
cp -R app_src/test app/test

cd app
flutter pub get
flutter analyze
flutter test
