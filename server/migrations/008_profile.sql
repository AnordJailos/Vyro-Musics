-- A profile photo, and a choice about sharing the listener's country with artists.
alter table users add column photo_key text;
alter table users add column photo_mime text;
alter table users add column photo_updated_at timestamptz;
alter table users add column share_country boolean not null default true;
