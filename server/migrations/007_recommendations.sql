-- "Not interested" choices, and lists curated by staff.
create table rec_dislikes (
  user_id uuid not null references users(id) on delete cascade,
  kind text not null check (kind in ('track', 'artist')),
  target_id uuid not null,
  created_at timestamptz not null,
  primary key (user_id, kind, target_id)
);

create table editorial_lists (
  id uuid primary key,
  title text not null,
  description text not null default '',
  position integer not null default 0,
  published boolean not null default false,
  created_at timestamptz not null,
  updated_at timestamptz not null
);

create table editorial_items (
  list_id uuid not null references editorial_lists(id) on delete cascade,
  track_id uuid not null references tracks(id) on delete cascade,
  position integer not null,
  primary key (list_id, track_id)
);
