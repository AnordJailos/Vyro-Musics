# Vyro Music

One Flutter codebase for **Android, iOS, Windows and macOS**, plus a Node/Postgres backend.

```
server/    Fastify + PostgreSQL API: accounts, listener and artist roles, feature flags
app_src/   Flutter source (lib/ and test/): theme system, Play Y logo, listener/artist shell,
           two-deck mix engine with Normal and Mixing modes
docs/      Requirements document
setup.sh   Builds the Flutter app with the latest tooling
```

## Backend

Needs Node 22+ and PostgreSQL (use the current stable release).

```bash
cd server
npm install
npm test                      # 50 tests, run on an in-memory Postgres
export DATABASE_URL=postgres://user:pass@localhost:5432/vyro
export JWT_SECRET=$(openssl rand -hex 32)
npm run dev
```

## App (Android, iOS, Windows, macOS)

Needs the latest stable Flutter and Node 22+. Run `./setup.sh` (macOS, Linux or Git Bash on Windows). It
upgrades Flutter, generates the platform folders, installs the newest version of every package, applies the
one-time platform settings (`tools/patch-platforms.mjs`), then runs `flutter analyze` and `flutter test`.
By hand:

```bash
flutter upgrade
flutter create --org com.vyro --project-name vyro_music --platforms android,ios,windows,macos app
rm -rf app/lib app/test && cp -R app_src/lib app/lib && cp -R app_src/test app/test
cd app
flutter pub add just_audio just_audio_media_kit media_kit_libs_windows_audio audio_service audio_session \
  file_picker path_provider permission_handler audio_metadata_reader
flutter pub add --dev fake_async
flutter pub upgrade --major-versions
node ../tools/patch-platforms.mjs .
flutter analyze && flutter test
flutter run -d <android|ios|windows|macos>
```

### Applying updates

Updates arrive as git patches. In your repo: `git am path/to/0001-*.patch` (then the next one). If the update
adds packages, run `./setup.sh` again (it keeps the existing `app/` folder and is safe to repeat); if it only
changes code, `./sync.sh` is enough.

### What the platform script changes

- **Android**: internet, wake lock, foreground-service and notification permissions; permission to read music
  (`READ_MEDIA_AUDIO`, and storage up to Android 12); the audio activity, service and media-button receiver.
- **iOS**: the audio background mode, so music keeps playing when the app is not on screen.
- **macOS**: network and picked-file entitlements, and the **App Sandbox is turned off** so the app can read your
  real Music folder. Fine for development and for apps shipped outside the Mac App Store; a store release needs the
  sandbox back on, with saved folder permissions.
- **Windows**: nothing to patch. Install Visual Studio with "Desktop development with C++" and turn on Developer Mode.

### Background playback

Android, iOS and macOS show the song in the notification or Now Playing area and respond to the lock screen
(not macOS), headset buttons and Bluetooth. Windows media keys and the Windows media overlay are a separate step.

### Local music library

Scans the usual music folders (Music and Download on Android, `Music` on Windows and macOS), reads tags in a
background thread, and only re-reads files that changed. Hidden folders and clips under 30 seconds are skipped.
You can also add a folder or pick songs. iOS cannot scan the device, so songs come in through "Add songs".
Songs are grouped into Songs, Albums, Artists and Liked, with search; tapping a song plays it with the mix engine.

## Accounts and sign-in

Sign-up and log in with email and password (with an emailed confirmation code), with a phone number and a texted
code, or with Google or Apple. Also: guest mode, a first-launch taste picker, password reset, age rules (under 13
cannot join, 13 to 15 need a parent's emailed code, explicit content stays off under 18), privacy switches
(private session, personalized recommendations), account deletion, and "Become an artist".

- **Server settings**: `DATABASE_URL`, `JWT_SECRET`, and optionally `GOOGLE_CLIENT_IDS` and `APPLE_CLIENT_IDS`
  (comma-separated). Until an email and SMS provider is connected (`server/src/messaging.ts`), **codes are printed in
  the server console**: look there to find the code you need to type in the app.
- **App server address**: `flutter run --dart-define=API_URL=http://10.0.2.2:3000` on an Android emulator. Other
  platforms default to `http://localhost:3000`.
- **Needs from you before real sign-ups**: an email provider, an SMS provider, your Google and Apple client IDs with
  the sign-in plugins (the buttons say "not set up" until then), and the final Terms, Privacy Policy and artist
  agreement (the screens show placeholders). The age limits are a starting point and need legal review per market.
- **Saved login**: held in the system's secure storage. If a platform refuses it, the app keeps working and the
  person simply logs in again next launch. Without a connection the app opens with the last saved profile.

## Statistics

Two screens, one set of numbers (Flutter screens now use demo data until login is wired up):

- **Artist dashboard** (artist mode, Stats tab): period picker with comparison to the period before,
  last-48-hours view, plays / listeners / followers / saves, daily trend, new / returning / super listeners,
  countries and sources of plays, song table with finish and skip rates, a per-song retention curve,
  and which songs get mixed with yours.
- **Listener profile** (listener mode, Profile tab): minutes listened, streak, top artists / songs / genres,
  listening clock and personality, songs blended, new artists found, and a privacy switch.

API (all under `/v1`): `POST /events/listens`, `GET /artists/me/stats?range=7d|28d|90d|365d`,
`GET /artists/me/tracks/:id/retention`, `GET /artists/:id/public`, `GET /me/stats?range=4w|6m|year|all&tzOffsetMinutes=`,
`POST|DELETE /artists/:id/follow`, `POST|DELETE /tracks/:id/save`.

Rules built in: a play is a stream after 30 seconds (or half of a very short track); retried uploads never
double count; breakdowns hide groups smaller than 5 listeners; deleting an account anonymizes its plays so
artists' totals stay right.

## Playback modes

- **Normal**: songs change one after another with no overlap (next, back, and end of song).
- **Mixing**: the next or previous song is blended in on a skip, and the next song is blended in
  automatically as a song ends. Blend lengths (1 to 12 s) are set separately for "end of song" and
  "next / back". YouTube and license-restricted tracks always change with a clean cut.
