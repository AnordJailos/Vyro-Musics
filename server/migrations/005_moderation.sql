-- Review before release, copyright checks, takedowns, suspensions and an audit trail.
alter table users add column role text not null default 'user' check (role in ('user', 'moderator', 'admin'));
alter table users add column suspended_at timestamptz;
alter table users add column suspension_reason text;

alter table tracks drop constraint tracks_status_check;
alter table tracks add constraint tracks_status_check
  check (status in ('draft', 'ready', 'in_review', 'published', 'rejected', 'held', 'taken_down', 'removed'));
alter table tracks add column submitted_at timestamptz;
alter table tracks add column reviewed_at timestamptz;
alter table tracks add column reviewed_by uuid references users(id) on delete set null;
alter table tracks add column reject_reason text;
alter table tracks add column review_note text;
alter table tracks add column checks jsonb not null default '{}';
create index tracks_review_queue on tracks (submitted_at) where status in ('in_review', 'held');

-- Audio fingerprints (Chromaprint). The hashes are an index for finding candidate matches quickly.
create table track_fingerprints (
  track_id uuid primary key references tracks(id) on delete cascade,
  duration_s integer not null,
  raw integer[] not null,
  created_at timestamptz not null
);
create table fingerprint_hashes (
  track_id uuid not null references tracks(id) on delete cascade,
  hash integer not null,
  pos integer not null
);
create index fingerprint_hashes_hash on fingerprint_hashes (hash);
create index fingerprint_hashes_track on fingerprint_hashes (track_id);

create table audit_log (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references users(id) on delete set null,
  action text not null,
  target_type text not null,
  target_id text,
  details jsonb not null default '{}',
  created_at timestamptz not null
);
create index audit_log_time on audit_log (created_at desc);

create table takedown_notices (
  id uuid primary key default gen_random_uuid(),
  track_id uuid not null references tracks(id) on delete cascade,
  claimant_name text not null,
  claimant_email text not null,
  claimant_company text,
  statement text not null,
  signature text not null,
  status text not null default 'open' check (status in ('open', 'counter_filed', 'upheld', 'restored')),
  previous_status text not null,
  counter_statement text,
  counter_signature text,
  counter_at timestamptz,
  created_at timestamptz not null,
  resolved_at timestamptz,
  resolved_by uuid references users(id) on delete set null
);
create index takedown_notices_status on takedown_notices (status, created_at);

create table copyright_strikes (
  id uuid primary key default gen_random_uuid(),
  artist_id uuid not null references users(id) on delete cascade,
  notice_id uuid not null references takedown_notices(id) on delete cascade,
  created_at timestamptz not null
);
create index copyright_strikes_artist on copyright_strikes (artist_id);
