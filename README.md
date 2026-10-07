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
npm test                      # 27 tests, run on an in-memory Postgres
export DATABASE_URL=postgres://user:pass@localhost:5432/vyro
export JWT_SECRET=$(openssl rand -hex 32)
npm run dev
```

## App (Android, iOS, Windows, macOS)

Needs the latest stable Flutter. Run `./setup.sh` (macOS, Linux or Git Bash on Windows), or by hand:

```bash
flutter upgrade
flutter create --org com.vyro --project-name vyro_music --platforms android,ios,windows,macos app
rm -rf app/lib app/test && cp -R app_src/lib app/lib && cp -R app_src/test app/test
cd app
flutter pub add just_audio just_audio_media_kit media_kit_libs_windows_audio
flutter pub add --dev fake_async
flutter pub upgrade --major-versions
flutter analyze && flutter test
flutter run -d <android|ios|windows|macos>
```

### One-time platform steps

- **Android**: add `<uses-permission android:name="android.permission.INTERNET"/>` to
  `app/android/app/src/main/AndroidManifest.xml` (release builds need it for streaming).
- **macOS**: add `<key>com.apple.security.network.client</key><true/>` to both
  `app/macos/Runner/DebugProfile.entitlements` and `app/macos/Runner/Release.entitlements`.
- **Windows**: install Visual Studio with the "Desktop development with C++" workload and turn on
  Developer Mode (Flutter plugins need symlinks).

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
