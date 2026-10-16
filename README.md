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
npm test                      # 98 tests, run on an in-memory Postgres
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

## Catalog and Studio

Artists upload songs; listeners search and stream them; the mix engine can blend them.

- **Studio** (artist mode): upload a song (MP3, M4A, FLAC, WAV, OGG or AIFF, up to 300 MB), add a cover, set genre,
  explicit and "allow blending", then publish. The **Releases** tab lists your songs with Publish, Take offline and
  Delete. Removing a song deletes its files, but past plays still count in your statistics.
- **Listeners** (guests included): **Home** shows New on Vyro and Top this week; **Search** looks through Vyro and the
  music on the device together, each result labelled by where it lives.
- **Quality checks at upload**: at least 10 seconds; lossy files at 128 kbps or better; lossless at 22.05 kHz or better.
- **Streaming**: each play asks the server for a short-lived signed address (one hour), and the audio is served with
  byte ranges so seeking and fast starts work. Explicit songs are hidden from guests and anyone with explicit content off.
- **Server settings**: `STORAGE_DIR` (where files are kept, default `./data`) and, optionally, `FFMPEG_PATH`.
  With ffmpeg installed the server measures loudness (EBU R128) and makes a smaller AAC copy of lossless uploads to
  stream; without it, files are streamed as uploaded.
- **Not built yet**: resumable uploads, albums and releases, adaptive bitrates, and S3-style storage with a CDN (the
  storage layer is ready for it). Songs are reviewed before they go live: see the next section.

## Review, copyright and admin

Nothing goes live unchecked. When an artist submits a song ("Submit for release"):

1. **Fingerprint check**: the audio is fingerprinted (Chromaprint) and compared with every live, in-review and
   taken-down song. A copy from another artist, even re-encoded as MP3 or with the start cut off, puts the song
   **on hold**. The same artist re-uploading their own song is only flagged.
2. **Optional lookup against released music** (`ACOUSTID_API_KEY`): a match puts the song on hold. If the lookup is
   unavailable, the song waits for a person.
3. **Review policy** (`REVIEW_POLICY`): `all` (default) sends every clean song to a reviewer; `new_artists` lets verified
   artists, and artists with three approved songs, go live directly; `none` lets clean songs go live. Audio that could not
   be fingerprinted **never skips review**, whatever the policy.
4. New audio for an existing song takes it offline until it is reviewed again, so an approved song cannot be swapped.

- **Staff**: roles are `user`, `moderator` and `admin`. Make the first admin with `ADMIN_EMAILS=you@example.com` (applied
  at start, for confirmed emails) or `npm run make-admin -- you@example.com`. Staff see an **Admin console** on the
  Account screen: the review queue (listen first, approve or reject with a reason the artist is told, bulk actions),
  copyright notices, and artists (verify, suspend, restore). Every decision goes into an audit log (admins can read it
  through `GET /v1/admin/audit`).
- **Copyright notices**: a rights holder can send a notice (`POST /v1/takedown-notices`); the song goes offline at once,
  including streaming links already handed out; the artist can send a counter-notice; a reviewer upholds or restores it.
  **Three upheld notices suspend the artist** (repeat-infringer policy). Suspended people are signed out everywhere,
  cannot sign in, and their songs are hidden.
- **Fingerprint tool**: install `fpcalc` (Chromaprint: `apt install libchromaprint-tools`, `brew install chromaprint`) or
  an ffmpeg built with Chromaprint. Without either, nothing can be checked and every song waits for a person.
- **Before real launch**: the wording and time limits of the notice process need a lawyer for each country; AcoustID's
  free service is for non-commercial use (a commercial app needs an agreement with them, or a paid service such as
  ACRCloud or Audible Magic behind the same interface); and anyone can send a notice, so decide how rights holders are
  verified before you rely on it.

## Progress checklist

`docs/progress.md` is the checking document. It starts with a readiness report (where things stand, what works today,
what is not ready and why, known risks, a plain-word state for each module), then lists every requirement, module by
module, with its own status and a plain-language note. The report text lives in `docs/status.json` under `meta.report`. It is
generated, so edit `docs/status.json` (one entry per requirement that has any progress) and then run:

```bash
node tools/progress.mjs                          # rewrites docs/progress.md
node tools/progress.mjs --module AUTH            # prints just one module, to show or paste
node tools/progress.mjs --module AUTH,ART --out accounts.md
node tools/progress.mjs --only done,built        # only what is finished or written
```

The script stops if `status.json` names a requirement or status that does not exist, so the checklist cannot drift
away from `docs/requirements.md`.

## Profile and privacy

- **Profile** (Account screen): name, username, **photo**, **country** and **language**. A listener's photo is private to them;
  an artist's photo is part of their public page. Pictures up to 5 MB (JPEG, PNG or WebP). The language choice is saved,
  but Vyro is not translated yet.
- **Privacy controls**: *Private session* (plays are not kept in your history and are not linked to you), *Personalized
  recommendations*, and *Share my country with artists* (off: your plays still count for the artist, without a country).
  *Show my listening on my profile* and *Hide my activity from friends* are saved but apply to nothing yet, because there
  are no friends or public listener profiles.
- **Download my data** copies everything linked to your account to the clipboard as readable text: profile and settings,
  taste picks, follows, liked songs, "not interested" choices and the plays linked to you (plays from a private session were
  never linked). Artists also get a list of their songs. It is limited to 5 requests an hour.
- **Deleting an account** removes the rows and the files (songs, covers, photo). Plays that artists already count stay as
  anonymous numbers.

## Finding music

- **Search** finds songs and artists on Vyro even with typos and missing accents ("nova wve" finds Nova Wave), plus songs on
  your device. With one or two letters typed it suggests names instead. Searches you submit or use are remembered
  (Recent searches, with remove and clear).
- **Browse by genre** and **Charts** (top songs, top artists, rising artists; worldwide or your own country) are on the
  Search screen when nothing is typed. Charts also has a button on Home.
- **Artist pages**: popular songs, all songs, about and links, similar artists, and Follow. Open one from search, the charts,
  similar artists, or by tapping the artist's name under any song.
- **Continue listening** on Home lists what you played lately (songs on your device only while the file is still there).
- Songs have only a genre so far, so browsing by mood, activity, decade and language is not possible yet. Vyro has no albums,
  so there are no album pages or albums chart.

## Recommendations

For someone with little or no listening history yet, **Home** shows, above "New on Vyro":

- **Picked for you**: songs from the artists and genres chosen in the taste picker (a picked artist counts more than a genre,
  then the most played), with at most three songs per artist. Left out for guests and when personalization is paused.
- **Popular in your country**: the most played songs there in the last 28 days (only real plays count). When a country has
  fewer than five songs with plays, it shows **Popular on Vyro** instead.
- **Lists chosen by Vyro's staff**: see below.

Every row has "Not interested" and "Don't suggest this artist" in its menu, and **Account, Reset recommendations** forgets
those choices and the taste picks. Explicit songs, unpublished songs and suspended artists are left out everywhere.

Staff (moderators and admins) manage the lists through the server for now:

```bash
# create (use "published": false to keep it as a draft); "trackIds" are song ids, in the order to show them
curl -X POST http://localhost:3000/v1/admin/editorial -H "Authorization: Bearer STAFF_TOKEN" -H "Content-Type: application/json" \
  -d '{"title":"Late night","description":"For after dark","trackIds":["SONG_ID"],"published":true,"position":1}'
curl http://localhost:3000/v1/admin/editorial -H "Authorization: Bearer STAFF_TOKEN"            # all lists
curl -X PUT http://localhost:3000/v1/admin/editorial/LIST_ID ...  # same body; replaces the songs
curl -X DELETE http://localhost:3000/v1/admin/editorial/LIST_ID -H "Authorization: Bearer STAFF_TOKEN"
```

## Your library

- **Browse** by songs, albums, artists, genres and folders (tap a genre or folder to open it). **Library settings** (the sliders
  button) shows the folders being looked at, lets you **leave a folder out** (for example voice notes) and include it
  again, and sets how short a song can be and still be kept: keep everything, 10 or 30 seconds, 1 or 2 minutes.
- **Likes**: a heart on every song (songs on your device, songs on Vyro, and the Now Playing screen). The **Liked** tab shows
  all of them together with a Vyro or Local badge. Likes of Vyro songs are saved on the server for signed-in people, so
  they follow you to another device; made while signed out or offline, they wait and are sent later.
- **Delete from device**: in a song's menu, after a confirmation. The file is deleted for good, and the song leaves the
  library, the queue and every playlist. If the file cannot be deleted (in use, or protected by the system), the song stays.

## Playlists

- Make playlists in the **Playlists** tab of the Library, with a name, a description and a cover picture. They are kept on
  this device (syncing across devices needs the server and is not built yet).
- Add a song from the **...** menu on any song row (Home, Search, Library) or the playlist button on Now Playing. The sheet
  can also start a new playlist. A song already in the playlist is noticed, with "Add anyway".
- Playlists can mix songs from your own files and from Vyro, each with a badge. A playlist plays like any queue (Play,
  Shuffle, or tap a song).
- In a playlist: drag to reorder, long-press to select several songs (remove, add to the queue, add to another playlist),
  sort by title, artist, date added or length, and remove duplicates.
- Not built: saving albums and mixtapes (needs albums on Vyro), YouTube links, public or shared playlists.

## Playing music

- **Shuffle** plays the queue in a random order, starting with the song that is playing; switching it off puts the original
  order back, including songs added in the meantime.
- **The queue**: the queue button on the Now Playing screen shows what is playing, what is next (drag to reorder, remove, or
  clear) and what was played before (tap to play again). Song rows in Home, Search and the Library have a menu with
  **Play next** and **Add to queue**.
- **Swipes**: flick the mini player or the artwork sideways to skip, and flick the mini player up to open Now Playing.
- **Picking up where you left off**: the queue, the settings and the place in the song are saved on the device (every few
  seconds while playing, and when the app goes to the background). The next start shows them paused and ready.
  Nothing loads until play is pressed.
- **Connection trouble**: a spinner shows while a song buffers. If the connection drops mid-song, the player waits and tries
  again after 1, 2 and 4 seconds, from where it stopped (asking for a fresh address each time); then it stops and says so,
  and pressing play continues from the same spot. Songs on the device are not retried. Lowering the quality instead of
  stalling needs several versions of each song and is not built yet.

## Lyrics

- **Artists** add lyrics in the Studio (Releases, then the song's menu, then **Add lyrics**): type or paste them, or import
  a `.lrc` or `.txt` file. Lyrics with times in front of each line, like `[01:23.45] a line`, follow the music; lyrics
  without times are shown as plain text. Several times on one line, an `[offset:+500]` tag and word-by-word stamps are
  understood. Lyrics can be changed on a live song without taking it offline.
- **Listeners** open the Now Playing screen and tap the lyrics button. The line being sung is highlighted and scrolled
  into view, and tapping a line jumps to it. Lyrics of explicit songs follow the explicit-content setting. A flag button
  lets a listener report wrong words, wrong timing, offensive content or copied lyrics; the artist is told once per person.
- **Your own files** show lyrics from a `.lrc` file with the same name next to the song (then a `.txt`), or from lyrics
  stored inside the file's tags.
- **Not covered yet**: lyrics are not reviewed by a person (an artist could paste lyrics they do not own, so the editor
  says only to add lyrics you have the right to share, and reports reach the artist, not a moderator), there is no tap-to-time
  editor, and no translation.

## Listening history

Every play is recorded on the device, with how long you really listened (a seek forward adds nothing, and pausing does not
end a play). Plays of Vyro songs are also sent to the server, so artists see real numbers and your profile fills in.

- **Kept on the device**: the history, so your profile can also count music from your own files. **Clear listening history**
  (Account screen) removes it. Demo songs and reviewer previews are never recorded.
- **Sent to the server**: only Vyro songs, in batches, whenever someone is signed in. Offline plays wait and are sent
  later; every play has its own id, so nothing is counted twice; one bad play cannot block the rest. Guests' Vyro plays wait
  and are sent when they sign in.
- **Private session** (Account screen): the play is not kept in your history; the server still counts it for the artist,
  without linking it to you. Turning personalization off does the same on the server.
- **Profile**: Vyro listening from the server plus music from your own files, with the streak worked out from both. With
  no connection, the profile is built from the history on the device.

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