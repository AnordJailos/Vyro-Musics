#!/usr/bin/env bash
# One codebase for Android, iOS, Windows and macOS, built with the latest tooling.
set -euo pipefail
cd "$(dirname "$0")"

flutter upgrade
flutter config --enable-windows-desktop --enable-macos-desktop
# Only generate the platform folders the first time; later runs keep them as they are.
if [ ! -f app/pubspec.yaml ]; then
  flutter create --org com.vyro --project-name vyro_music --platforms android,ios,windows,macos app
fi

rm -rf app/lib app/test
cp -R app_src/lib app/lib
cp -R app_src/test app/test

cd app
# Without version numbers, pub picks the newest release of each package.
flutter pub add just_audio just_audio_media_kit media_kit_libs_windows_audio \
  audio_service audio_session file_picker path_provider permission_handler audio_metadata_reader
flutter pub add --dev fake_async
flutter pub upgrade --major-versions

# One-time platform settings: Android permissions and audio service, iOS background audio,
# macOS entitlements. Needs Node (the same Node the server uses).
node ../tools/patch-platforms.mjs .

flutter analyze
flutter test
echo "Done. Run it with: cd app && flutter run -d <android|ios|windows|macos>"
