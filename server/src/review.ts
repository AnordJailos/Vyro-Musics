import type { Ctx } from './context.js';
import { findMatches } from './fingerprint.js';
import type { CopyrightMatch } from './copyright.js';

/** Who can publish without a person looking first. */
export type ReviewPolicy = 'all' | 'new_artists' | 'none';

export interface ChecksResult {
  fingerprinted: boolean;
  duplicates: { trackId: string; title: string; artistId: string; artistName: string; status: string; similarity: number; sameArtist: boolean }[];
  external: { status: 'off' | 'unchecked' | 'clean' | 'matches'; matches: CopyrightMatch[] };
}

export const TRUSTED_AFTER_APPROVED = 3;

/** Compares an uploaded song with the rest of the catalog and, when configured, with a database of released music. */
export async function runChecks(ctx: Ctx, track: { id: string; artist_id: string; audio_key: string; duration_ms: number }): Promise<ChecksResult> {
  const result: ChecksResult = { fingerprinted: false, duplicates: [], external: { status: 'off', matches: [] } };
  const stored = (await ctx.db.query<{ raw: number[] }>('select raw from track_fingerprints where track_id = $1', [track.id])).rows[0];
  if (!ctx.fingerprint || !stored) return result;
  result.fingerprinted = true;

  for (const m of await findMatches(ctx.db, stored.raw, track.id)) {
    const info = (
      await ctx.db.query<any>(
        `select t.title, t.status, ap.user_id as artist_id, ap.stage_name
         from tracks t join artist_profiles ap on ap.user_id = t.artist_id
         where t.id = $1 and t.status in ('published', 'in_review', 'taken_down')`,
        [m.trackId],
      )
    ).rows[0];
    if (!info) continue;
    result.duplicates.push({
      trackId: m.trackId,
      title: info.title,
      artistId: info.artist_id,
      artistName: info.stage_name,
      status: info.status,
      similarity: m.similarity,
      sameArtist: info.artist_id === track.artist_id,
    });
  }

  if (ctx.copyright) {
    const fp = await ctx.storage.withLocalFile(track.audio_key, (p) => ctx.fingerprint!.compressed(p, track.duration_ms / 1000).catch(() => null));
    const found = fp ? await ctx.copyright.check({ compressed: fp.fingerprint, durationSec: fp.durationSec }) : null;
    result.external = found === null ? { status: 'unchecked', matches: [] } : { status: found.length > 0 ? 'matches' : 'clean', matches: found };
  }
  return result;
}

/** What should happen to a song someone asks to release. */
export async function decideStatus(ctx: Ctx, artistId: string, checks: ChecksResult): Promise<'published' | 'in_review' | 'held'> {
  // Another artist's recording, or a match with released music: a person must look at it.
  if (checks.duplicates.some((d) => !d.sameArtist) || checks.external.status === 'matches') return 'held';
  // Audio nobody could check never goes live by itself.
  if (!checks.fingerprinted || checks.external.status === 'unchecked') return 'in_review';
  if (ctx.reviewPolicy === 'none') return 'published';
  if (ctx.reviewPolicy === 'new_artists') {
    const row = (
      await ctx.db.query<{ verified: boolean; approved: number }>(
        `select ap.verified, (select count(*)::int from tracks t where t.artist_id = ap.user_id and t.reviewed_by is not null and t.status in ('published', 'ready')) as approved
         from artist_profiles ap where ap.user_id = $1`,
        [artistId],
      )
    ).rows[0];
    if (row && (row.verified || row.approved >= TRUSTED_AFTER_APPROVED)) return 'published';
  }
  return 'in_review';
}
