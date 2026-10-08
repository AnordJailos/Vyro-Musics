-- The Vyro catalog: songs that artists upload and listeners stream.
alter table tracks add column status text not null default 'draft'
  check (status in ('draft', 'ready', 'published', 'removed'));
alter table tracks add column explicit boolean not null default false;
alter table tracks add column allow_mixing boolean not null default true;
alter table tracks add column allow_download boolean not null default true;

-- The uploaded file is kept as the master. A smaller stream copy is made for
-- lossless uploads when ffmpeg is available; otherwise the master is streamed.
alter table tracks add column audio_key text;
alter table tracks add column audio_mime text;
alter table tracks add column audio_bytes integer;
alter table tracks add column stream_key text;
alter table tracks add column stream_mime text;
alter table tracks add column stream_bytes integer;
alter table tracks add column codec text;
alter table tracks add column bitrate_kbps integer;
alter table tracks add column sample_rate integer;
alter table tracks add column lossless boolean not null default false;
alter table tracks add column loudness_lufs real;

alter table tracks add column cover_key text;
alter table tracks add column cover_mime text;
alter table tracks add column published_at timestamptz;

create index tracks_published_at on tracks (published_at desc) where status = 'published';
