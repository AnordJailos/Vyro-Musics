#!/usr/bin/env bash
# One codebase for Android, iOS, Windows and macOS, built with the latest tooling.
set -euo pipefail
cd "$(dirname "$0")"

flutter upgrade
flutter config --enable-windows-desktop --enable-macos-desktop
flutter create --org com.vyro --project-name vyro_music --platforms android,ios,windows,macos app

rm -rf app/lib app/test
cp -R app_src/lib app/lib
cp -R app_src/test app/test

cd app
flutter pub add just_audio just_audio_media_kit media_kit_libs_windows_audio
flutter pub add --dev fake_async
flutter pub upgrade --major-versions
flutter analyze
flutter test
echo "Done. Run it with: cd app && flutter run -d <android|ios|windows|macos>"
