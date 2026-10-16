import { z } from 'zod';
import { LIVE } from './catalog_routes.js';
import type { Ctx } from './context.js';
import { matchScore, normalize } from './fuzzy.js';
import { PUBLIC_COLUMNS, publicView } from './track_views.js';

const DAY = 86_400_000;
const FUZZY_POOL = 3000;

const searchQuery = z.object({ q: z.string().trim().min(1).max(100), limit: z.coerce.number().int().min(1).max(50).default(20) });
const suggestQuery = z.object({ q: z.string().trim().min(1).max(100) });
const idParam = z.object({ id: z.uuid() });
const genreParam = z.object({ genre: z.string().trim().min(1).max(60) });
const browseQuery = z.object({ sort: z.enum(['new', 'popular']).default('new'), limit: z.coerce.number().int().min(1).max(100).default(50) });
const artistChartQuery = z.object({
  kind: z.enum(['top', 'rising']).default('top'),
  country: z.string().trim().length(2).optional(),
  limit: z.coerce.number().int().min(1).max(50).default(20),
});

// An artist is listed publicly when they are not suspended and have at least one live song.
const LIVE_ARTIST = `not exists (select 1 from users su where su.id = ap.user_id and su.suspended_at is not null)
  and exists (select 1 from tracks t where t.artist_id = ap.user_id and ${LIVE})`;

/** Finding things: search that forgives typos, suggestions as you type, browsing by genre, artist pages and artist charts. */
export function registerDiscoveryRoutes(ctx: Ctx) {
  const { app, db, now, invalid } = ctx;
  const optional = { preHandler: ctx.optionalUser };

  async function explicitAllowed(userId: string | null): Promise<boolean> {
    if (!userId) return false;
    return (await db.query<{ explicit_allowed: boolean }>('select explicit_allowed from users where id = $1', [userId])).rows[0]?.explicit_allowed ?? false;
  }

  const likeEscape = (s: string) => s.replace(/[\\%_]/g, (c) => `\\${c}`);

  /** Live songs and artists a person may see, as light rows to compare against what was typed. */
  async function pool(explicit: boolean) {
    const tracks = (
      await db.query<{ id: string; title: string; stage_name: string }>(
        `select t.id, t.title, ap.stage_name from tracks t join artist_profiles ap on ap.user_id = t.artist_id
         where ${LIVE} and ($1::boolean or not t.explicit) order by t.published_at desc limit ${FUZZY_POOL}`,
        [explicit],
      )
    ).rows;
    const artists = (await db.query<{ id: string; stage_name: string }>(`select ap.user_id as id, ap.stage_name from artist_profiles ap where ${LIVE_ARTIST} limit 1500`)).rows;
    return { tracks, artists };
  }

  async function artistSummaries(ids: string[]) {
    if (ids.length === 0) return [];
    const rows = (
      await db.query<any>(
        `select ap.user_id as id, ap.stage_name, ap.verified, (select count(*)::int from follows f where f.artist_id = ap.user_id) as followers
         from artist_profiles ap where ap.user_id in (select jsonb_array_elements_text($1::jsonb)::uuid)`,
        [JSON.stringify(ids)],
      )
    ).rows;
    const byId = new Map(rows.map((r) => [r.id as string, r]));
    return ids.flatMap((id) => {
      const r = byId.get(id);
      return r ? [{ id, stageName: r.stage_name as string, verified: r.verified as boolean, followers: r.followers as number }] : [];
    });
  }

  async function trackRows(ids: string[], explicit: boolean) {
    if (ids.length === 0) return [];
    const rows = (
      await db.query<any>(
        `select ${PUBLIC_COLUMNS} from tracks t join artist_profiles ap on ap.user_id = t.artist_id
         where t.id in (select jsonb_array_elements_text($2::jsonb)::uuid) and ${LIVE} and ($1::boolean or not t.explicit)`,
        [explicit, JSON.stringify(ids)],
      )
    ).rows;
    const byId = new Map(rows.map((r) => [r.id as string, r]));
    return ids.flatMap((id) => (byId.has(id) ? [publicView(byId.get(id))] : []));
  }

  // ---- search ---------------------------------------------------------------

  app.get('/v1/search', optional, async (req, reply) => {
    const q = searchQuery.safeParse(req.query);
    if (!q.success) return invalid(reply, q.error);
    const explicit = await explicitAllowed(req.userId);
    const { tracks, artists } = await pool(explicit);
    // Songs: their title counts fully, and the artist's name a little less. Artists: their name.
    const songHits = tracks
      .map((t) => ({ id: t.id, score: Math.max(matchScore(q.data.q, t.title), Math.round(matchScore(q.data.q, t.stage_name) * 0.8)) }))
      .filter((x) => x.score > 0)
      .sort((a, b) => b.score - a.score)
      .slice(0, q.data.limit);
    const artistHits = artists
      .map((a) => ({ id: a.id, score: matchScore(q.data.q, a.stage_name) }))
      .filter((x) => x.score > 0)
      .sort((a, b) => b.score - a.score)
      .slice(0, 10);
    return {
      artists: await artistSummaries(artistHits.map((a) => a.id)),
      tracks: await trackRows(songHits.map((s) => s.id), explicit),
    };
  });

  // What to offer while someone is still typing: artists first, then songs.
  app.get('/v1/search/suggest', optional, async (req, reply) => {
    const q = suggestQuery.safeParse(req.query);
    if (!q.success) return invalid(reply, q.error);
    const { tracks, artists } = await pool(await explicitAllowed(req.userId));
    const rank = (score: number, text: string) => score * 1000 - text.length; // shorter names first among equals
    const artistHits = artists
      .map((a) => ({ kind: 'artist' as const, id: a.id, text: a.stage_name, subtitle: 'Artist', r: rank(matchScore(q.data.q, a.stage_name), a.stage_name), score: matchScore(q.data.q, a.stage_name) }))
      .filter((x) => x.score > 0)
      .sort((a, b) => b.r - a.r)
      .slice(0, 3);
    const songHits = tracks
      .map((t) => ({ kind: 'song' as const, id: t.id, text: t.title, subtitle: t.stage_name, r: rank(matchScore(q.data.q, t.title), t.title), score: matchScore(q.data.q, t.title) }))
      .filter((x) => x.score > 0)
      .sort((a, b) => b.r - a.r)
      .slice(0, 5);
    return { suggestions: [...artistHits, ...songHits].map(({ kind, id, text, subtitle }) => ({ kind, id, text, subtitle })) };
  });

  // ---- browse by genre ----------------------------------------------------------

  app.get('/v1/browse/genres', optional, async (req) => {
    const rows = (
      await db.query<{ genre: string; count: number }>(
        `select lower(t.genre) as genre, count(*)::int as count from tracks t
         where ${LIVE} and ($1::boolean or not t.explicit) group by lower(t.genre)
         order by (lower(t.genre) = 'other'), count(*) desc, lower(t.genre)`,
        [await explicitAllowed(req.userId)],
      )
    ).rows;
    return { genres: rows };
  });

  app.get('/v1/browse/genres/:genre', optional, async (req, reply) => {
    const p = genreParam.safeParse(req.params);
    const q = browseQuery.safeParse(req.query);
    if (!p.success) return invalid(reply, p.error);
    if (!q.success) return invalid(reply, q.error);
    const since = new Date(now().getTime() - 28 * DAY).toISOString();
    const rows = (
      await db.query<any>(
        `select ${PUBLIC_COLUMNS},
           (select count(*)::int from listen_events e where e.track_id = t.id and e.valid and e.started_at >= $3::timestamptz) as plays
         from tracks t join artist_profiles ap on ap.user_id = t.artist_id
         where ${LIVE} and ($1::boolean or not t.explicit) and lower(t.genre) = lower($2)
         order by ${q.data.sort === 'popular' ? 'plays desc,' : ''} t.published_at desc limit $4`,
        [await explicitAllowed(req.userId), p.data.genre, since, q.data.limit],
      )
    ).rows;
    return { genre: p.data.genre.toLowerCase(), sort: q.data.sort, tracks: rows.map(publicView) };
  });

  // ---- artist page ----------------------------------------------------------------

  app.get('/v1/artists/:id/page', optional, async (req, reply) => {
    const p = idParam.safeParse(req.params);
    if (!p.success) return invalid(reply, p.error);
    const artist = (
      await db.query<any>(
        `select ap.user_id as id, ap.stage_name, ap.verified, ap.bio, ap.genres, ap.links from artist_profiles ap
         where ap.user_id = $1 and not exists (select 1 from users su where su.id = ap.user_id and su.suspended_at is not null)`,
        [p.data.id],
      )
    ).rows[0];
    if (!artist) return reply.code(404).send({ error: 'not_found' });
    const explicit = await explicitAllowed(req.userId);
    const since = new Date(now().getTime() - 28 * DAY).toISOString();
    const own = `from tracks t join artist_profiles ap on ap.user_id = t.artist_id where t.artist_id = $2 and ${LIVE} and ($1::boolean or not t.explicit)`;
    const top = (
      await db.query<any>(
        `select ${PUBLIC_COLUMNS}, (select count(*)::int from listen_events e where e.track_id = t.id and e.valid) as plays ${own} order by plays desc, t.published_at desc limit 5`,
        [explicit, p.data.id],
      )
    ).rows;
    const discography = (await db.query<any>(`select ${PUBLIC_COLUMNS} ${own} order by t.published_at desc limit 100`, [explicit, p.data.id])).rows;
    const followers = (await db.query<{ n: number }>('select count(*)::int as n from follows where artist_id = $1', [p.data.id])).rows[0]!.n;
    const listeners = (
      await db.query<{ n: number }>('select count(distinct user_id)::int as n from listen_events where artist_id = $1 and valid and started_at >= $2::timestamptz', [p.data.id, since])
    ).rows[0]!.n;
    const following = req.userId ? (await db.query('select 1 from follows where user_id = $1 and artist_id = $2', [req.userId, p.data.id])).rows.length > 0 : false;
    // Artists whose songs share genres with this artist's songs; the most in common first, then the most followed.
    const similar = (
      await db.query<{ id: string }>(
        `select o.user_id as id from artist_profiles o
         join tracks ot on ot.artist_id = o.user_id
         join tracks mt on mt.artist_id = $1 and lower(mt.genre) = lower(ot.genre) and lower(mt.genre) <> 'other'
         where o.user_id <> $1 and ${LIVE.replace(/\bt\./g, 'ot.')} and mt.status = 'published'
           and not exists (select 1 from users su where su.id = o.user_id and su.suspended_at is not null)
         group by o.user_id
         order by count(distinct lower(ot.genre)) desc, (select count(*) from follows f where f.artist_id = o.user_id) desc, o.stage_name
         limit 6`,
        [p.data.id],
      )
    ).rows;
    return {
      artist: { id: artist.id, stageName: artist.stage_name, verified: artist.verified, bio: artist.bio ?? '', genres: artist.genres ?? [], links: artist.links ?? [], followers, monthlyListeners: listeners },
      following,
      topTracks: top.map((r) => ({ ...publicView(r), plays: r.plays as number })),
      discography: discography.map(publicView),
      similar: await artistSummaries(similar.map((s) => s.id)),
    };
  });

  // ---- artist charts -------------------------------------------------------------

  app.get('/v1/charts/artists', async (req, reply) => {
    const q = artistChartQuery.safeParse(req.query);
    if (!q.success) return invalid(reply, q.error);
    const end = new Date(now().getTime() + DAY);
    const recentFrom = new Date(now().getTime() - (q.data.kind === 'rising' ? 7 : 28) * DAY);
    const previousFrom = new Date(recentFrom.getTime() - 7 * DAY);
    const rows = (
      await db.query<any>(
        `select ap.user_id as id, ap.stage_name, ap.verified,
           count(e.id) filter (where e.started_at >= $1::timestamptz)::int as recent,
           count(e.id) filter (where e.started_at < $1::timestamptz)::int as previous
         from artist_profiles ap
         join listen_events e on e.artist_id = ap.user_id and e.valid and e.started_at >= $2::timestamptz and e.started_at < $3::timestamptz
              and ($4::text is null or e.country = $4)
         where ${LIVE_ARTIST}
         group by ap.user_id, ap.stage_name, ap.verified`,
        [recentFrom.toISOString(), (q.data.kind === 'rising' ? previousFrom : recentFrom).toISOString(), end.toISOString(), q.data.country?.toUpperCase() ?? null],
      )
    ).rows as { id: string; stage_name: string; verified: boolean; recent: number; previous: number }[];
    const kept = q.data.kind === 'rising' ? rows.filter((r) => r.recent >= 3 && r.recent > r.previous) : rows.filter((r) => r.recent > 0);
    kept.sort((a, b) => (q.data.kind === 'rising' ? b.recent - b.previous - (a.recent - a.previous) : b.recent - a.recent) || b.recent - a.recent || a.stage_name.localeCompare(b.stage_name));
    const top = kept.slice(0, q.data.limit);
    const followers = new Map((await artistSummaries(top.map((r) => r.id))).map((a) => [a.id, a.followers]));
    return {
      kind: q.data.kind,
      artists: top.map((r, i) => ({ rank: i + 1, id: r.id, stageName: r.stage_name, verified: r.verified, followers: followers.get(r.id) ?? 0, plays: r.recent, change: q.data.kind === 'rising' ? r.recent - r.previous : null })),
    };
  });
}
