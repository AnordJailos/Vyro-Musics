-- Accounts: phone and social sign-in, email checks, age rules, privacy, taste.
alter table users alter column email drop not null;
alter table users alter column password_hash drop not null;
alter table users add column email_verified_at timestamptz;
alter table users add column phone text unique;
alter table users add column phone_verified_at timestamptz;
alter table users add column language text not null default 'en';
alter table users add column birth_date date;
alter table users add column explicit_allowed boolean not null default true;
alter table users add column parent_consent text not null default 'not_needed'
  check (parent_consent in ('not_needed', 'pending', 'granted'));
alter table users add column parent_email text;
alter table users add column private_session boolean not null default false;
alter table users add column hide_activity boolean not null default false;
alter table users add column share_listening boolean not null default true;
alter table users add column personalization boolean not null default true;
alter table users add constraint users_has_contact check (email is not null or phone is not null);

create table identities (
  provider text not null check (provider in ('google', 'apple')),
  subject text not null,
  user_id uuid not null references users(id) on delete cascade,
  email text,
  created_at timestamptz not null default now(),
  primary key (provider, subject)
);

-- One-time codes: email checks, phone sign-in, password reset, parent consent.
create table verification_codes (
  id uuid primary key default gen_random_uuid(),
  purpose text not null check (purpose in ('email_verify', 'phone_login', 'password_reset', 'parent_consent')),
  target text not null,
  code_hash text not null,
  attempts integer not null default 0,
  user_id uuid references users(id) on delete cascade,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null
);
create index verification_codes_lookup on verification_codes (purpose, target, created_at);

create table taste_profiles (
  user_id uuid primary key references users(id) on delete cascade,
  genres jsonb not null default '[]',
  moods jsonb not null default '[]',
  artist_ids jsonb not null default '[]',
  updated_at timestamptz not null default now()
);

alter table refresh_tokens add column device_name text;

-- Artist names: a normalized key blocks look-alike names (ART-08).
alter table artist_profiles add column stage_name_key text;
update artist_profiles set stage_name_key = lower(stage_name);
alter table artist_profiles alter column stage_name_key set not null;
create unique index artist_stage_name_key on artist_profiles (stage_name_key);
alter table artist_profiles add column genres jsonb not null default '[]';
alter table artist_profiles add column links jsonb not null default '[]';
