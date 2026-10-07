create table users (
  id uuid primary key default gen_random_uuid(),
  email text not null unique,
  password_hash text not null,
  display_name text not null,
  username text not null unique,
  country text,
  created_at timestamptz not null default now()
);

create table consents (
  user_id uuid not null references users(id) on delete cascade,
  document text not null,
  version text not null,
  accepted_at timestamptz not null default now(),
  primary key (user_id, document, version)
);

create table artist_profiles (
  user_id uuid primary key references users(id) on delete cascade,
  stage_name text not null,
  bio text not null default '',
  artist_type text not null check (artist_type in ('solo', 'group', 'producer_dj', 'label_manager')),
  rights_accepted_at timestamptz not null,
  agreement_version text not null,
  verified boolean not null default false,
  created_at timestamptz not null default now()
);
create unique index artist_stage_name_ci on artist_profiles (lower(stage_name));

create table refresh_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  token_hash text not null unique,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);

create table feature_flags (
  key text primary key,
  enabled boolean not null,
  description text not null default ''
);
insert into feature_flags (key, enabled, description) values
  ('payments_enforced', false, 'Paywalls on or off (PAY-02). Off at launch.'),
  ('youtube_enabled', true, 'Kill-switch for YouTube search and watch (SRC-09).'),
  ('smart_mixing', false, 'Beat-matched and harmonic mixing modes.');
