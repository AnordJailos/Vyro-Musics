-- Minimal catalog record so plays can be attributed to artists (full Studio upload comes later).
create table tracks (
  id uuid primary key default gen_random_uuid(),
  artist_id uuid not null references users(id) on delete cascade,
  title text not null,
  genre text not null default 'other',
  duration_ms integer not null check (duration_ms between 1000 and 21600000),
  created_at timestamptz not null default now()
);
create index tracks_artist on tracks (artist_id);

create table follows (
  user_id uuid not null references users(id) on delete cascade,
  artist_id uuid not null references users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, artist_id),
  check (user_id <> artist_id)
);
create index follows_artist on follows (artist_id, created_at);

create table saves (
  user_id uuid not null references users(id) on delete cascade,
  track_id uuid not null references tracks(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, track_id)
);
create index saves_track on saves (track_id, created_at);

-- One row per play. The client generates the id, so retries and offline syncs are safe.
-- When a listener deletes their account the row is kept but anonymized (user_id becomes null),
-- so artists' totals stay correct without keeping anyone's identity.
create table listen_events (
  id uuid primary key,
  user_id uuid references users(id) on delete set null,
  track_id uuid not null references tracks(id) on delete cascade,
  artist_id uuid not null references users(id) on delete cascade,
  started_at timestamptz not null,
  listened_ms integer not null check (listened_ms >= 0),
  valid boolean not null,
  source text not null check (source in ('search', 'recommendation', 'playlist', 'chart', 'share', 'library', 'direct')),
  platform text not null check (platform in ('android', 'ios', 'windows', 'macos', 'linux', 'web')),
  mode text not null check (mode in ('normal', 'mixing')),
  mixed_with_track_id uuid references tracks(id) on delete set null,
  country text,
  created_at timestamptz not null default now()
);
create index le_artist_time on listen_events (artist_id, started_at);
create index le_user_time on listen_events (user_id, started_at);
create index le_track_time on listen_events (track_id, started_at);
