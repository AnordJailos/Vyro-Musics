# Vyro Music: Product Requirements

**Version 0.3 · 6 October 2026 · Status: for review**

*Changes in v0.3: statistics redesigned from the best of Spotify, Apple Music, YouTube Studio, Audiomack, stats.fm and Last.fm (STA-16 to STA-20, new module PRF for listener profiles). v0.2: Normal and Mixing playback modes (MIX-21 to MIX-23), one codebase for desktop (DEV-12, DEV-13).*

## 1. Vision

One app that combines the best ideas from Apple Music, Spotify, Lark Player, Audiomack and other leading music apps. Vyro is **ad-free and free at launch**, with offline listening, synced lyrics and professional-grade mixing, for **listeners and artists** on iOS and Android. Payments are fully built but switched off until we have users.

**Principles**
1. Ad-free, always.
2. Mixing is a core feature, not an add-on.
3. One account, two sides: listener and artist.
4. One library for every source: local files, artist uploads, open/licensed catalogs, YouTube.
5. Quality over quantity: sound, metadata and curation come before catalog size.
6. Free now, payment-ready from day one.

## 2. Roles

- **Listener**: streams, downloads, mixes, shares.
- **Artist**: a listener who also uploads, tracks stats and (later) earns.
- **Curator/Editor** (internal): builds playlists, features artists.
- **Admin/Moderator** (internal): reviews uploads, handles reports and support.

## 3. Content sources and what each can do

| Source | Mixing | Offline | Background play | Notes |
|---|---|---|---|---|
| Local files | Yes | Already on device | Yes | Lyrics from tags, .lrc files or catalog match |
| Vyro artist uploads | Yes | Yes (encrypted in-app) | Yes | Core catalog at launch |
| Open-licensed catalogs | Yes | Where license allows | Yes | Check each source's terms |
| Licensed label catalog | Per license | Per license | Yes | Later phase; some licenses restrict altering tracks |
| YouTube | **No** | **No** | **No** | Official player only, foreground, video visible; rules set by YouTube's policies and re-checked before every release |

## 4. How to read and review this document

Each requirement has an ID, a phase tag and a checkbox.

- **[M]** MVP launch · **[2]** Phase 2 (offline, lyrics, basic mixing, payments built but off) · **[3]** Phase 3 (smart mixing, social, advanced discovery) · **[4]** Phase 4 (monetization on, licensed catalog, expansion)
- To review, reply with IDs: *approve*, *change*, *remove* or *move phase* (for example: "MIX-07 move to phase 2, STU-15 remove").

---

## 5. Requirements

### AUTH: Listener accounts and onboarding
*Inspired by Spotify, Apple Music*

- [ ] **AUTH-01** [M] Sign up and log in with phone number and one-time code.
- [ ] **AUTH-02** [M] Sign up with email and password, with email verification.
- [ ] **AUTH-03** [M] Social sign-in with Google, plus Sign in with Apple on iOS.
- [ ] **AUTH-04** [M] Guest mode: browse and play without an account; prompt to sign up before saving or downloading.
- [ ] **AUTH-05** [M] First-launch taste picker (genres, moods, at least three artists), skippable.
- [ ] **AUTH-06** [M] Profile with name, photo, username, country and language.
- [ ] **AUTH-07** [M] Password reset and account recovery.
- [ ] **AUTH-08** [M] In-app account deletion with full data removal (required by both stores).
- [ ] **AUTH-09** [M] Age gate and parental-consent flow where law requires it; explicit-content filter for minors.
- [ ] **AUTH-10** [M] Privacy controls: private listening session, hide activity, control data sharing.
- [ ] **AUTH-11** [M] Terms and privacy consent stored with version and timestamp.
- [ ] **AUTH-12** [2] Multi-device login with synced library, playlists and settings.
- [ ] **AUTH-13** [2] Device manager: view and sign out other devices.
- [ ] **AUTH-14** [3] Optional two-factor authentication.

### ART: Artist registration and verification
*Inspired by Audiomack, Bandcamp, SoundCloud, Tidal*

- [ ] **ART-01** [M] "Become an artist" upgrade inside the same account: one login, two modes.
- [ ] **ART-02** [M] One-tap switch between Listener mode and Artist Studio.
- [ ] **ART-03** [M] Artist profile: stage name, bio, photo, banner, genres, social links.
- [ ] **ART-04** [M] Artist type: solo, group, producer/DJ, label/manager.
- [ ] **ART-05** [M] Rights declaration confirming ownership or control of uploads, stored with timestamp.
- [ ] **ART-06** [M] Non-exclusive streaming agreement; the artist keeps ownership.
- [ ] **ART-07** [M] Claim an auto-created artist profile through verification.
- [ ] **ART-08** [M] Impersonation protection: name-similarity checks and a report flow.
- [ ] **ART-09** [M] Artists keep all listener features; their listening informs recommendations (opt-out available).
- [ ] **ART-10** [2] Identity verification (ID check) required before payouts and the verified badge.
- [ ] **ART-11** [2] Verified-artist badge with a review process.
- [ ] **ART-12** [2] Payout profile: mobile money, bank or other methods, plus tax details where required.
- [ ] **ART-13** [2] Label/manager accounts that manage several artists.
- [ ] **ART-14** [2] Team roles on a profile: admin, editor, analyst.
- [ ] **ART-15** [2] Onboarding checklist: complete profile, first upload, first share.

### STU: Artist Studio
*Inspired by Audiomack, SoundCloud, Spotify for Artists*

- [ ] **STU-01** [M] Upload WAV, FLAC, MP3 and AAC files.
- [ ] **STU-02** [M] Resumable uploads that survive weak networks and app restarts.
- [ ] **STU-03** [M] Metadata: title, featured artists, genre, mood, language, explicit flag, release date, credits, optional ISRC.
- [ ] **STU-04** [M] Cover art upload with size and ratio checks.
- [ ] **STU-05** [M] Release types: single, EP, album, mixtape, DJ mix.
- [ ] **STU-06** [M] Automatic quality checks (clipping, silence, bitrate, upsampled fakes) with clear feedback.
- [ ] **STU-07** [M] Copyright fingerprint scan before publishing.
- [ ] **STU-08** [M] Draft, schedule, publish, unpublish and delete releases.
- [ ] **STU-09** [M] Edit metadata after publishing, with change history.
- [ ] **STU-10** [2] Synced lyrics editor with .lrc import.
- [ ] **STU-11** [2] Show detected BPM, key and loudness; artist can override mix-in and mix-out points.
- [ ] **STU-12** [2] Collaborator splits: percentage per contributor, accepted by each.
- [ ] **STU-13** [2] Per-track permissions: allow or deny downloads and sharing.
- [ ] **STU-14** [2] Pre-save and release countdown.
- [ ] **STU-15** [3] Smart link page for each release, shareable outside the app.
- [ ] **STU-16** [3] Short looping visual per track.
- [ ] **STU-17** [3] Music video upload or link.
- [ ] **STU-18** [3] Announcements to followers.

### LIB: Local library
*Inspired by Lark Player, Poweramp, Apple Music*

- [ ] **LIB-01** [M] Scan internal storage and SD card, with background incremental rescans.
- [ ] **LIB-02** [M] Formats: MP3, AAC/M4A, FLAC, ALAC, WAV, OGG, Opus, AIFF.
- [ ] **LIB-03** [M] Read tags (ID3, Vorbis, MP4) and embedded artwork.
- [ ] **LIB-04** [M] Browse by songs, albums, artists, genres and folders.
- [ ] **LIB-05** [M] Include/exclude folders; ignore short clips such as voice notes.
- [ ] **LIB-06** [M] One unified library for local and online tracks, with source badges.
- [ ] **LIB-07** [M] Like any track; Liked Songs list.
- [ ] **LIB-08** [M] Delete local files from inside the app, with confirmation.
- [ ] **LIB-09** [2] Built-in tag editor (title, artist, album, artwork).
- [ ] **LIB-10** [2] Fix missing metadata and artwork by matching against the Vyro catalog.
- [ ] **LIB-11** [2] Recently added, recently played, most played.
- [ ] **LIB-12** [2] Duplicate detection across local files and downloads.
- [ ] **LIB-13** [2] Import playlists from other services (file import or connected services where allowed).
- [ ] **LIB-14** [3] Cloud sync of library metadata and playlists (not the audio files).
- [ ] **LIB-15** [3] Optional private cloud locker: stream your own uploaded files on other devices.

### SRC: Streaming sources and YouTube
*Inspired by Lark Player, Audiomack*

- [ ] **SRC-01** [M] Stream Vyro artist uploads with adaptive quality.
- [ ] **SRC-02** [M] Source badge on every track (Local, Vyro, Open, YouTube) plus a "Mixable" indicator.
- [ ] **SRC-03** [M] Unified search with results grouped by source.
- [ ] **SRC-04** [M] YouTube search integrated into Vyro search, in its own section.
- [ ] **SRC-05** [M] YouTube plays only through the official player, in the foreground, with video visible and unmodified.
- [ ] **SRC-06** [M] YouTube items never enter the mix engine; transitions to or from them are a clean cut.
- [ ] **SRC-07** [M] No download, offline copy, audio extraction or background play of YouTube items.
- [ ] **SRC-08** [M] YouTube items can be saved to playlists as links only, clearly marked.
- [ ] **SRC-09** [M] YouTube policy compliance review before every release, with a remote switch to disable YouTube instantly.
- [ ] **SRC-10** [2] Clean hand-off between the YouTube player and the Vyro audio engine in mixed queues.
- [ ] **SRC-11** [2] Open-licensed catalog integration, with the license checked per source.
- [ ] **SRC-12** [4] Licensed major and independent label catalog through deals or distributors, with per-license rules for mixing and offline.

### PLY: Playback core
*Inspired by Apple Music, Spotify, Poweramp*

- [ ] **PLY-01** [M] Play, pause, seek, next, previous, shuffle, repeat (off, one, all).
- [ ] **PLY-02** [M] Background playback with lock-screen and notification controls (own content).
- [ ] **PLY-03** [M] Queue: play next, add, reorder, remove, clear, view history.
- [ ] **PLY-04** [M] Mini-player and full-screen Now Playing with swipe gestures.
- [ ] **PLY-05** [M] Correct audio-focus handling for calls, navigation and other apps.
- [ ] **PLY-06** [M] Headphone and Bluetooth media buttons; pause on unplug.
- [ ] **PLY-07** [M] Resume exactly where the user left off, even after the app is killed.
- [ ] **PLY-08** [M] Network resilience: buffering indicator, auto-retry, drop to a lower bitrate instead of stalling.
- [ ] **PLY-09** [2] Gapless playback.
- [ ] **PLY-10** [2] Sleep timer (minutes, end of track, end of album) with gentle fade-out.
- [ ] **PLY-11** [2] Playback speed with pitch preservation.
- [ ] **PLY-12** [2] 10-band equalizer with presets, bass boost and per-device profiles.
- [ ] **PLY-13** [2] Loudness normalization so tracks play at similar volume (toggle).
- [ ] **PLY-14** [2] Streaming quality settings: Auto, Data saver, Normal, High, Lossless; separate for Wi-Fi and cellular.
- [ ] **PLY-15** [2] Preload the next track so skipping is instant.
- [ ] **PLY-16** [2] Smart shuffle that avoids repeats and mixes in recommendations (toggle).
- [ ] **PLY-17** [3] Cross-device handoff and remote control.
- [ ] **PLY-18** [3] Car mode with a simplified, large-button UI.
- [ ] **PLY-19** [3] Spatial audio mode for headphones, where licensing and technology allow.

### MIX: Mixing and transitions
*Inspired by Apple Music Automix, DJ software*

- [ ] **MIX-01** [M] Crossfade between consecutive tracks, 0 to 12 seconds, adjustable, equal-power curve.
- [ ] **MIX-02** [2] Crossfade settings per context: playlists on, albums off by default, radio on.
- [ ] **MIX-03** [2] Fade-in on start and fade-out on pause to avoid clicks.
- [ ] **MIX-04** [2] Server-side analysis of every Vyro track: BPM, beat grid, key, loudness, energy, intro and outro points, silence.
- [ ] **MIX-05** [2] On-device analysis for local files, cached, run only while idle or charging.
- [ ] **MIX-06** [2] Fallback to a simple crossfade when analysis is missing or low confidence.
- [ ] **MIX-07** [2] Mixing works offline using downloaded and local tracks with cached analysis.
- [ ] **MIX-08** [2] Respect license flags: non-mixable tracks get a plain gap or crossfade only.
- [ ] **MIX-09** [3] Automix: transitions placed automatically at the best mix-out and mix-in points.
- [ ] **MIX-10** [3] Beat-matched transitions using tempo-sync within a safe limit (about ±6%).
- [ ] **MIX-11** [3] Harmonic mixing: prefer key-compatible neighbors.
- [ ] **MIX-12** [3] Transition styles: crossfade, cut, echo-out, filter sweep, bass-swap, with intensity control.
- [ ] **MIX-13** [3] "Mix this playlist": reorder by BPM, key and energy for smooth flow (optional, undoable).
- [ ] **MIX-14** [3] Energy-arc modes: warm-up, steady, peak, cool-down; match BPM to running cadence.
- [ ] **MIX-15** [3] Mix editor: adjust transition length and style per track pair and save the mix.
- [ ] **MIX-16** [3] Share a mix as a playlist with its transition settings (not rendered audio).
- [ ] **MIX-17** [3] Artist-defined default mix points per track.
- [ ] **MIX-18** [3] Artist opt-out of tempo or pitch alteration per track.
- [ ] **MIX-19** [3] Mixing runs reliably in the background and with the screen off.
- [ ] **MIX-20** [4] DJ mode for creators: two-deck view with waveforms.
- [ ] **MIX-21** [M] Two playback modes, switchable at any time: **Normal** (songs change one after another, no overlap) and **Mixing** (blends apply when a song ends, and on next and previous).
- [ ] **MIX-22** [M] In Mixing mode, separate blend lengths (1 to 12 seconds) for "end of song" and "next / back".
- [ ] **MIX-23** [M] Previous restarts the current song after the first 3 seconds, in both modes; otherwise it goes back to the earlier song (blended in Mixing mode).

### LYR: Lyrics
*Inspired by Apple Music, Spotify, Musixmatch*

- [ ] **LYR-01** [2] Time-synced lyrics highlighted line by line with auto-scroll.
- [ ] **LYR-02** [2] Full-screen lyrics view; tap a line to seek.
- [ ] **LYR-03** [2] Plain (unsynced) lyrics fallback.
- [ ] **LYR-04** [2] Read embedded lyrics and sidecar .lrc files for local tracks.
- [ ] **LYR-05** [2] Artist-supplied lyrics from Studio for Vyro tracks.
- [ ] **LYR-06** [2] Lyrics stay in sync through crossfades and tempo changes.
- [ ] **LYR-07** [2] Report wrong lyrics; artists can correct them.
- [ ] **LYR-08** [2] Share a lyric card as an image (licensed or artist-supplied lyrics only).
- [ ] **LYR-09** [3] Lyrics translation into the user's language.
- [ ] **LYR-10** [3] Romanization for non-Latin scripts.
- [ ] **LYR-11** [3] Word-by-word highlighting.
- [ ] **LYR-12** [3] Karaoke mode with vocal reduction where stems are available and the artist allows it.
- [ ] **LYR-13** [3] Floating lyrics overlay on Android.
- [ ] **LYR-14** [4] Licensed lyrics provider for the wider catalog.

### OFF: Offline and downloads
*Inspired by Audiomack, Apple Music, Spotify*

- [ ] **OFF-01** [2] Download tracks, albums, playlists and mixtapes where artist and license allow.
- [ ] **OFF-02** [2] Downloads stored encrypted inside the app, not extractable as plain files.
- [ ] **OFF-03** [2] Download queue with pause, resume and retry; Wi-Fi-only option.
- [ ] **OFF-04** [2] Choose storage location (internal or SD card) and download quality.
- [ ] **OFF-05** [2] Storage manager: size per item, delete all, auto-delete unplayed downloads after N days.
- [ ] **OFF-06** [2] Offline mode that shows and plays only downloaded and local content.
- [ ] **OFF-07** [2] Optional auto-download: new releases from followed artists, liked songs, chosen playlists.
- [ ] **OFF-08** [2] Smart cache for frequently played tracks.
- [ ] **OFF-09** [2] Lyrics and analysis data downloaded with each track so mixing and lyrics work offline.
- [ ] **OFF-10** [2] Offline listens recorded locally and synced when back online.
- [ ] **OFF-11** [2] Free downloads at launch, with entitlement hooks ready to limit later via feature flag.
- [ ] **OFF-12** [3] Offline validity window (for example 30 days) with silent re-verification when online.

### DSC: Search, browse and charts
*Inspired by Spotify, Apple Music, Audiomack*

- [ ] **DSC-01** [M] Unified search across tracks, artists, albums, playlists, users and local files.
- [ ] **DSC-02** [M] Instant suggestions, typo tolerance, recent searches.
- [ ] **DSC-03** [M] Browse by genre, mood, activity, decade and language.
- [ ] **DSC-04** [M] Home feed: continue listening, new releases, picks for you, trending.
- [ ] **DSC-05** [M] Charts: trending, top songs, albums and artists; global and per country; rising artists.
- [ ] **DSC-06** [M] Artist page: top tracks, discography, about, similar artists, follow.
- [ ] **DSC-07** [M] Album/release page with credits, duration and total tracks.
- [ ] **DSC-08** [M] Explicit-content preference applied across search and browse.
- [ ] **DSC-09** [2] Editor-curated mood and activity playlists (Chill, Focus, Workout, Party, Night Drive, Worship, more).
- [ ] **DSC-10** [2] Genre hubs for regional scenes (Afrobeats, Amapiano, Hip-Hop, Gospel and more).
- [ ] **DSC-11** [2] Search by lyric snippet.
- [ ] **DSC-12** [2] New releases page with filters.
- [ ] **DSC-13** [3] Song recognition (identify a song playing nearby).
- [ ] **DSC-14** [3] Radio: infinite stations from an artist, track or genre.
- [ ] **DSC-15** [3] Editorial features: artist spotlights, artist of the week, interviews.
- [ ] **DSC-16** [3] Music videos and live performances section.
- [ ] **DSC-17** [3] Events and ticket links on artist pages.
- [ ] **DSC-18** [4] Podcasts and spoken-word shows.

### REC: Recommendations and personalization
*Inspired by Spotify, YouTube's two-stage approach, Apple Music*

- [ ] **REC-01** [M] Cold-start recommendations from the taste picker, editorial lists and regional popularity.
- [ ] **REC-02** [2] Consent-based event logging: plays, completions, skips, replays, saves, adds, shares, searches.
- [ ] **REC-03** [2] Daily mixes grouped by taste cluster.
- [ ] **REC-04** [2] Weekly discovery playlist of new-to-you tracks.
- [ ] **REC-05** [2] New-release radar from followed artists.
- [ ] **REC-06** [2] "Listeners also play" and similar artists and tracks.
- [ ] **REC-07** [2] Fairness quota: reserve a share of recommendation slots for new and independent artists.
- [ ] **REC-08** [2] Local-file taste signals included, with consent.
- [ ] **REC-09** [2] User controls: pause personalization, reset recommendations, clear history, "not interested".
- [ ] **REC-10** [3] Two-stage engine: candidate generation, then ranking, with vector search.
- [ ] **REC-11** [3] Context awareness: time of day, activity, device, session mood.
- [ ] **REC-12** [3] Diversity controls and thumbs up/down to avoid filter bubbles.
- [ ] **REC-13** [3] "Because you listened to…" explanations.
- [ ] **REC-14** [3] Yearly recap for listeners and for artists.
- [ ] **REC-15** [3] Blend: merge two friends' tastes into a shared, updating playlist.
- [ ] **REC-16** [3] Playlist generator from a text prompt.
- [ ] **REC-17** [4] AI-led listening sessions with a voice host.

### PLS: Playlists
*Inspired by Spotify, Apple Music*

- [ ] **PLS-01** [M] Create, rename, edit and delete playlists with cover and description.
- [ ] **PLS-02** [M] Add any source (local, Vyro, YouTube link) to a playlist, with badges.
- [ ] **PLS-03** [M] Reorder, bulk select, sort and remove duplicates.
- [ ] **PLS-04** [M] Save albums and mixtapes to the library.
- [ ] **PLS-05** [2] Public, private and link-only playlists.
- [ ] **PLS-06** [2] Collaborative playlists with invite links and contributor roles.
- [ ] **PLS-07** [2] Folders and pinning.
- [ ] **PLS-08** [2] Playlist sync across devices.
- [ ] **PLS-09** [3] Smart playlists by rules (genre, BPM, year, play count, source).
- [ ] **PLS-10** [3] Auto-generated cover mosaics.
- [ ] **PLS-11** [3] Follow other users' playlists, with follower counts.
- [ ] **PLS-12** [3] "Mix mode" toggle on a playlist.

### SOC: Social and sharing
*Inspired by Spotify, SoundCloud, Audiomack*

- [ ] **SOC-01** [M] Share tracks, albums, artists and playlists via link; deep links open the app or the store page.
- [ ] **SOC-02** [M] Block, mute and report users and content (required for user-generated content).
- [ ] **SOC-03** [2] Share cards for stories and messaging apps.
- [ ] **SOC-04** [2] Follow users and artists.
- [ ] **SOC-05** [3] Opt-in friend activity feed with a private-session override.
- [ ] **SOC-06** [3] Group listening: shared queue and synced playback.
- [ ] **SOC-07** [3] Scannable share codes.
- [ ] **SOC-08** [3] Timed comments on the waveform, with moderation tools for artists.
- [ ] **SOC-09** [3] Reposts to followers.
- [ ] **SOC-10** [3] 30-second preview clips for sharing.
- [ ] **SOC-11** [3] Fan support: tips and supporter badges (needs payments live).

### UIX: Design, themes, accessibility and localization
*Inspired by Lark Player, Apple Music*

- [ ] **UIX-01** [M] Themes: Midnight (dark), Daylight (light), AMOLED Black, follow system.
- [ ] **UIX-02** [M] Smooth 60 fps animations with no layout jumps.
- [ ] **UIX-03** [M] Accessibility: VoiceOver and TalkBack, scalable text, high contrast, color-blind-safe palettes, large touch targets.
- [ ] **UIX-04** [M] English at launch, with a localization system and right-to-left support ready for more languages.
- [ ] **UIX-05** [M] Smooth performance on low-end phones (2 GB RAM) and small app size.
- [ ] **UIX-06** [M] Short onboarding tour explaining mixing, lyrics and offline.
- [ ] **UIX-07** [2] Accent themes (Neon, Sunset, Forest, Ocean).
- [ ] **UIX-08** [2] Album Color theme: palette drawn from cover art.
- [ ] **UIX-09** [2] Now Playing styles: classic, large cover, lyrics-first, waveform, visualizer.
- [ ] **UIX-10** [2] Home-screen and lock-screen widgets.
- [ ] **UIX-11** [2] Tablet and foldable layouts, landscape mode.
- [ ] **UIX-12** [2] Helpful empty states and skeleton loaders.
- [ ] **UIX-13** [3] Seasonal and artist-made themes.
- [ ] **UIX-14** [3] Customizable bottom navigation and home sections.

### STA: Artist analytics
*Inspired by Spotify for Artists, Apple Music for Artists, Audiomack*

- [ ] **STA-01** [M] Dashboard: plays, unique listeners, followers, saves, playlist adds, with date ranges.
- [ ] **STA-02** [M] Per-track stats: completion rate, skip rate, replays, average listen time.
- [ ] **STA-03** [2] Audience: top countries and cities, age bands, device types, aggregated only.
- [ ] **STA-04** [2] Discovery sources: search, recommendations, playlists, charts, shares, direct.
- [ ] **STA-05** [2] Listening heatmap by hour and weekday.
- [ ] **STA-06** [2] Playlist placements: which playlists feature the artist's tracks.
- [ ] **STA-07** [2] Mixing stats: how often tracks appear in transitions and which tracks they mix with.
- [ ] **STA-08** [2] Real-time view for the first 48 hours after release.
- [ ] **STA-09** [2] CSV and PDF export.
- [ ] **STA-10** [2] Minimum thresholds so individual listeners can never be identified.
- [ ] **STA-11** [2] Fraud filtering and a published "valid stream" rule (about 30 seconds).
- [ ] **STA-12** [3] Release comparison and milestone notifications.
- [ ] **STA-13** [3] Opt-in top-fans insights.
- [ ] **STA-14** [3] Public monthly listeners on artist pages.
- [ ] **STA-15** [3] Earnings view (when monetization is on), pending versus paid.
- [ ] **STA-16** [M] Every number shown next to the period just before it, with an up or down percentage.
- [ ] **STA-17** [M] Retention curve per song: the share of plays still going at each 10% of the song.
- [ ] **STA-18** [M] Audience split into new, returning and super listeners (5 or more plays in the period).
- [ ] **STA-19** [M] Period picker: 7 days, 28 days, 90 days, 12 months.
- [ ] **STA-20** [M] Plays by hour for the last 48 hours ("right now" view).

### PAY: Payments, subscriptions and payouts
*Built fully, enforced later*

- [ ] **PAY-01** [2] Plan model and entitlements engine; everyone starts on "Free (Founding)".
- [ ] **PAY-02** [2] Global and per-feature flags to switch paywalls on or off without an app update.
- [ ] **PAY-03** [2] Apple in-app purchase (StoreKit 2) and Google Play Billing implemented and tested, hidden behind flags.
- [ ] **PAY-04** [2] Server-side receipt validation and webhooks as the single source of truth.
- [ ] **PAY-05** [2] Plan types: Individual, Student, Family, Annual; regional pricing.
- [ ] **PAY-06** [2] Free trials, intro offers, promo codes and gift codes.
- [ ] **PAY-07** [2] Restore purchases, grace periods, billing retry, cancellation and refund handling.
- [ ] **PAY-08** [2] Local payment methods (mobile money, cards, carrier billing) through web checkout where store rules allow; legal check per market.
- [ ] **PAY-09** [2] Founding Listener badge and grandfathering rules for early users.
- [ ] **PAY-10** [2] Receipts, invoices and tax/VAT handling.
- [ ] **PAY-11** [2] Payment and promo-code fraud detection.
- [ ] **PAY-12** [2] Paywall screens built and tested in staging, disabled in production.
- [ ] **PAY-13** [3] Artist earnings ledger with per-stream accrual and multi-currency support.
- [ ] **PAY-14** [3] Subscriber analytics for admins: conversion, churn, recurring revenue.
- [ ] **PAY-15** [3] Fan tips with a platform fee.
- [ ] **PAY-16** [4] Decide the premium perks (candidates: lossless and hi-res, unlimited downloads, family plans, early access). Ad-free stays free.
- [ ] **PAY-17** [4] Decide the payout model (pro-rata pool or user-centric pool) and publish it to artists.
- [ ] **PAY-18** [4] Scheduled payouts via mobile money or bank, with a minimum threshold and payout history.

### BKE: Backend and content pipeline

- [ ] **BKE-01** [M] Versioned API with rate limiting.
- [ ] **BKE-02** [M] PostgreSQL for users, catalog and playlists; separate analytics store for events.
- [ ] **BKE-03** [M] Object storage for masters and encoded files, delivered through a CDN.
- [ ] **BKE-04** [M] Transcoding pipeline: master to AAC at multiple bitrates and Opus; adaptive HLS; optional lossless tier.
- [ ] **BKE-05** [M] Loudness measurement (EBU R128 / ReplayGain) at ingest.
- [ ] **BKE-06** [M] Audio fingerprinting for duplicates and copyright matches.
- [ ] **BKE-07** [M] Search engine with typo tolerance and multilingual support.
- [ ] **BKE-08** [M] Signed, expiring stream URLs with hotlink protection.
- [ ] **BKE-09** [M] Push notification service (APNs and FCM) with user preferences.
- [ ] **BKE-10** [M] Staging and production environments, infrastructure as code, CI/CD.
- [ ] **BKE-11** [M] Monitoring, logging, alerting and error tracking.
- [ ] **BKE-12** [M] Backups and a disaster-recovery plan with tested restores.
- [ ] **BKE-13** [M] Feature-flag and remote-config service.
- [ ] **BKE-14** [2] Audio analysis service for BPM, beats, key, energy and cue points.
- [ ] **BKE-15** [2] Event ingestion pipeline (queue and stream) for listens and analytics.
- [ ] **BKE-16** [2] Encrypted offline package service with per-device keys.
- [ ] **BKE-17** [2] Background job system for ingest, analysis and email.
- [ ] **BKE-18** [2] Cost dashboard: streaming, storage and delivery cost per active user.
- [ ] **BKE-19** [3] Recommendation service with feature store and vector index.
- [ ] **BKE-20** [3] Multi-region CDN and edge caching.

### QUA: Audio quality
*Inspired by Apple Music, Tidal*

- [ ] **QUA-01** [M] Normal streaming at 128 kbps or higher (Opus/AAC); High at 256 kbps or higher. Free-tier ceiling to be decided.
- [ ] **QUA-02** [M] Upload quality gates (minimum bitrate, fake-upsample detection).
- [ ] **QUA-03** [2] Lossless playback for local files (FLAC, ALAC), bit-perfect where hardware allows.
- [ ] **QUA-04** [2] Loudness target of about -14 LUFS with a user setting.
- [ ] **QUA-05** [2] Headroom management and clip prevention inside the mix engine.
- [ ] **QUA-06** [2] Listening and performance benchmarks on target devices before each release.
- [ ] **QUA-07** [3] Hi-res support (up to 24-bit/192 kHz) for local and uploaded files.
- [ ] **QUA-08** [3] USB DAC and Bluetooth codec support (LDAC, aptX, AAC).
- [ ] **QUA-09** [3] Quality badges on tracks (Standard, Lossless, Hi-Res).
- [ ] **QUA-10** [4] Spatial audio ingestion (licensing check required).

### DEV: Devices and platform integrations

- [ ] **DEV-01** [M] iOS and Android apps with a shared UI codebase and native audio engine modules.
- [ ] **DEV-02** [M] Lock-screen, notification and quick-settings media controls.
- [ ] **DEV-03** [M] Correct background-audio setup: iOS background mode, Android foreground service, battery-optimization handling.
- [ ] **DEV-04** [2] Bluetooth, AirPlay and Google Cast output.
- [ ] **DEV-05** [2] "Open with Vyro" for audio files from other apps.
- [ ] **DEV-06** [2] Optional scrobbling to listening-history services.
- [ ] **DEV-07** [3] CarPlay and Android Auto.
- [ ] **DEV-08** [3] Smartwatch companion (Apple Watch, Wear OS).
- [ ] **DEV-09** [3] Voice assistant support (Siri, Google Assistant).
- [ ] **DEV-10** [3] Web player with the same account.
- [ ] **DEV-11** [4] Smart TV app.
- [ ] **DEV-12** [M] One Flutter codebase for Android, iOS, Windows and macOS (Linux later).
- [ ] **DEV-13** [2] Desktop conventions: resizable window, keyboard shortcuts and media keys, menu-bar or system-tray controls, drag-and-drop of audio files.

### SAF: Trust, safety and legal

- [ ] **SAF-01** [M] Terms of Service, Privacy Policy and artist agreement reviewed by legal counsel in each launch market.
- [ ] **SAF-02** [M] Copyright takedown process with counter-notice and a repeat-infringer policy.
- [ ] **SAF-03** [M] Moderation queue for uploads, profiles, images and comments.
- [ ] **SAF-04** [M] Explicit-content labeling and filtering.
- [ ] **SAF-05** [M] Data-protection compliance: access, export and deletion rights.
- [ ] **SAF-06** [M] Data minimization; encryption at rest and in transit.
- [ ] **SAF-07** [M] Child-safety rules: age limits, no targeting of minors, reporting channel.
- [ ] **SAF-08** [M] Music licensing and royalty-reporting obligations (publishing and performance rights) confirmed per market.
- [ ] **SAF-09** [M] Trademark and name clearance for "Vyro Music" (pending).
- [ ] **SAF-10** [M] App Store and Google Play policy checklist, including user-generated-content rules.
- [ ] **SAF-11** [2] Anti-fraud: bot, stream-farming and fake-account detection.
- [ ] **SAF-12** [2] Rate limits and abuse protection on uploads and APIs.
- [ ] **SAF-13** [2] Published explanations of how stream counts and recommendations work.
- [ ] **SAF-14** [2] Dispute and appeal process for artists.
- [ ] **SAF-15** [2] Penetration test before public launch and a vulnerability disclosure channel.

### PRF: Listener profile and statistics
*Inspired by Apple Music Replay, Spotify Wrapped, stats.fm, Last.fm*

- [ ] **PRF-01** [M] Profile header: photo, name and username.
- [ ] **PRF-02** [M] Period picker: 4 weeks, 6 months, this year, all time.
- [ ] **PRF-03** [M] Minutes listened as the headline number, with hours.
- [ ] **PRF-04** [M] Listening streak: consecutive days with listening, in the listener's own time zone.
- [ ] **PRF-05** [M] Top artists, top songs and top genres for the period.
- [ ] **PRF-06** [M] Listening clock (which hours of the day) and a listening personality (night owl, early bird, daytime, all-day).
- [ ] **PRF-07** [M] Songs blended and new artists discovered, the two numbers only Vyro can show.
- [ ] **PRF-08** [M] Switch to keep listening stats private, only visible to the listener.
- [ ] **PRF-09** [2] Public profile showing the stats the listener chose to share.
- [ ] **PRF-10** [3] Year-in-music recap with a shareable card (see REC-14).
- [ ] **PRF-11** [2] On-device statistics for local files and YouTube plays, merged with server statistics so the profile covers everything the listener plays.

### ADM: Admin and curation

- [ ] **ADM-01** [M] Admin console with roles and an audit log.
- [ ] **ADM-02** [M] Approve or reject uploads, with bulk actions and reasons sent to artists.
- [ ] **ADM-03** [M] User and artist management: suspend, verify, merge duplicates.
- [ ] **ADM-04** [2] Editorial tools: build playlists, schedule home sections, feature artists.
- [ ] **ADM-05** [2] Chart management with fraud exclusions and logged manual overrides.
- [ ] **ADM-06** [2] Feature-flag and remote-config interface.
- [ ] **ADM-07** [2] Support tools: user lookup, entitlement and refund adjustments.
- [ ] **ADM-08** [2] Reports dashboard with response-time targets.
- [ ] **ADM-09** [2] A/B testing framework.
- [ ] **ADM-10** [3] Business dashboards: daily and monthly actives, retention, listening hours, cost per user.
- [ ] **ADM-11** [3] Segmented announcement and push campaigns.

### NFR: Non-functional requirements

- [ ] **NFR-01** [M] Start-to-play under 1.5 seconds on 4G for Vyro tracks (75th percentile).
- [ ] **NFR-02** [M] Cold start under 2 seconds on mid-range phones.
- [ ] **NFR-03** [M] Crash-free sessions of at least 99.5%.
- [ ] **NFR-04** [M] Streaming API availability of at least 99.9%.
- [ ] **NFR-05** [M] Supported OS: Android 8+ and iOS 16+ (confirm against market device data).
- [ ] **NFR-06** [M] Install size under 60 MB.
- [ ] **NFR-07** [M] Security aligned with OWASP MASVS: certificate pinning, no secrets in the app.
- [ ] **NFR-08** [M] Privacy-safe analytics with an opt-out.
- [ ] **NFR-09** [M] Offline-first UI that degrades gracefully on poor networks.
- [ ] **NFR-10** [M] Automated unit, integration and audio-regression tests, including mixing.
- [ ] **NFR-11** [2] Data-use estimates shown per quality level; Data saver cuts usage roughly in half.
- [ ] **NFR-12** [2] Playback-start failure rate and rebuffer ratio tracked per release.
- [ ] **NFR-13** [2] Load tests at 10× expected launch traffic; design for 1 million users.
- [ ] **NFR-14** [2] Accessibility audit against WCAG AA before launch.
- [ ] **NFR-15** [2] Battery targets set from benchmarks; analysis only when idle or charging.
- [ ] **NFR-16** [3] Mix transitions start within 20 ms of schedule with no audible glitches in 99% of transitions.

### OPS: Release and operations

- [ ] **OPS-01** [M] Closed beta (TestFlight and Play internal testing) with listener and artist cohorts.
- [ ] **OPS-02** [M] Seed catalog: onboard the first 50 to 200 artists before public launch.
- [ ] **OPS-03** [M] Support: in-app help, email, FAQ and a status page.
- [ ] **OPS-04** [M] Staged rollouts (5%, 25%, 100%) with remote kill-switches for risky features such as YouTube and mixing modes.
- [ ] **OPS-05** [M] Store listings: screenshots, description, Apple privacy labels, Google Data Safety form.
- [ ] **OPS-06** [2] In-app feedback and well-timed rating prompts.
- [ ] **OPS-07** [2] Artist community: onboarding sessions and a creator guide.
- [ ] **OPS-08** [3] Public roadmap and changelog.

---

## 6. Decisions needed from you

1. **Launch markets**: this decides licensing, payments, languages and legal review.
2. **Catalog plan at launch**: artist uploads plus open-licensed sources, with label deals later. Confirm?
3. **Free-tier audio quality**: which quality ceiling can the budget afford?
4. **Artist payout model**: pro-rata or user-centric (decided before monetization, announced early).
5. **Lyrics source** beyond artist-supplied and local files.
6. **Minimum age** and parental-consent rules.
7. **Languages** beyond English at launch.
8. **Tech stack confirmation**: Flutter UI with native audio engines (my recommendation) versus fully native.
9. **Funding runway** for ad-free and free as users grow.
10. **Name clearance** for Vyro Music (trademark, stores, domains, handles).

## 7. Proposed build order

1. Project setup, design system and themes, backend foundations (BKE, UIX).
2. Accounts and artist registration (AUTH, ART).
3. Audio core: playback, queue, local library, background play (PLY, LIB).
4. Studio uploads and the content pipeline (STU, BKE).
5. Search, home, charts and playlists (DSC, PLS).
6. Offline, lyrics, then basic crossfade (OFF, LYR, MIX 01 to 08).
7. Payments built but disabled (PAY).
8. Smart mixing, recommendations, social (MIX 09+, REC, SOC).
