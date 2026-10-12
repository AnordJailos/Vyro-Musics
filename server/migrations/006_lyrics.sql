-- Lyrics supplied by the artist, plain or synced (LRC), and listeners' reports about them.
alter table tracks add column lyrics text;
alter table tracks add column lyrics_synced boolean not null default false;
alter table tracks add column lyrics_updated_at timestamptz;

create table lyric_reports (
  track_id uuid not null references tracks(id) on delete cascade,
  user_id uuid not null references users(id) on delete cascade,
  reason text not null check (reason in ('wrong_text', 'wrong_timing', 'offensive', 'copyright', 'other')),
  created_at timestamptz not null,
  primary key (track_id, user_id)
);
