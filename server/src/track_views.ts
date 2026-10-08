/** The columns and JSON shapes used whenever a song is shown. */
export const OWNER_COLUMNS = `t.id, t.title, t.genre, t.duration_ms, t.explicit, t.status, t.allow_mixing, t.allow_download,
  (t.audio_key is not null) as has_audio, (t.cover_key is not null) as has_cover, t.codec, t.bitrate_kbps, t.sample_rate,
  t.lossless, t.loudness_lufs, t.published_at, t.created_at`;

export const ownerView = (r: any) => ({
  id: r.id as string,
  title: r.title as string,
  genre: r.genre as string,
  durationMs: r.duration_ms as number,
  explicit: r.explicit as boolean,
  status: r.status as string,
  allowMixing: r.allow_mixing as boolean,
  allowDownload: r.allow_download as boolean,
  hasAudio: r.has_audio as boolean,
  hasCover: r.has_cover as boolean,
  codec: (r.codec as string | null) ?? null,
  bitrateKbps: (r.bitrate_kbps as number | null) ?? null,
  sampleRate: (r.sample_rate as number | null) ?? null,
  lossless: r.lossless as boolean,
  loudnessLufs: r.loudness_lufs === null || r.loudness_lufs === undefined ? null : Math.round(Number(r.loudness_lufs) * 10) / 10,
  publishedAt: r.published_at ?? null,
  createdAt: r.created_at,
});

export const PUBLIC_COLUMNS = `t.id, t.title, t.genre, t.duration_ms, t.explicit, t.allow_mixing, t.loudness_lufs,
  (t.cover_key is not null) as has_cover, t.published_at, ap.user_id as artist_id, ap.stage_name`;

export const publicView = (r: any) => ({
  id: r.id as string,
  title: r.title as string,
  artist: { id: r.artist_id as string, stageName: r.stage_name as string },
  genre: r.genre as string,
  durationMs: r.duration_ms as number,
  explicit: r.explicit as boolean,
  allowMixing: r.allow_mixing as boolean,
  loudnessLufs: r.loudness_lufs === null || r.loudness_lufs === undefined ? null : Math.round(Number(r.loudness_lufs) * 10) / 10,
  coverUrl: r.has_cover ? `/v1/tracks/${r.id}/cover` : null,
  publishedAt: r.published_at,
});
