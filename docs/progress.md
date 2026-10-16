# Vyro Music: what is built

Checked against requirements document version 0.9 · updated 12 October 2026

Every requirement is listed under its module, with its own status. Look up a requirement by its ID.

## Where things stand

Vyro Music is a working prototype, not a finished product. The server (accounts, uploads, streaming, review and copyright checks, statistics, recommendations, lyrics) is built and has been run: its 166 automated checks pass, including checks with real audio files. The app (listening and mixing, library, playlists, queue, lyrics, the artist Studio and the admin console) is written, with automated checks of its own, but none of it has been run yet on a phone or a computer.

So "Built" in this document means written and ready to be tested, not proven. The first real milestone is to run the setup script and the app's checks on your machine and fix what they find.

Nothing can be opened to the public yet. What stands in the way is listed below: outside services to connect, legal documents, store accounts and hosting, and the launch-level features that are still missing.

Launch-level features still missing: YouTube search and playback, album pages and albums (Vyro has none yet), browsing by mood, activity, decade and language, sharing and deep links, blocking and reporting users, accessibility, translations and an onboarding tour, resumable uploads and release types, claiming an artist profile, and almost all of the operations work (environments, monitoring, backups, beta, support, store listings).

## What works today

- **Accounts**: Sign up and log in with email (with confirmation) or a phone code, Google and Apple sign-in on the server side, guest mode, age rules with parent consent, password reset, a saved login, a profile with photo, country and language, privacy controls (private session, sharing your country with artists, personalization), a download of your data, and account deletion that removes every file.
- **Artists and uploads**: Upgrade a listener account to an artist account, upload songs (MP3, M4A, FLAC, WAV, OGG, AIFF, up to 300 MB), cover art, loudness measured at upload, and submit a song for release.
- **Review and safety**: Copies of songs already on Vyro are caught by audio fingerprint, a reviewer queue with approve, reject and bulk actions, copyright notices with counter-notices, automatic suspension after three upheld notices, roles (listener, moderator, admin) and an audit log.
- **Streaming**: Songs stream from short-lived secure links and can be played from any point. Explicit songs are hidden from guests and from anyone who turned them off.
- **The player**: Normal and Mixing modes with crossfades, shuffle and repeat, a queue (play next, reorder, remove, history), swipe gestures, picking up where you left off after the app was closed, a buffering spinner with automatic retries, and lock-screen controls.
- **Library**: Scan folders on the device, read tags, browse by songs, albums, artists, genres and folders, leave folders out, ignore short clips, like any song (on the device or on Vyro, saved on the server for signed-in people), and delete a song from the device.
- **Playlists**: Create and edit playlists with a cover picture, mix songs from your own files and from Vyro, drag to reorder, sort, select several songs, and remove duplicates.
- **Lyrics**: Artists add synced or plain lyrics in the Studio. Listeners see the current line highlighted. Songs on the device use a .lrc file next to them or lyrics stored inside. Listeners can report wrong lyrics.
- **Discovery**: Home shows Continue listening, picks from the taste picker, what is popular in your country, and lists chosen by staff, with "Not interested" and a reset. Search finds songs and artists even with typos, with suggestions, recent searches and browsing by genre. Artist pages (with follow) and charts of songs, artists and rising artists.
- **Statistics**: An artist dashboard (plays, listeners, audience split, per-song listening, countries) and a listener profile, both filled by real plays recorded by the app.
- **Admin console**: For reviewers: the review queue, copyright notices, and artist management (verify, suspend, restore).

## What is not ready

### Needs something from you or an outside service

- **An SMS service**: Phone sign-in codes only print on the server's screen until a provider is connected. Affects: AUTH-01.
- **An email service**: Confirmation, password reset and parent-consent emails also only print on the server's screen. Affects: AUTH-02, AUTH-07, AUTH-09.
- **Google and Apple developer accounts**: The sign-in buttons say "not set up" until client IDs and the sign-in plugins are added. Affects: AUTH-03.
- **A copyright lookup service you may use commercially**: Matching against music released elsewhere is connected but switched off. The free AcoustID service is for non-commercial use only; a commercial app needs an agreement with them or a paid service. Affects: STU-07, BKE-06, SAF-02.
- **Legal review**: The terms, privacy policy and artist agreement are placeholders. The age limits, the copyright notice wording and time limits, music licensing and royalty reporting, and the "Vyro Music" name all need a lawyer for each launch market. Affects: ART-06, AUTH-09, SAF-01, SAF-02, SAF-08, SAF-09.
- **Apple and Google store accounts, and push services**: Store policy checks, store listings, and push notifications cannot start without them. Affects: SAF-10, OPS-05, BKE-09.
- **Hosting and operations**: The server keeps files on its own disk and has no deployment set-up, monitoring, backups or content delivery network yet. Affects: BKE-03, BKE-10, BKE-11, BKE-12.
- **Real phones for testing**: Audio focus for calls, lock-screen controls, folder access and background audio on Android and iOS, and the speed and size targets, can only be confirmed on devices. Affects: PLY-02, PLY-05, LIB-01, DEV-03, NFR-01, NFR-02, NFR-06.
- **A YouTube policy review**: YouTube search and playback are not started, and the requirements demand a compliance review before every release. Affects: SRC-04, SRC-09.
- **Real artists and testers**: The seed catalog and the closed beta need people, not code. Affects: OPS-01, OPS-02.

### Written, but never run on a device

The app's automated checks are written for every feature but have never been run, because the build tools for the app (Flutter) are not available where this was developed. Expect some compile errors and a few failing checks on the first run; they are normally quick to fix. Until then, treat every Built item that involves the app as unconfirmed. The server side is different: it has been run, and its checks pass.

### Launch-level features that are only partly built

- **AUTH-01** [M] Sign up and log in with phone number and one-time code. Phone sign-in works and the screens are built. Codes are not actually sent yet: an SMS service still needs to be connected.
- **AUTH-03** [M] Social sign-in with Google, plus Sign in with Apple on iOS. Google and Apple sign-in are checked by the server. The buttons say "not set up" until your Google and Apple developer accounts are connected.
- **AUTH-10** [M] Privacy controls: private listening session, hide activity, control data sharing. Private session, "Share my country with artists" (off means plays count without a country), personalized recommendations, and a download of your data are real controls. "Hide my activity" and "Show my listening on my profile" are saved but apply to nothing yet, because friends and public profiles do not exist.
- **ART-03** [M] Artist profile: stage name, bio, photo, banner, genres, social links. Name, type, bio, genres and links are stored. Photo and banner are missing.
- **ART-06** [M] Non-exclusive streaming agreement; the artist keeps ownership. The agreement version is recorded and a draft agreement is shown. The real text needs legal review.
- **ART-08** [M] Impersonation protection: name-similarity checks and a report flow. Look-alike names (letter case, spaces, punctuation, accents) are blocked. A reporting flow is missing.
- **ART-09** [M] Artists keep all listener features; their listening informs recommendations (opt-out available). Artists use the same app and library. Using their listening for recommendations is not built.
- **STU-03** [M] Metadata: title, featured artists, genre, mood, language, explicit flag, release date, credits, optional ISRC. Title, genre, explicit, allow-blending and length are stored. Featured artists, mood, language, release date, credits and ISRC are missing.
- **STU-04** [M] Cover art upload with size and ratio checks. JPEG, PNG and WebP covers up to 5 MB are checked and stored. Size and ratio checks are missing.
- **STU-06** [M] Automatic quality checks (clipping, silence, bitrate, upsampled fakes) with clear feedback. Length, bitrate and sample-rate checks. Clipping, silence and fake-upsample checks are missing.
- **STU-08** [M] Draft, schedule, publish, unpublish and delete releases. Draft, submit for release, withdraw and delete work. Scheduling is missing.
- **STU-09** [M] Edit metadata after publishing, with change history. The server can change title, genre, explicit and blending after publishing. There is no screen for it and no change history.
- **LIB-01** [M] Scan internal storage and SD card, with background incremental rescans. Scans the Music and Download folders (Android), the Music folder (desktop) and any folder you add; only changed files are re-read. Automatic background rescans are missing.
- **LIB-03** [M] Read tags (ID3, Vorbis, MP4) and embedded artwork. Tags are read. Cover art is not.
- **LIB-06** [M] One unified library for local and online tracks, with source badges. The Liked tab brings songs from the device and from Vyro together, each with a "Local" or "Vyro" badge, and playlists mix both. The Songs, Albums, Artists, Genres and Folders views still show only songs on the device.
- **SRC-01** [M] Stream Vyro artist uploads with adaptive quality. Songs stream from short-lived secure links and can be played from any point. Adaptive quality is missing.
- **SRC-02** [M] Source badge on every track (Local, Vyro, Open, YouTube) plus a "Mixable" indicator. "Vyro" and "On device" badges in search and on Vyro songs. No "Mixable" indicator yet.
- **SRC-06** [M] YouTube items never enter the mix engine; transitions to or from them are a clean cut. The mix engine never blends YouTube or license-restricted tracks. YouTube playback itself is not built.
- **PLY-05** [M] Correct audio-focus handling for calls, navigation and other apps. The audio session is set up for music so calls and other apps are handled by the system. Not tested on a phone.
- **PLY-08** [M] Network resilience: buffering indicator, auto-retry, drop to a lower bitrate instead of stalling. A buffering spinner and automatic retries (after 1, 2 and 4 seconds, from where the song stopped) are built. Dropping to a lower quality needs several versions of each song, which do not exist yet.
- **DSC-01** [M] Unified search across tracks, artists, albums, playlists, users and local files. Songs and artists on Vyro, found even with typos and missing accents, plus songs on the device. Albums, playlists and users cannot be searched yet, because Vyro has no public albums, playlists or user pages.
- **DSC-03** [M] Browse by genre, mood, activity, decade and language. Browse by genre, from the Search screen. Mood, activity, decade and language are missing, because songs do not carry those details yet.
- **DSC-05** [M] Charts: trending, top songs, albums and artists; global and per country; rising artists. Top songs, top artists and rising artists, worldwide or for your own country. An albums chart is missing, because Vyro has no albums yet.
- **PLS-02** [M] Add any source (local, Vyro, YouTube link) to a playlist, with badges. Songs from your own files and from Vyro can be added from any song row or from Now Playing, each shown with a "Vyro" or "Local" badge. YouTube links are not built yet.
- **STA-01** [M] Dashboard: plays, unique listeners, followers, saves, playlist adds, with date ranges. Plays, listeners, followers and saves with date ranges, filled by real plays once the app sends them. Saves now include the likes made in the app. Playlist adds are missing.
- **STA-02** [M] Per-track stats: completion rate, skip rate, replays, average listen time. Finish rate and skip rate per song. Replays and average listen time are missing.
- **BKE-01** [M] Versioned API with rate limiting. A versioned API. Rate limits exist for sign-in only.
- **BKE-02** [M] PostgreSQL for users, catalog and playlists; separate analytics store for events. A database holds users, artists, songs, follows, saves and plays. Playlists and a separate analytics store are missing.
- **BKE-03** [M] Object storage for masters and encoded files, delivered through a CDN. Files are stored on the server's disk behind a storage layer. Cloud storage and a content delivery network are missing.
- **BKE-04** [M] Transcoding pipeline: master to AAC at multiple bitrates and Opus; adaptive HLS; optional lossless tier. Lossless uploads get a smaller streaming copy (needs the ffmpeg tool installed on the server). Several bitrates and adaptive streaming are missing.
- **BKE-06** [M] Audio fingerprinting for duplicates and copyright matches. Copies of songs already on Vyro are detected by audio fingerprint, even re-encoded ones. Matching against music released elsewhere needs a licensed lookup service.
- **BKE-07** [M] Search engine with typo tolerance and multilingual support. Search uses the database (prefix matches first). Typo tolerance and a search engine are missing.
- **BKE-13** [M] Feature-flag and remote-config service. A table of feature switches and a way to read them. There is no admin screen to change them.
- **QUA-02** [M] Upload quality gates (minimum bitrate, fake-upsample detection). Bitrate, sample-rate and length gates. Fake-upsample detection is missing.
- **DEV-01** [M] iOS and Android apps with a shared UI codebase and native audio engine modules. One shared codebase for every platform. A custom native audio engine is not built.
- **DEV-03** [M] Correct background-audio setup: iOS background mode, Android foreground service, battery-optimization handling. The setup script adds the Android service and permissions and the iOS background mode. Battery-optimization handling is missing.
- **SAF-03** [M] Moderation queue for uploads, profiles, images and comments. A moderation queue for uploads. Profiles, images and comments are missing.
- **SAF-06** [M] Data minimization; encryption at rest and in transit. Passwords are stored securely hashed. Encryption in transit comes with deployment.
- **PRF-01** [M] Profile header: photo, name and username. Header shows the real name and username. No photo yet.
- **PRF-08** [M] Switch to keep listening stats private, only visible to the listener. Saved on the server and shown on the profile; there is no public profile yet to apply it to.
- **ADM-01** [M] Admin console with roles and an audit log. Roles (listener, moderator, admin) and a record of every decision exist, and the Admin console is built. The record has no screen yet.
- **ADM-03** [M] User and artist management: suspend, verify, merge duplicates. Search artists, verify, suspend and restore. Merging duplicate accounts is missing.
- **NFR-10** [M] Automated unit, integration and audio-regression tests, including mixing. The server has 166 automated checks, all passing. The app's checks are written but have not been run yet.

### Launch-level features not started

- **ART-07** [M] Claim an auto-created artist profile through verification.
- **STU-02** [M] Resumable uploads that survive weak networks and app restarts.
- **STU-05** [M] Release types: single, EP, album, mixtape, DJ mix.
- **SRC-04** [M] YouTube search integrated into Vyro search, in its own section.
- **SRC-05** [M] YouTube plays only through the official player, in the foreground, with video visible and unmodified.
- **SRC-07** [M] No download, offline copy, audio extraction or background play of YouTube items.
- **SRC-08** [M] YouTube items can be saved to playlists as links only, clearly marked.
- **SRC-09** [M] YouTube policy compliance review before every release, with a remote switch to disable YouTube instantly.
- **DSC-07** [M] Album/release page with credits, duration and total tracks.
- **PLS-04** [M] Save albums and mixtapes to the library.
- **SOC-01** [M] Share tracks, albums, artists and playlists via link; deep links open the app or the store page.
- **SOC-02** [M] Block, mute and report users and content (required for user-generated content).
- **UIX-02** [M] Smooth 60 fps animations with no layout jumps.
- **UIX-03** [M] Accessibility: VoiceOver and TalkBack, scalable text, high contrast, color-blind-safe palettes, large touch targets.
- **UIX-04** [M] English at launch, with a localization system and right-to-left support ready for more languages.
- **UIX-05** [M] Smooth performance on low-end phones (2 GB RAM) and small app size.
- **UIX-06** [M] Short onboarding tour explaining mixing, lyrics and offline.
- **BKE-09** [M] Push notification service (APNs and FCM) with user preferences.
- **BKE-10** [M] Staging and production environments, infrastructure as code, CI/CD.
- **BKE-11** [M] Monitoring, logging, alerting and error tracking.
- **BKE-12** [M] Backups and a disaster-recovery plan with tested restores.
- **QUA-01** [M] Normal streaming at 128 kbps or higher (Opus/AAC); High at 256 kbps or higher. Free-tier ceiling to be decided.
- **SAF-01** [M] Terms of Service, Privacy Policy and artist agreement reviewed by legal counsel in each launch market.
- **SAF-04** [M] Explicit-content labeling and filtering.
- **SAF-07** [M] Child-safety rules: age limits, no targeting of minors, reporting channel.
- **SAF-08** [M] Music licensing and royalty-reporting obligations (publishing and performance rights) confirmed per market.
- **SAF-09** [M] Trademark and name clearance for "Vyro Music" (pending).
- **SAF-10** [M] App Store and Google Play policy checklist, including user-generated-content rules.
- **NFR-01** [M] Start-to-play under 1.5 seconds on 4G for Vyro tracks (75th percentile).
- **NFR-02** [M] Cold start under 2 seconds on mid-range phones.
- **NFR-03** [M] Crash-free sessions of at least 99.5%.
- **NFR-04** [M] Streaming API availability of at least 99.9%.
- **NFR-05** [M] Supported OS: Android 8+ and iOS 16+ (confirm against market device data).
- **NFR-06** [M] Install size under 60 MB.
- **NFR-07** [M] Security aligned with OWASP MASVS: certificate pinning, no secrets in the app.
- **NFR-08** [M] Privacy-safe analytics with an opt-out.
- **NFR-09** [M] Offline-first UI that degrades gracefully on poor networks.
- **OPS-01** [M] Closed beta (TestFlight and Play internal testing) with listener and artist cohorts.
- **OPS-02** [M] Seed catalog: onboard the first 50 to 200 artists before public launch.
- **OPS-03** [M] Support: in-app help, email, FAQ and a status page.
- **OPS-04** [M] Staged rollouts (5%, 25%, 100%) with remote kill-switches for risky features such as YouTube and mixing modes.
- **OPS-05** [M] Store listings: screenshots, description, Apple privacy labels, Google Data Safety form.

Features planned for later phases are listed in the checklist below, each with its own status.

### Known risks

- Nobody reviews lyrics. An artist could add lyrics they do not own, and reports from listeners reach the artist, not a moderator.
- Anyone can send a copyright notice, and the song goes offline at once. Decide how rights holders are verified before relying on this.
- Every uploaded song waits for a reviewer by default, so moderators are needed before artists start uploading.
- Playlists, the queue and the listening history are kept on the device only. They are not saved to the server, so they are lost with the phone.
- A country with listening on fewer than five songs shows the whole-of-Vyro popular list instead of its own.
- On newer Android versions the system may refuse to delete music files that are outside the app's own folder.
- Crashes, speed, install size and availability are not measured anywhere yet, so none of the performance targets is confirmed.
- Accessibility, translations and the onboarding tour are launch requirements and are not started.
- The artist age limit of 18 is a cautious default that needs legal confirmation in each market.

## Suggested next steps

1. Run ./setup.sh on your machine and report what flutter analyze and flutter test say. Until then, every Built item is unconfirmed (there is a lot of it now).
2. Try the player on a real phone: audio focus for calls (PLY-05) and the lock-screen controls can only be confirmed there.
3. Before opening to the public: connect an email and SMS provider, set ADMIN_EMAILS, choose a copyright lookup service you may use commercially, have a lawyer review the notice process, and decide how lyrics will be reviewed.
4. Offline downloads, with encrypted storage and a download queue.
5. A screen in the Admin console for staff to build the editorial lists (today they use the server directly).
6. Next module: offline downloads (OFF), or the remaining launch-level gaps in other modules (for example the profile photo and language picker in AUTH-06, or YouTube search in SRC).

## Module overview

- **AUTH**: Listener accounts and onboarding. Launch items partly built. Launch-level items still open: AUTH-01, AUTH-03, AUTH-10.
- **ART**: Artist registration and verification. Launch items partly built. Launch-level items still open: ART-03, ART-06, ART-07, ART-08, ART-09.
- **STU**: Artist Studio. Launch items partly built. Launch-level items still open: STU-02, STU-03, STU-04, STU-05, STU-06, STU-08, STU-09.
- **LIB**: Local library. Launch items partly built. Launch-level items still open: LIB-01, LIB-03, LIB-06.
- **SRC**: Streaming sources and YouTube. Launch items partly built. Launch-level items still open: SRC-01, SRC-02, SRC-04, SRC-05, SRC-06, SRC-07, SRC-08, SRC-09.
- **PLY**: Playback core. Launch items partly built. Launch-level items still open: PLY-05, PLY-08.
- **MIX**: Mixing and transitions. Launch items built.
- **LYR**: Lyrics. Later-phase items partly built.
- **OFF**: Offline and downloads. Later phase, not started.
- **DSC**: Search, browse and charts. Launch items partly built. Launch-level items still open: DSC-01, DSC-03, DSC-05, DSC-07.
- **REC**: Recommendations and personalization. Launch items built.
- **PLS**: Playlists. Launch items partly built. Launch-level items still open: PLS-02, PLS-04.
- **SOC**: Social and sharing. Launch items partly built. Launch-level items still open: SOC-01, SOC-02.
- **UIX**: Design, themes, accessibility and localization. Launch items partly built. Launch-level items still open: UIX-02, UIX-03, UIX-04, UIX-05, UIX-06.
- **STA**: Artist analytics. Launch items partly built. Launch-level items still open: STA-01, STA-02.
- **PAY**: Payments, subscriptions and payouts. Later-phase items partly built.
- **BKE**: Backend and content pipeline. Launch items partly built. Launch-level items still open: BKE-01, BKE-02, BKE-03, BKE-04, BKE-06, BKE-07, BKE-09, BKE-10, BKE-11, BKE-12, BKE-13.
- **QUA**: Audio quality. Launch items partly built. Launch-level items still open: QUA-01, QUA-02.
- **DEV**: Devices and platform integrations. Launch items partly built. Launch-level items still open: DEV-01, DEV-03.
- **SAF**: Trust, safety and legal. Launch items partly built. Launch-level items still open: SAF-01, SAF-03, SAF-04, SAF-06, SAF-07, SAF-08, SAF-09, SAF-10.
- **PRF**: Listener profile and statistics. Launch items partly built. Launch-level items still open: PRF-01, PRF-08.
- **ADM**: Admin and curation. Launch items partly built. Launch-level items still open: ADM-01, ADM-03.
- **NFR**: Non-functional requirements. Launch items partly built. Launch-level items still open: NFR-01, NFR-02, NFR-03, NFR-04, NFR-05, NFR-06, NFR-07, NFR-08, NFR-09, NFR-10.
- **OPS**: Release and operations. Not started. Launch-level items still open: OPS-01, OPS-02, OPS-03, OPS-04, OPS-05.

## How to read the checklist

- ✅ **Done**: finished and checked by automated tests that have been run.
- 🟦 **Built**: written, and checked on the server where possible, but not yet tried on a phone or a computer, or not yet connected end to end.
- 🟨 **Partial**: only part of the requirement exists. The line under it says what is missing.
- ⬜ **Not started**: nothing built yet.

Tags in square brackets show when a requirement is planned: [M] MVP launch, [2] Phase 2, [3] Phase 3, [4] Phase 4.

## AUTH: Listener accounts and onboarding

*Inspired by Spotify, Apple Music*

- 🟨 **AUTH-01** [M] Sign up and log in with phone number and one-time code.
  - **Partial.** Phone sign-in works and the screens are built. Codes are not actually sent yet: an SMS service still needs to be connected.
- 🟦 **AUTH-02** [M] Sign up with email and password, with email verification.
  - **Built.** Sign-up, log-in and email confirmation work and the screens are built. Confirmation emails are not actually sent yet: an email service still needs to be connected.
- 🟨 **AUTH-03** [M] Social sign-in with Google, plus Sign in with Apple on iOS.
  - **Partial.** Google and Apple sign-in are checked by the server. The buttons say "not set up" until your Google and Apple developer accounts are connected.
- 🟦 **AUTH-04** [M] Guest mode: browse and play without an account; prompt to sign up before saving or downloading.
  - **Built.** Continue as guest. Profile, artist studio and account actions ask a guest to sign in.
- 🟦 **AUTH-05** [M] First-launch taste picker (genres, moods, at least three artists), skippable.
  - **Built.** Genres, moods and artists, skippable. "At least three artists" is not enforced because the catalog is still empty.
- 🟦 **AUTH-06** [M] Profile with name, photo, username, country and language.
  - **Built.** Name, photo, username, country and language. A listener's photo is private to them; an artist's photo is part of their public page. The language picker saves the choice, but Vyro is not translated yet.
- 🟦 **AUTH-07** [M] Password reset and account recovery.
  - **Built.** Reset with an emailed code; signs out every device.
- 🟦 **AUTH-08** [M] In-app account deletion with full data removal (required by both stores).
  - **Built.** Deleting an account needs the typed word DELETE and the password. Plays already counted for artists are kept, without the person's name. Every file goes too: songs, covers and the profile photo.
- 🟦 **AUTH-09** [M] Age gate and parental-consent flow where law requires it; explicit-content filter for minors.
  - **Built.** Date of birth at sign-up. Under 13 refused, 13 to 15 need a parent's emailed code, explicit content locked off under 18. Ages need legal review per market.
- 🟨 **AUTH-10** [M] Privacy controls: private listening session, hide activity, control data sharing.
  - **Partial.** Private session, "Share my country with artists" (off means plays count without a country), personalized recommendations, and a download of your data are real controls. "Hide my activity" and "Show my listening on my profile" are saved but apply to nothing yet, because friends and public profiles do not exist.
- 🟦 **AUTH-11** [M] Terms and privacy consent stored with version and timestamp.
  - **Built.** The sign-up checkbox records which version of the terms was accepted, and when. The legal text itself is a placeholder.
- 🟨 **AUTH-12** [2] Multi-device login with synced library, playlists and settings.
  - **Partial.** Several devices can be signed in at once and the saved login renews itself. Syncing library and settings is not built.
- ⬜ **AUTH-13** [2] Device manager: view and sign out other devices.
- ⬜ **AUTH-14** [3] Optional two-factor authentication.
- ✅ **AUTH-15** [M] One-time codes expire after 10 minutes, lock after 5 wrong tries, and at most 5 are sent per hour to one address or number.
  - **Done.** Codes expire after 10 minutes, lock after 5 wrong tries, and are limited to 5 per hour.
- ✅ **AUTH-16** [M] Sessions last 30 days and renew automatically; a password reset signs the person out of every device.
  - **Done.** Logins last 30 days and renew themselves. Resetting a password signs the person out of every device.
- 🟦 **AUTH-17** [M] The login survives app restarts in secure storage, and the app opens offline with the last saved profile.
  - **Built.** The login is kept in the device's secure storage. With no connection, the app opens with the last saved profile.
- 🟦 **AUTH-18** [M] Google and Apple sign-in accept only accounts whose email the provider has confirmed, and link to an existing account with the same confirmed email.
  - **Built.** Accounts are only linked when the email address is verified. Not yet tried with real Google or Apple accounts.

## ART: Artist registration and verification

*Inspired by Audiomack, Bandcamp, SoundCloud, Tidal*

- 🟦 **ART-01** [M] "Become an artist" upgrade inside the same account: one login, two modes.
  - **Built.** Upgrading a listener account to an artist account works, and the "Become an artist" screen is built.
- 🟦 **ART-02** [M] One-tap switch between Listener mode and Artist Studio.
  - **Built.** Top-bar switch between the listener tabs and the artist tabs.
- 🟨 **ART-03** [M] Artist profile: stage name, bio, photo, banner, genres, social links.
  - **Partial.** Name, type, bio, genres and links are stored. Photo and banner are missing.
- 🟦 **ART-04** [M] Artist type: solo, group, producer/DJ, label/manager.
  - **Built.** Solo, group, producer/DJ and label/manager on the upgrade screen, stored and checked by the server.
- 🟦 **ART-05** [M] Rights declaration confirming ownership or control of uploads, stored with timestamp.
  - **Built.** A tick box on the upgrade screen; the declaration is stored with the time it was made.
- 🟨 **ART-06** [M] Non-exclusive streaming agreement; the artist keeps ownership.
  - **Partial.** The agreement version is recorded and a draft agreement is shown. The real text needs legal review.
- ⬜ **ART-07** [M] Claim an auto-created artist profile through verification.
- 🟨 **ART-08** [M] Impersonation protection: name-similarity checks and a report flow.
  - **Partial.** Look-alike names (letter case, spaces, punctuation, accents) are blocked. A reporting flow is missing.
- 🟨 **ART-09** [M] Artists keep all listener features; their listening informs recommendations (opt-out available).
  - **Partial.** Artists use the same app and library. Using their listening for recommendations is not built.
- ⬜ **ART-10** [2] Identity verification (ID check) required before payouts and the verified badge.
- 🟦 **ART-11** [2] Verified-artist badge with a review process.
  - **Built.** Moderators can mark an artist verified, and verified artists can skip review under the "new artists" policy.
- ⬜ **ART-12** [2] Payout profile: mobile money, bank or other methods, plus tax details where required.
- ⬜ **ART-13** [2] Label/manager accounts that manage several artists.
- ⬜ **ART-14** [2] Team roles on a profile: admin, editor, analyst.
- ⬜ **ART-15** [2] Onboarding checklist: complete profile, first upload, first share.

## STU: Artist Studio

*Inspired by Audiomack, SoundCloud, Spotify for Artists*

- 🟦 **STU-01** [M] Upload WAV, FLAC, MP3 and AAC files.
  - **Built.** Uploads accept MP3, M4A, FLAC, WAV, OGG and AIFF files, and the Studio screen picks and uploads them.
- ⬜ **STU-02** [M] Resumable uploads that survive weak networks and app restarts.
- 🟨 **STU-03** [M] Metadata: title, featured artists, genre, mood, language, explicit flag, release date, credits, optional ISRC.
  - **Partial.** Title, genre, explicit, allow-blending and length are stored. Featured artists, mood, language, release date, credits and ISRC are missing.
- 🟨 **STU-04** [M] Cover art upload with size and ratio checks.
  - **Partial.** JPEG, PNG and WebP covers up to 5 MB are checked and stored. Size and ratio checks are missing.
- ⬜ **STU-05** [M] Release types: single, EP, album, mixtape, DJ mix.
- 🟨 **STU-06** [M] Automatic quality checks (clipping, silence, bitrate, upsampled fakes) with clear feedback.
  - **Partial.** Length, bitrate and sample-rate checks. Clipping, silence and fake-upsample checks are missing.
- 🟦 **STU-07** [M] Copyright fingerprint scan before publishing.
  - **Built.** Songs that sound like ones already on Vyro are put on hold, including re-encoded or trimmed copies. Checking against music released elsewhere is connected, but needs a licensed lookup service to go live.
- 🟨 **STU-08** [M] Draft, schedule, publish, unpublish and delete releases.
  - **Partial.** Draft, submit for release, withdraw and delete work. Scheduling is missing.
- 🟨 **STU-09** [M] Edit metadata after publishing, with change history.
  - **Partial.** The server can change title, genre, explicit and blending after publishing. There is no screen for it and no change history.
- 🟨 **STU-10** [2] Synced lyrics editor with .lrc import.
  - **Partial.** Artists can write, paste or import.lrc lyrics. There is no tap-to-time editor yet.
- ⬜ **STU-11** [2] Show detected BPM, key and loudness; artist can override mix-in and mix-out points.
- ⬜ **STU-12** [2] Collaborator splits: percentage per contributor, accepted by each.
- 🟨 **STU-13** [2] Per-track permissions: allow or deny downloads and sharing.
  - **Partial.** Blending can be switched off per song. Download and sharing permissions are stored but have no screen.
- ⬜ **STU-14** [2] Pre-save and release countdown.
- ⬜ **STU-15** [3] Smart link page for each release, shareable outside the app.
- ⬜ **STU-16** [3] Short looping visual per track.
- ⬜ **STU-17** [3] Music video upload or link.
- ⬜ **STU-18** [3] Announcements to followers.
- ✅ **STU-19** [M] Removing a song deletes its files, while past plays keep counting in the artist's statistics.
  - **Done.** Deleting a song removes its files and keeps its plays in the artist's statistics.
- ✅ **STU-21** [M] Uploading new audio for an existing song takes it offline until it is reviewed again.
  - **Done.** New audio takes a live song offline until it is reviewed again.
- 🟦 **STU-20** [M] Uploads have a size limit, checked before sending and again by the server, and a failed upload can be retried without creating a second song.
  - **Built.** The 300 MB limit is checked before sending and by the server, and a failed upload is retried on the same song.

## LIB: Local library

*Inspired by Lark Player, Poweramp, Apple Music*

- 🟨 **LIB-01** [M] Scan internal storage and SD card, with background incremental rescans.
  - **Partial.** Scans the Music and Download folders (Android), the Music folder (desktop) and any folder you add; only changed files are re-read. Automatic background rescans are missing.
- 🟦 **LIB-02** [M] Formats: MP3, AAC/M4A, FLAC, ALAC, WAV, OGG, Opus, AIFF.
  - **Built.** mp3, m4a, aac, flac, wav, ogg, opus and aiff files are picked up.
- 🟨 **LIB-03** [M] Read tags (ID3, Vorbis, MP4) and embedded artwork.
  - **Partial.** Tags are read. Cover art is not.
- 🟦 **LIB-04** [M] Browse by songs, albums, artists, genres and folders.
  - **Built.** Browse by songs, albums, artists, genres and folders. Genres and folders open to their songs, which play from there.
- 🟦 **LIB-05** [M] Include/exclude folders; ignore short clips such as voice notes.
  - **Built.** Leave a folder out (its songs go at once and stay out when the device is scanned again) and include it again; choose how short a song can be and still be kept (keep everything, 10 seconds, 30 seconds, 1 or 2 minutes). Both are in Library settings.
- 🟨 **LIB-06** [M] One unified library for local and online tracks, with source badges.
  - **Partial.** The Liked tab brings songs from the device and from Vyro together, each with a "Local" or "Vyro" badge, and playlists mix both. The Songs, Albums, Artists, Genres and Folders views still show only songs on the device.
- 🟦 **LIB-07** [M] Like any track; Liked Songs list.
  - **Built.** A heart on every song: songs on the device, Vyro songs, and the Now Playing screen. Vyro likes are saved on the server for signed-in people, so they follow them to another device, and wait on the device until the connection or the sign-in is there.
- 🟦 **LIB-08** [M] Delete local files from inside the app, with confirmation.
  - **Built.** "Delete from device" in a song's menu, after a confirmation. The song also leaves the queue and every playlist, and if it was playing, playback moves on first. If the file cannot be deleted, the song stays and the person is told. On newer Android versions the system may refuse to delete files outside the app's own folder; that case needs platform code.
- ⬜ **LIB-09** [2] Built-in tag editor (title, artist, album, artwork).
- ⬜ **LIB-10** [2] Fix missing metadata and artwork by matching against the Vyro catalog.
- ⬜ **LIB-11** [2] Recently added, recently played, most played.
- ⬜ **LIB-12** [2] Duplicate detection across local files and downloads.
- ⬜ **LIB-13** [2] Import playlists from other services (file import or connected services where allowed).
- ⬜ **LIB-14** [3] Cloud sync of library metadata and playlists (not the audio files).
- ⬜ **LIB-15** [3] Optional private cloud locker: stream your own uploaded files on other devices.
- 🟦 **LIB-16** [M] Add songs by picking them; on phones the picked files are copied into the app so they stay available.
  - **Built.** Pick songs with the system picker; on phones they are copied into the app.
- 🟦 **LIB-17** [M] Scanning runs in the background with live progress and never freezes the screen.
  - **Built.** Scanning runs in the background with a live count.

## SRC: Streaming sources and YouTube

*Inspired by Lark Player, Audiomack*

- 🟨 **SRC-01** [M] Stream Vyro artist uploads with adaptive quality.
  - **Partial.** Songs stream from short-lived secure links and can be played from any point. Adaptive quality is missing.
- 🟨 **SRC-02** [M] Source badge on every track (Local, Vyro, Open, YouTube) plus a "Mixable" indicator.
  - **Partial.** "Vyro" and "On device" badges in search and on Vyro songs. No "Mixable" indicator yet.
- 🟦 **SRC-03** [M] Unified search with results grouped by source.
  - **Built.** One search across Vyro and the music on the device, grouped by source. YouTube is not part of it yet.
- ⬜ **SRC-04** [M] YouTube search integrated into Vyro search, in its own section.
- ⬜ **SRC-05** [M] YouTube plays only through the official player, in the foreground, with video visible and unmodified.
- 🟨 **SRC-06** [M] YouTube items never enter the mix engine; transitions to or from them are a clean cut.
  - **Partial.** The mix engine never blends YouTube or license-restricted tracks. YouTube playback itself is not built.
- ⬜ **SRC-07** [M] No download, offline copy, audio extraction or background play of YouTube items.
- ⬜ **SRC-08** [M] YouTube items can be saved to playlists as links only, clearly marked.
- ⬜ **SRC-09** [M] YouTube policy compliance review before every release, with a remote switch to disable YouTube instantly.
- ⬜ **SRC-10** [2] Clean hand-off between the YouTube player and the Vyro audio engine in mixed queues.
- ⬜ **SRC-11** [2] Open-licensed catalog integration, with the license checked per source.
- ⬜ **SRC-12** [4] Licensed major and independent label catalog through deals or distributors, with per-license rules for mixing and offline.

## PLY: Playback core

*Inspired by Apple Music, Spotify, Poweramp*

- 🟦 **PLY-01** [M] Play, pause, seek, next, previous, shuffle, repeat (off, one, all).
  - **Built.** Play, pause, seek, next, previous, repeat (off, one, all) and shuffle. Shuffle plays the current song first, and the original order comes back when it is switched off.
- 🟦 **PLY-02** [M] Background playback with lock-screen and notification controls (own content).
  - **Built.** Notification, lock screen and headset buttons on Android, iOS and macOS, including shuffle and repeat.
- 🟦 **PLY-03** [M] Queue: play next, add, reorder, remove, clear, view history.
  - **Built.** A queue screen with play next, add, reorder, remove, clear and a history list. Song rows have a menu for "Play next" and "Add to queue".
- 🟦 **PLY-04** [M] Mini-player and full-screen Now Playing with swipe gestures.
  - **Built.** Mini player and full Now Playing screen. Swipe sideways on the mini player or the artwork to skip, and swipe up on the mini player to open Now Playing. Swipe down to close is not built.
- 🟨 **PLY-05** [M] Correct audio-focus handling for calls, navigation and other apps.
  - **Partial.** The audio session is set up for music so calls and other apps are handled by the system. Not tested on a phone.
- 🟦 **PLY-06** [M] Headphone and Bluetooth media buttons; pause on unplug.
  - **Built.** Headset and Bluetooth buttons go through the system media controls.
- 🟦 **PLY-07** [M] Resume exactly where the user left off, even after the app is killed.
  - **Built.** The queue, shuffle and repeat settings, and the exact place in the song are saved and brought back when the app starts, paused and ready. Nothing loads until play is pressed, so starting needs no connection.
- 🟨 **PLY-08** [M] Network resilience: buffering indicator, auto-retry, drop to a lower bitrate instead of stalling.
  - **Partial.** A buffering spinner and automatic retries (after 1, 2 and 4 seconds, from where the song stopped) are built. Dropping to a lower quality needs several versions of each song, which do not exist yet.
- ⬜ **PLY-09** [2] Gapless playback.
- ⬜ **PLY-10** [2] Sleep timer (minutes, end of track, end of album) with gentle fade-out.
- ⬜ **PLY-11** [2] Playback speed with pitch preservation.
- ⬜ **PLY-12** [2] 10-band equalizer with presets, bass boost and per-device profiles.
- 🟨 **PLY-13** [2] Loudness normalization so tracks play at similar volume (toggle).
  - **Partial.** Loudness is measured and sent to the app, but not applied to playback yet.
- ⬜ **PLY-14** [2] Streaming quality settings: Auto, Data saver, Normal, High, Lossless; separate for Wi-Fi and cellular.
- ⬜ **PLY-15** [2] Preload the next track so skipping is instant.
- ⬜ **PLY-16** [2] Smart shuffle that avoids repeats and mixes in recommendations (toggle).
- ⬜ **PLY-17** [3] Cross-device handoff and remote control.
- ⬜ **PLY-18** [3] Car mode with a simplified, large-button UI.
- ⬜ **PLY-19** [3] Spatial audio mode for headphones, where licensing and technology allow.
- 🟦 **PLY-20** [M] Background playback with notification, lock-screen, headset and Bluetooth controls on Android, iOS and macOS.
  - **Built.** Same work as PLY-02: background playback with system controls on Android, iOS and macOS.

## MIX: Mixing and transitions

*Inspired by Apple Music Automix, DJ software*

- 🟦 **MIX-01** [M] Crossfade between consecutive tracks, 0 to 12 seconds, adjustable, equal-power curve.
  - **Built.** Equal-power blend from 1 to 12 seconds (Normal mode is the off setting).
- ⬜ **MIX-02** [2] Crossfade settings per context: playlists on, albums off by default, radio on.
- ⬜ **MIX-03** [2] Fade-in on start and fade-out on pause to avoid clicks.
- 🟨 **MIX-04** [2] Server-side analysis of every Vyro track: BPM, beat grid, key, loudness, energy, intro and outro points, silence.
  - **Partial.** Only loudness is measured so far. Beats, key and mix points are missing.
- ⬜ **MIX-05** [2] On-device analysis for local files, cached, run only while idle or charging.
- ⬜ **MIX-06** [2] Fallback to a simple crossfade when analysis is missing or low confidence.
- 🟨 **MIX-07** [2] Mixing works offline using downloaded and local tracks with cached analysis.
  - **Partial.** Songs on this device are blended. Downloaded online songs do not exist yet.
- 🟦 **MIX-08** [2] Respect license flags: non-mixable tracks get a plain gap or crossfade only.
  - **Built.** Songs marked not mixable, and YouTube songs, change with a clean cut.
- ⬜ **MIX-09** [3] Automix: transitions placed automatically at the best mix-out and mix-in points.
- ⬜ **MIX-10** [3] Beat-matched transitions using tempo-sync within a safe limit (about ±6%).
- ⬜ **MIX-11** [3] Harmonic mixing: prefer key-compatible neighbors.
- ⬜ **MIX-12** [3] Transition styles: crossfade, cut, echo-out, filter sweep, bass-swap, with intensity control.
- ⬜ **MIX-13** [3] "Mix this playlist": reorder by BPM, key and energy for smooth flow (optional, undoable).
- ⬜ **MIX-14** [3] Energy-arc modes: warm-up, steady, peak, cool-down; match BPM to running cadence.
- ⬜ **MIX-15** [3] Mix editor: adjust transition length and style per track pair and save the mix.
- ⬜ **MIX-16** [3] Share a mix as a playlist with its transition settings (not rendered audio).
- ⬜ **MIX-17** [3] Artist-defined default mix points per track.
- ⬜ **MIX-18** [3] Artist opt-out of tempo or pitch alteration per track.
- ⬜ **MIX-19** [3] Mixing runs reliably in the background and with the screen off.
- ⬜ **MIX-20** [4] DJ mode for creators: two-deck view with waveforms.
- 🟦 **MIX-21** [M] Two playback modes, switchable at any time: Normal (songs change one after another, no overlap) and Mixing (blends apply when a song ends, and on next and previous).
  - **Built.** Normal and Mixing modes on the player screen.
- 🟦 **MIX-22** [M] In Mixing mode, separate blend lengths (1 to 12 seconds) for "end of song" and "next / back".
  - **Built.** Separate blend lengths for end of song and for next/back.
- 🟦 **MIX-23** [M] Previous restarts the current song after the first 3 seconds, in both modes; otherwise it goes back to the earlier song (blended in Mixing mode).
  - **Built.** Back restarts the song after 3 seconds, otherwise goes to the earlier song.

## LYR: Lyrics

*Inspired by Apple Music, Spotify, Musixmatch*

- 🟦 **LYR-01** [2] Time-synced lyrics highlighted line by line with auto-scroll.
  - **Built.** The line being sung is highlighted and scrolled into view.
- 🟨 **LYR-02** [2] Full-screen lyrics view; tap a line to seek.
  - **Partial.** Lyrics open inside the Now Playing screen, and tapping a line jumps to it. There is no separate full-screen view.
- 🟦 **LYR-03** [2] Plain (unsynced) lyrics fallback.
  - **Built.** Lyrics without times are shown as plain text, with verse breaks kept.
- 🟦 **LYR-04** [2] Read embedded lyrics and sidecar .lrc files for local tracks.
  - **Built.** Songs on the device use a.lrc or.txt file with the same name, or lyrics stored inside the file.
- 🟦 **LYR-05** [2] Artist-supplied lyrics from Studio for Vyro tracks.
  - **Built.** Artists add, edit and remove lyrics in the Studio.
- 🟨 **LYR-06** [2] Lyrics stay in sync through crossfades and tempo changes.
  - **Partial.** Lyrics follow the song that is showing, including through a blend. Tempo changes do not exist yet.
- 🟦 **LYR-07** [2] Report wrong lyrics; artists can correct them.
  - **Built.** Listeners report wrong words, timing, offensive or copied lyrics; the artist is told once per person.
- ⬜ **LYR-08** [2] Share a lyric card as an image (licensed or artist-supplied lyrics only).
- ⬜ **LYR-09** [3] Lyrics translation into the user's language.
- ⬜ **LYR-10** [3] Romanization for non-Latin scripts.
- ⬜ **LYR-11** [3] Word-by-word highlighting.
- ⬜ **LYR-12** [3] Karaoke mode with vocal reduction where stems are available and the artist allows it.
- ⬜ **LYR-13** [3] Floating lyrics overlay on Android.
- ⬜ **LYR-14** [4] Licensed lyrics provider for the wider catalog.
- ✅ **LYR-15** [2] Lyrics of explicit songs are hidden from people who have explicit content turned off.
  - **Done.** Lyrics of explicit songs follow the explicit setting, for guests and minors too.

## OFF: Offline and downloads

*Inspired by Audiomack, Apple Music, Spotify*

- ⬜ **OFF-01** [2] Download tracks, albums, playlists and mixtapes where artist and license allow.
- ⬜ **OFF-02** [2] Downloads stored encrypted inside the app, not extractable as plain files.
- ⬜ **OFF-03** [2] Download queue with pause, resume and retry; Wi-Fi-only option.
- ⬜ **OFF-04** [2] Choose storage location (internal or SD card) and download quality.
- ⬜ **OFF-05** [2] Storage manager: size per item, delete all, auto-delete unplayed downloads after N days.
- ⬜ **OFF-06** [2] Offline mode that shows and plays only downloaded and local content.
- ⬜ **OFF-07** [2] Optional auto-download: new releases from followed artists, liked songs, chosen playlists.
- ⬜ **OFF-08** [2] Smart cache for frequently played tracks.
- ⬜ **OFF-09** [2] Lyrics and analysis data downloaded with each track so mixing and lyrics work offline.
- ⬜ **OFF-10** [2] Offline listens recorded locally and synced when back online.
- ⬜ **OFF-11** [2] Free downloads at launch, with entitlement hooks ready to limit later via feature flag.
- ⬜ **OFF-12** [3] Offline validity window (for example 30 days) with silent re-verification when online.

## DSC: Search, browse and charts

*Inspired by Spotify, Apple Music, Audiomack*

- 🟨 **DSC-01** [M] Unified search across tracks, artists, albums, playlists, users and local files.
  - **Partial.** Songs and artists on Vyro, found even with typos and missing accents, plus songs on the device. Albums, playlists and users cannot be searched yet, because Vyro has no public albums, playlists or user pages.
- 🟦 **DSC-02** [M] Instant suggestions, typo tolerance, recent searches.
  - **Built.** Suggestions for the first one or two letters, search that forgives typos and accents ("nova wve" finds Nova Wave), and recent searches that can be reused, removed or cleared.
- 🟨 **DSC-03** [M] Browse by genre, mood, activity, decade and language.
  - **Partial.** Browse by genre, from the Search screen. Mood, activity, decade and language are missing, because songs do not carry those details yet.
- 🟦 **DSC-04** [M] Home feed: continue listening, new releases, picks for you, trending.
  - **Built.** Home shows Continue listening (what you played lately), Picked for you, New on Vyro and Top this week, with a Charts button.
- 🟨 **DSC-05** [M] Charts: trending, top songs, albums and artists; global and per country; rising artists.
  - **Partial.** Top songs, top artists and rising artists, worldwide or for your own country. An albums chart is missing, because Vyro has no albums yet.
- 🟦 **DSC-06** [M] Artist page: top tracks, discography, about, similar artists, follow.
  - **Built.** An artist page with popular songs, all their songs, about, links, similar artists and a follow button. Photo and banner are missing. Reached from search, charts, similar artists and the artist name under any song.
- ⬜ **DSC-07** [M] Album/release page with credits, duration and total tracks.
- ✅ **DSC-08** [M] Explicit-content preference applied across search and browse.
  - **Done.** Explicit songs are hidden from guests and from anyone with explicit content turned off, in search, new releases, charts and streaming.
- ⬜ **DSC-09** [2] Editor-curated mood and activity playlists (Chill, Focus, Workout, Party, Night Drive, Worship, more).
- ⬜ **DSC-10** [2] Genre hubs for regional scenes (Afrobeats, Amapiano, Hip-Hop, Gospel and more).
- ⬜ **DSC-11** [2] Search by lyric snippet.
- ⬜ **DSC-12** [2] New releases page with filters.
- ⬜ **DSC-13** [3] Song recognition (identify a song playing nearby).
- ⬜ **DSC-14** [3] Radio: infinite stations from an artist, track or genre.
- ⬜ **DSC-15** [3] Editorial features: artist spotlights, artist of the week, interviews.
- ⬜ **DSC-16** [3] Music videos and live performances section.
- ⬜ **DSC-17** [3] Events and ticket links on artist pages.
- ⬜ **DSC-18** [4] Podcasts and spoken-word shows.

## REC: Recommendations and personalization

*Inspired by Spotify, YouTube's two-stage approach, Apple Music*

- 🟦 **REC-01** [M] Cold-start recommendations from the taste picker, editorial lists and regional popularity.
  - **Built.** Home shows "Picked for you" (from the genres and artists chosen in the taste picker), "Popular in your country" (or on all of Vyro when a country has too little listening), and lists chosen by Vyro's staff. The moods from the picker are not used yet, because songs have no mood. Staff create the lists through the server for now; there is no screen for it.
- 🟦 **REC-02** [2] Consent-based event logging: plays, completions, skips, replays, saves, adds, shares, searches.
  - **Built.** Plays are recorded on the device, and plays of Vyro songs are sent to the server when signed in. Private sessions and personalization settings are respected.
- ⬜ **REC-03** [2] Daily mixes grouped by taste cluster.
- ⬜ **REC-04** [2] Weekly discovery playlist of new-to-you tracks.
- ⬜ **REC-05** [2] New-release radar from followed artists.
- ⬜ **REC-06** [2] "Listeners also play" and similar artists and tracks.
- ⬜ **REC-07** [2] Fairness quota: reserve a share of recommendation slots for new and independent artists.
- ⬜ **REC-08** [2] Local-file taste signals included, with consent.
- 🟦 **REC-09** [2] User controls: pause personalization, reset recommendations, clear history, "not interested".
  - **Built.** Pause personalization (this turns off "Picked for you"), reset recommendations, clear listening history, and "Not interested" for a song or a whole artist.
- ⬜ **REC-10** [3] Two-stage engine: candidate generation, then ranking, with vector search.
- ⬜ **REC-11** [3] Context awareness: time of day, activity, device, session mood.
- ⬜ **REC-12** [3] Diversity controls and thumbs up/down to avoid filter bubbles.
- ⬜ **REC-13** [3] "Because you listened to…" explanations.
- ⬜ **REC-14** [3] Yearly recap for listeners and for artists.
- ⬜ **REC-15** [3] Blend: merge two friends' tastes into a shared, updating playlist.
- ⬜ **REC-16** [3] Playlist generator from a text prompt.
- ⬜ **REC-17** [4] AI-led listening sessions with a voice host.
- 🟦 **REC-18** [M] Listening time is measured honestly: seeks add nothing, pausing does not end a play, and a play under a second is ignored.
  - **Built.** Real listening time per song, including blends.
- 🟦 **REC-19** [M] Plays made offline or as a guest wait on the device and are sent later, without ever being counted twice.
  - **Built.** Plays made offline or as a guest wait on the device and are sent later. No play is counted twice, and bad data cannot block the rest.

## PLS: Playlists

*Inspired by Spotify, Apple Music*

- 🟦 **PLS-01** [M] Create, rename, edit and delete playlists with cover and description.
  - **Built.** Create, rename, describe and delete playlists, with a cover picture. Playlists are kept on this device.
- 🟨 **PLS-02** [M] Add any source (local, Vyro, YouTube link) to a playlist, with badges.
  - **Partial.** Songs from your own files and from Vyro can be added from any song row or from Now Playing, each shown with a "Vyro" or "Local" badge. YouTube links are not built yet.
- 🟦 **PLS-03** [M] Reorder, bulk select, sort and remove duplicates.
  - **Built.** Drag to reorder, select several songs (remove, add to the queue, add to another playlist), sort by title, artist, date added or length, and remove duplicates.
- ⬜ **PLS-04** [M] Save albums and mixtapes to the library.
- ⬜ **PLS-05** [2] Public, private and link-only playlists.
- ⬜ **PLS-06** [2] Collaborative playlists with invite links and contributor roles.
- ⬜ **PLS-07** [2] Folders and pinning.
- ⬜ **PLS-08** [2] Playlist sync across devices.
- ⬜ **PLS-09** [3] Smart playlists by rules (genre, BPM, year, play count, source).
- ⬜ **PLS-10** [3] Auto-generated cover mosaics.
- ⬜ **PLS-11** [3] Follow other users' playlists, with follower counts.
- ⬜ **PLS-12** [3] "Mix mode" toggle on a playlist.

## SOC: Social and sharing

*Inspired by Spotify, SoundCloud, Audiomack*

- ⬜ **SOC-01** [M] Share tracks, albums, artists and playlists via link; deep links open the app or the store page.
- ⬜ **SOC-02** [M] Block, mute and report users and content (required for user-generated content).
- ⬜ **SOC-03** [2] Share cards for stories and messaging apps.
- 🟨 **SOC-04** [2] Follow users and artists.
  - **Partial.** Follow and unfollow from the artist page. A list of the artists you follow is missing.
- ⬜ **SOC-05** [3] Opt-in friend activity feed with a private-session override.
- ⬜ **SOC-06** [3] Group listening: shared queue and synced playback.
- ⬜ **SOC-07** [3] Scannable share codes.
- ⬜ **SOC-08** [3] Timed comments on the waveform, with moderation tools for artists.
- ⬜ **SOC-09** [3] Reposts to followers.
- ⬜ **SOC-10** [3] 30-second preview clips for sharing.
- ⬜ **SOC-11** [3] Fan support: tips and supporter badges (needs payments live).

## UIX: Design, themes, accessibility and localization

*Inspired by Lark Player, Apple Music*

- 🟦 **UIX-01** [M] Themes: Midnight (dark), Daylight (light), AMOLED Black, follow system.
  - **Built.** Midnight, Daylight, AMOLED black and follow-system. The choice is not saved between launches yet.
- ⬜ **UIX-02** [M] Smooth 60 fps animations with no layout jumps.
- ⬜ **UIX-03** [M] Accessibility: VoiceOver and TalkBack, scalable text, high contrast, color-blind-safe palettes, large touch targets.
- ⬜ **UIX-04** [M] English at launch, with a localization system and right-to-left support ready for more languages.
- ⬜ **UIX-05** [M] Smooth performance on low-end phones (2 GB RAM) and small app size.
- ⬜ **UIX-06** [M] Short onboarding tour explaining mixing, lyrics and offline.
- 🟦 **UIX-07** [2] Accent themes (Neon, Sunset, Forest, Ocean).
  - **Built.** Aurora, Sunset, Forest and Ocean accents.
- ⬜ **UIX-08** [2] Album Color theme: palette drawn from cover art.
- ⬜ **UIX-09** [2] Now Playing styles: classic, large cover, lyrics-first, waveform, visualizer.
- ⬜ **UIX-10** [2] Home-screen and lock-screen widgets.
- ⬜ **UIX-11** [2] Tablet and foldable layouts, landscape mode.
- 🟨 **UIX-12** [2] Helpful empty states and skeleton loaders.
  - **Partial.** Empty and loading states exist for the Library and statistics, not everywhere.
- ⬜ **UIX-13** [3] Seasonal and artist-made themes.
- ⬜ **UIX-14** [3] Customizable bottom navigation and home sections.

## STA: Artist analytics

*Inspired by Spotify for Artists, Apple Music for Artists, Audiomack*

- 🟨 **STA-01** [M] Dashboard: plays, unique listeners, followers, saves, playlist adds, with date ranges.
  - **Partial.** Plays, listeners, followers and saves with date ranges, filled by real plays once the app sends them. Saves now include the likes made in the app. Playlist adds are missing.
- 🟨 **STA-02** [M] Per-track stats: completion rate, skip rate, replays, average listen time.
  - **Partial.** Finish rate and skip rate per song. Replays and average listen time are missing.
- 🟨 **STA-03** [2] Audience: top countries and cities, age bands, device types, aggregated only.
  - **Partial.** Countries only. Cities, age bands and devices are missing.
- 🟦 **STA-04** [2] Discovery sources: search, recommendations, playlists, charts, shares, direct.
  - **Built.** Search, recommendations, playlists, charts, shares, library and direct.
- ⬜ **STA-05** [2] Listening heatmap by hour and weekday.
- ⬜ **STA-06** [2] Playlist placements: which playlists feature the artist's tracks.
- 🟦 **STA-07** [2] Mixing stats: how often tracks appear in transitions and which tracks they mix with.
  - **Built.** Which songs yours are blended with.
- 🟦 **STA-08** [2] Real-time view for the first 48 hours after release.
  - **Built.** Last 48 hours hour by hour (shown at any time, not only after a release).
- ⬜ **STA-09** [2] CSV and PDF export.
- ✅ **STA-10** [2] Minimum thresholds so individual listeners can never be identified.
  - **Done.** Groups with fewer than 5 listeners are folded into "Other" to protect privacy.
- 🟨 **STA-11** [2] Fraud filtering and a published "valid stream" rule (about 30 seconds).
  - **Partial.** The 30-second rule for counting a stream is built. Fraud filtering is missing.
- ⬜ **STA-12** [3] Release comparison and milestone notifications.
- ⬜ **STA-13** [3] Opt-in top-fans insights.
- 🟨 **STA-14** [3] Public monthly listeners on artist pages.
  - **Partial.** Monthly listeners and follower numbers exist on the server. There is no artist page screen yet.
- ⬜ **STA-15** [3] Earnings view (when monetization is on), pending versus paid.
- 🟦 **STA-16** [M] Every number shown next to the period just before it, with an up or down percentage.
  - **Built.** Every headline number shows its change against the period before.
- 🟦 **STA-17** [M] Retention curve per song: the share of plays still going at each 10% of the song.
  - **Built.** Retention curve per song.
- 🟦 **STA-18** [M] Audience split into new, returning and super listeners (5 or more plays in the period).
  - **Built.** New, returning and super listeners.
- 🟦 **STA-19** [M] Period picker: 7 days, 28 days, 90 days, 12 months.
  - **Built.** 7 days, 28 days, 90 days and 12 months.
- 🟦 **STA-20** [M] Plays by hour for the last 48 hours ("right now" view).
  - **Built.** Plays by hour for the last 48 hours.

## PAY: Payments, subscriptions and payouts

- ⬜ **PAY-01** [2] Plan model and entitlements engine; everyone starts on "Free (Founding)".
- 🟨 **PAY-02** [2] Global and per-feature flags to switch paywalls on or off without an app update.
  - **Partial.** Paywall flags exist on the server and default to off. The app does not read them yet.
- ⬜ **PAY-03** [2] Apple in-app purchase (StoreKit 2) and Google Play Billing implemented and tested, hidden behind flags.
- ⬜ **PAY-04** [2] Server-side receipt validation and webhooks as the single source of truth.
- ⬜ **PAY-05** [2] Plan types: Individual, Student, Family, Annual; regional pricing.
- ⬜ **PAY-06** [2] Free trials, intro offers, promo codes and gift codes.
- ⬜ **PAY-07** [2] Restore purchases, grace periods, billing retry, cancellation and refund handling.
- ⬜ **PAY-08** [2] Local payment methods (mobile money, cards, carrier billing) through web checkout where store rules allow; legal check per market.
- ⬜ **PAY-09** [2] Founding Listener badge and grandfathering rules for early users.
- ⬜ **PAY-10** [2] Receipts, invoices and tax/VAT handling.
- ⬜ **PAY-11** [2] Payment and promo-code fraud detection.
- ⬜ **PAY-12** [2] Paywall screens built and tested in staging, disabled in production.
- ⬜ **PAY-13** [3] Artist earnings ledger with per-stream accrual and multi-currency support.
- ⬜ **PAY-14** [3] Subscriber analytics for admins: conversion, churn, recurring revenue.
- ⬜ **PAY-15** [3] Fan tips with a platform fee.
- ⬜ **PAY-16** [4] Decide the premium perks (candidates: lossless and hi-res, unlimited downloads, family plans, early access). Ad-free stays free.
- ⬜ **PAY-17** [4] Decide the payout model (pro-rata pool or user-centric pool) and publish it to artists.
- ⬜ **PAY-18** [4] Scheduled payouts via mobile money or bank, with a minimum threshold and payout history.

## BKE: Backend and content pipeline

- 🟨 **BKE-01** [M] Versioned API with rate limiting.
  - **Partial.** A versioned API. Rate limits exist for sign-in only.
- 🟨 **BKE-02** [M] PostgreSQL for users, catalog and playlists; separate analytics store for events.
  - **Partial.** A database holds users, artists, songs, follows, saves and plays. Playlists and a separate analytics store are missing.
- 🟨 **BKE-03** [M] Object storage for masters and encoded files, delivered through a CDN.
  - **Partial.** Files are stored on the server's disk behind a storage layer. Cloud storage and a content delivery network are missing.
- 🟨 **BKE-04** [M] Transcoding pipeline: master to AAC at multiple bitrates and Opus; adaptive HLS; optional lossless tier.
  - **Partial.** Lossless uploads get a smaller streaming copy (needs the ffmpeg tool installed on the server). Several bitrates and adaptive streaming are missing.
- ✅ **BKE-05** [M] Loudness measurement (EBU R128 / ReplayGain) at ingest.
  - **Done.** Loudness is measured when a song is uploaded and stored (needs the ffmpeg tool installed on the server).
- 🟨 **BKE-06** [M] Audio fingerprinting for duplicates and copyright matches.
  - **Partial.** Copies of songs already on Vyro are detected by audio fingerprint, even re-encoded ones. Matching against music released elsewhere needs a licensed lookup service.
- 🟨 **BKE-07** [M] Search engine with typo tolerance and multilingual support.
  - **Partial.** Search uses the database (prefix matches first). Typo tolerance and a search engine are missing.
- ✅ **BKE-08** [M] Signed, expiring stream URLs with hotlink protection.
  - **Done.** Stream links are signed and expire; altered or expired links are refused.
- ⬜ **BKE-09** [M] Push notification service (APNs and FCM) with user preferences.
- ⬜ **BKE-10** [M] Staging and production environments, infrastructure as code, CI/CD.
- ⬜ **BKE-11** [M] Monitoring, logging, alerting and error tracking.
- ⬜ **BKE-12** [M] Backups and a disaster-recovery plan with tested restores.
- 🟨 **BKE-13** [M] Feature-flag and remote-config service.
  - **Partial.** A table of feature switches and a way to read them. There is no admin screen to change them.
- ⬜ **BKE-14** [2] Audio analysis service for BPM, beats, key, energy and cue points.
- 🟨 **BKE-15** [2] Event ingestion pipeline (queue and stream) for listens and analytics.
  - **Partial.** Plays are stored straight into the database. There is no queue or stream pipeline yet.
- ⬜ **BKE-16** [2] Encrypted offline package service with per-device keys.
- ⬜ **BKE-17** [2] Background job system for ingest, analysis and email.
- ⬜ **BKE-18** [2] Cost dashboard: streaming, storage and delivery cost per active user.
- ⬜ **BKE-19** [3] Recommendation service with feature store and vector index.
- ⬜ **BKE-20** [3] Multi-region CDN and edge caching.

## QUA: Audio quality

*Inspired by Apple Music, Tidal*

- ⬜ **QUA-01** [M] Normal streaming at 128 kbps or higher (Opus/AAC); High at 256 kbps or higher. Free-tier ceiling to be decided.
- 🟨 **QUA-02** [M] Upload quality gates (minimum bitrate, fake-upsample detection).
  - **Partial.** Bitrate, sample-rate and length gates. Fake-upsample detection is missing.
- 🟨 **QUA-03** [2] Lossless playback for local files (FLAC, ALAC), bit-perfect where hardware allows.
  - **Partial.** FLAC and ALAC files are accepted and played by the platform players. Bit-perfect output is not handled.
- ⬜ **QUA-04** [2] Loudness target of about -14 LUFS with a user setting.
- ⬜ **QUA-05** [2] Headroom management and clip prevention inside the mix engine.
- ⬜ **QUA-06** [2] Listening and performance benchmarks on target devices before each release.
- ⬜ **QUA-07** [3] Hi-res support (up to 24-bit/192 kHz) for local and uploaded files.
- ⬜ **QUA-08** [3] USB DAC and Bluetooth codec support (LDAC, aptX, AAC).
- ⬜ **QUA-09** [3] Quality badges on tracks (Standard, Lossless, Hi-Res).
- ⬜ **QUA-10** [4] Spatial audio ingestion (licensing check required).

## DEV: Devices and platform integrations

- 🟨 **DEV-01** [M] iOS and Android apps with a shared UI codebase and native audio engine modules.
  - **Partial.** One shared codebase for every platform. A custom native audio engine is not built.
- 🟦 **DEV-02** [M] Lock-screen, notification and quick-settings media controls.
  - **Built.** Same work as PLY-02.
- 🟨 **DEV-03** [M] Correct background-audio setup: iOS background mode, Android foreground service, battery-optimization handling.
  - **Partial.** The setup script adds the Android service and permissions and the iOS background mode. Battery-optimization handling is missing.
- ⬜ **DEV-04** [2] Bluetooth, AirPlay and Google Cast output.
- ⬜ **DEV-05** [2] "Open with Vyro" for audio files from other apps.
- ⬜ **DEV-06** [2] Optional scrobbling to listening-history services.
- ⬜ **DEV-07** [3] CarPlay and Android Auto.
- ⬜ **DEV-08** [3] Smartwatch companion (Apple Watch, Wear OS).
- ⬜ **DEV-09** [3] Voice assistant support (Siri, Google Assistant).
- ⬜ **DEV-10** [3] Web player with the same account.
- ⬜ **DEV-11** [4] Smart TV app.
- 🟦 **DEV-12** [M] One Flutter codebase for Android, iOS, Windows and macOS (Linux later).
  - **Built.** One setup script builds Android, iOS, Windows and macOS from one codebase.
- ⬜ **DEV-13** [2] Desktop conventions: resizable window, keyboard shortcuts and media keys, menu-bar or system-tray controls, drag-and-drop of audio files.
- ⬜ **DEV-14** [2] Windows media keys and the Windows media overlay (the background-audio plugin does not cover Windows).
- ⬜ **DEV-15** [3] macOS App Store release: App Sandbox back on, with saved folder permissions for the music library.

## SAF: Trust, safety and legal

- ⬜ **SAF-01** [M] Terms of Service, Privacy Policy and artist agreement reviewed by legal counsel in each launch market.
- 🟦 **SAF-02** [M] Copyright takedown process with counter-notice and a repeat-infringer policy.
  - **Built.** A copyright notice takes a song offline at once; the artist can answer with a counter-notice; a reviewer upholds or restores it. The legal wording and time limits need a lawyer.
- 🟨 **SAF-03** [M] Moderation queue for uploads, profiles, images and comments.
  - **Partial.** A moderation queue for uploads. Profiles, images and comments are missing.
- ⬜ **SAF-04** [M] Explicit-content labeling and filtering.
- 🟦 **SAF-05** [M] Data-protection compliance: access, export and deletion rights.
  - **Built.** Deleting an account removes everything, files included; plays stay as anonymous counts. "Download my data" copies a full export (profile, picks, follows, likes, "not interested" choices and the plays linked to the person). The wording and retention periods need a lawyer.
- 🟨 **SAF-06** [M] Data minimization; encryption at rest and in transit.
  - **Partial.** Passwords are stored securely hashed. Encryption in transit comes with deployment.
- ⬜ **SAF-07** [M] Child-safety rules: age limits, no targeting of minors, reporting channel.
- ⬜ **SAF-08** [M] Music licensing and royalty-reporting obligations (publishing and performance rights) confirmed per market.
- ⬜ **SAF-09** [M] Trademark and name clearance for "Vyro Music" (pending).
- ⬜ **SAF-10** [M] App Store and Google Play policy checklist, including user-generated-content rules.
- ⬜ **SAF-11** [2] Anti-fraud: bot, stream-farming and fake-account detection.
- 🟨 **SAF-12** [2] Rate limits and abuse protection on uploads and APIs.
  - **Partial.** Rate limits on sign-in. Nothing for uploads yet.
- ⬜ **SAF-13** [2] Published explanations of how stream counts and recommendations work.
- 🟨 **SAF-14** [2] Dispute and appeal process for artists.
  - **Partial.** Artists can answer a copyright notice with a counter-notice. Appeals of a rejection or an ownership dispute are missing.
- ⬜ **SAF-15** [2] Penetration test before public launch and a vulnerability disclosure channel.
- ✅ **SAF-16** [M] Repeat infringers are suspended automatically after 3 upheld copyright notices.
  - **Done.** Three upheld copyright notices suspend the artist automatically.
- ✅ **SAF-17** [M] Suspended accounts are signed out everywhere and cannot sign in, and their songs are hidden.
  - **Done.** A suspended account is signed out everywhere, cannot sign in, and its songs are hidden.

## PRF: Listener profile and statistics

*Inspired by Apple Music Replay, Spotify Wrapped, stats.fm, Last.fm*

- 🟨 **PRF-01** [M] Profile header: photo, name and username.
  - **Partial.** Header shows the real name and username. No photo yet.
- 🟦 **PRF-02** [M] Period picker: 4 weeks, 6 months, this year, all time.
  - **Built.** 4 weeks, 6 months, this year, all time.
- 🟦 **PRF-03** [M] Minutes listened as the headline number, with hours.
  - **Built.** Minutes listened with hours.
- 🟦 **PRF-04** [M] Listening streak: consecutive days with listening, in the listener's own time zone.
  - **Built.** Listening streak in the listener's own time zone.
- 🟦 **PRF-05** [M] Top artists, top songs and top genres for the period.
  - **Built.** Top artists, songs and genres.
- 🟦 **PRF-06** [M] Listening clock (which hours of the day) and a listening personality (night owl, early bird, daytime, all-day).
  - **Built.** Listening clock and personality.
- 🟦 **PRF-07** [M] Songs blended and new artists discovered, the two numbers only Vyro can show.
  - **Built.** Songs blended and new artists found.
- 🟨 **PRF-08** [M] Switch to keep listening stats private, only visible to the listener.
  - **Partial.** Saved on the server and shown on the profile; there is no public profile yet to apply it to.
- ⬜ **PRF-09** [2] Public profile showing the stats the listener chose to share.
- ⬜ **PRF-10** [3] Year-in-music recap with a shareable card (see REC-14).
- 🟦 **PRF-12** [M] A "clear listening history" option that removes the history kept on the device.
  - **Built.** Clear listening history on the Account screen.
- 🟦 **PRF-11** [2] On-device statistics for local files and YouTube plays, merged with server statistics so the profile covers everything the listener plays.
  - **Built.** Profile combines Vyro listening from the server with music played from the device, streak included. YouTube plays are not part of it yet.

## ADM: Admin and curation

- 🟨 **ADM-01** [M] Admin console with roles and an audit log.
  - **Partial.** Roles (listener, moderator, admin) and a record of every decision exist, and the Admin console is built. The record has no screen yet.
- 🟦 **ADM-02** [M] Approve or reject uploads, with bulk actions and reasons sent to artists.
  - **Built.** Approve or reject with a reason the artist is told, one at a time or in bulk.
- 🟨 **ADM-03** [M] User and artist management: suspend, verify, merge duplicates.
  - **Partial.** Search artists, verify, suspend and restore. Merging duplicate accounts is missing.
- ⬜ **ADM-04** [2] Editorial tools: build playlists, schedule home sections, feature artists.
- ⬜ **ADM-05** [2] Chart management with fraud exclusions and logged manual overrides.
- ⬜ **ADM-06** [2] Feature-flag and remote-config interface.
- ⬜ **ADM-07** [2] Support tools: user lookup, entitlement and refund adjustments.
- ⬜ **ADM-08** [2] Reports dashboard with response-time targets.
- ⬜ **ADM-09** [2] A/B testing framework.
- ⬜ **ADM-10** [3] Business dashboards: daily and monthly actives, retention, listening hours, cost per user.
- ⬜ **ADM-11** [3] Segmented announcement and push campaigns.
- 🟦 **ADM-12** [M] Reviewers can listen to a song before deciding, including songs that are not public.
  - **Built.** Reviewers can listen to a song before deciding, through a private link.
- ✅ **ADM-13** [M] A review policy setting (every song, only new artists, or none), and audio that could not be checked never skips review.
  - **Done.** Review policy: every song, only new artists, or none. Audio that could not be checked never skips review.

## NFR: Non-functional requirements

- ⬜ **NFR-01** [M] Start-to-play under 1.5 seconds on 4G for Vyro tracks (75th percentile).
- ⬜ **NFR-02** [M] Cold start under 2 seconds on mid-range phones.
- ⬜ **NFR-03** [M] Crash-free sessions of at least 99.5%.
- ⬜ **NFR-04** [M] Streaming API availability of at least 99.9%.
- ⬜ **NFR-05** [M] Supported OS: Android 8+ and iOS 16+ (confirm against market device data).
- ⬜ **NFR-06** [M] Install size under 60 MB.
- ⬜ **NFR-07** [M] Security aligned with OWASP MASVS: certificate pinning, no secrets in the app.
- ⬜ **NFR-08** [M] Privacy-safe analytics with an opt-out.
- ⬜ **NFR-09** [M] Offline-first UI that degrades gracefully on poor networks.
- 🟨 **NFR-10** [M] Automated unit, integration and audio-regression tests, including mixing.
  - **Partial.** The server has 166 automated checks, all passing. The app's checks are written but have not been run yet.
- ⬜ **NFR-11** [2] Data-use estimates shown per quality level; Data saver cuts usage roughly in half.
- ⬜ **NFR-12** [2] Playback-start failure rate and rebuffer ratio tracked per release.
- ⬜ **NFR-13** [2] Load tests at 10× expected launch traffic; design for 1 million users.
- ⬜ **NFR-14** [2] Accessibility audit against WCAG AA before launch.
- ⬜ **NFR-15** [2] Battery targets set from benchmarks; analysis only when idle or charging.
- ⬜ **NFR-16** [3] Mix transitions start within 20 ms of schedule with no audible glitches in 99% of transitions.

## OPS: Release and operations

- ⬜ **OPS-01** [M] Closed beta (TestFlight and Play internal testing) with listener and artist cohorts.
- ⬜ **OPS-02** [M] Seed catalog: onboard the first 50 to 200 artists before public launch.
- ⬜ **OPS-03** [M] Support: in-app help, email, FAQ and a status page.
- ⬜ **OPS-04** [M] Staged rollouts (5%, 25%, 100%) with remote kill-switches for risky features such as YouTube and mixing modes.
- ⬜ **OPS-05** [M] Store listings: screenshots, description, Apple privacy labels, Google Data Safety form.
- ⬜ **OPS-06** [2] In-app feedback and well-timed rating prompts.
- ⬜ **OPS-07** [2] Artist community: onboarding sessions and a creator guide.
- ⬜ **OPS-08** [3] Public roadmap and changelog.