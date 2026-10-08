import { z } from 'zod';
import type { Ctx } from './context.js';
import { ARTIST_RANGES, DAY, startOfUtcDay } from './stats.js';
import { PUBLIC_COLUMNS, publicView } from './track_views.js';
import { signStreamToken, verifyStreamToken } from './security.js';

const idParam = z.object({ id: z.uuid() });
const limitQuery = z.object({ limit: z.coerce.number().int().min(1).max(50).default(30) });
const searchQuery = z.object({ q: z.string().trim().min(1).max(80), limit: z.coerce.number().int().min(1).max(50).default(30) });
const chartQuery = z.object({
  range: z.enum(['7d', '28d']).default('7d'),
  country: z.string().length(2).optional(),
  limit: z.coerce.number().int().min(1).max(50).default(30),
});

const STREAM_MINUTES = 60;

/** Reads "bytes=a-b", "bytes=a-" or "bytes=-n". */
export function parseRange(header: string | undefined, size: number): { start: number; end: number } | 'invalid' | null {
  if (!header) return null;
  const m = header.match(/^bytes=(\d*)-(\d*)$/);
  if (!m) return 'invalid';
  const [, a, b] = m as unknown as [string, string, string];
  if (a === '' && b === '') return 'invalid';
  let start: number;
  let end: number;
  if (a === '') {
    const suffix = Number(b);
    if (suffix === 0) return 'invalid';
    start = Math.max(0, size - suffix);
    end = size - 1;
  } else {
    start = Number(a);
    end = b === '' ? size - 1 : Math.min(Number(b), size - 1);
  }
  if (start >= size || start > end) return 'invalid';
  return { start, end };
}

export function registerCatalogRoutes(ctx: Ctx) {
  const { app, db, now, secret, storage, invalid } = ctx;
  const optional = { preHandler: ctx.optionalUser };

  /** Explicit songs are hidden from guests and from anyone who turned them off. */
  async function explicitAllowed(userId: string | null): Promise<boolean> {
    if (!userId) return false;
    return (await db.query<{ explicit_allowed: boolean }>('select explicit_allowed from users where id = $1', [userId])).rows[0]?.explicit_allowed ?? false;
  }

  app.get('/v1/catalog/new', optional, async (req, reply) => {
    const q = limitQuery.safeParse(req.query);
    if (!q.success) return invalid(reply, q.error);
    const rows = (
      await db.query<any>(
        `select ${PUBLIC_COLUMNS} from tracks t join artist_profiles ap on ap.user_id = t.artist_id
         where t.status = 'published' and ($1::boolean or not t.explicit) order by t.published_at desc limit $2`,
        [await explicitAllowed(req.userId), q.data.limit],
      )
    ).rows;
    return { tracks: rows.map(publicView) };
  });

  app.get('/v1/catalog/search', optional, async (req, reply) => {
    const q = searchQuery.safeParse(req.query);
    if (!q.success) return invalid(reply, q.error);
    const escaped = q.data.q.replace(/[\\%_]/g, (c) => `\\${c}`);
    const rows = (
      await db.query<any>(
        `select ${PUBLIC_COLUMNS} from tracks t join artist_profiles ap on ap.user_id = t.artist_id
         where t.status = 'published' and ($1::boolean or not t.explicit)
           and (t.title ilike $2 escape '\\' or ap.stage_name ilike $2 escape '\\')
         order by (t.title ilike $3 escape '\\') desc, (ap.stage_name ilike $3 escape '\\') desc, t.published_at desc limit $4`,
        [await explicitAllowed(req.userId), `%${escaped}%`, `${escaped}%`, q.data.limit],
      )
    ).rows;
    return { tracks: rows.map(publicView) };
  });

  // Most played songs in the last 7 or 28 days, worldwide or for one country.
  app.get('/v1/catalog/charts', optional, async (req, reply) => {
    const q = chartQuery.safeParse(req.query);
    if (!q.success) return invalid(reply, q.error);
    const days = ARTIST_RANGES[q.data.range];
    const end = new Date(startOfUtcDay(now()).getTime() + DAY);
    const start = new Date(end.getTime() - days * DAY);
    const rows = (
      await db.query<any>(
        `select ${PUBLIC_COLUMNS}, count(e.id)::int as plays
         from tracks t join artist_profiles ap on ap.user_id = t.artist_id
         left join listen_events e on e.track_id = t.id and e.valid and e.started_at >= $2::timestamptz and e.started_at < $3::timestamptz
              and ($4::text is null or e.country = $4)
         where t.status = 'published' and ($1::boolean or not t.explicit)
         group by t.id, ap.user_id, ap.stage_name
         order by plays desc, t.published_at desc limit $5`,
        [await explicitAllowed(req.userId), start.toISOString(), end.toISOString(), q.data.country?.toUpperCase() ?? null, q.data.limit],
      )
    ).rows;
    return { range: q.data.range, tracks: rows.map((r, i) => ({ rank: i + 1, plays: r.plays as number, ...publicView(r) })) };
  });

  async function visibleTrack(id: string, userId: string | null) {
    const r = (await db.query<any>(`select ${PUBLIC_COLUMNS}, t.status, t.artist_id as owner_id from tracks t join artist_profiles ap on ap.user_id = t.artist_id where t.id = $1`, [id])).rows[0];
    if (!r || r.status === 'removed') return null;
    if (r.status !== 'published' && r.owner_id !== userId) return null; // drafts are only visible to their artist
    return r;
  }

  app.get('/v1/tracks/:id', optional, async (req, reply) => {
    const p = idParam.safeParse(req.params);
    if (!p.success) return invalid(reply, p.error);
    const r = await visibleTrack(p.data.id, req.userId);
    return r ? publicView(r) : reply.code(404).send({ error: 'not_found' });
  });

  app.get('/v1/tracks/:id/cover', optional, async (req, reply) => {
    const p = idParam.safeParse(req.params);
    if (!p.success) return invalid(reply, p.error);
    const r = await visibleTrack(p.data.id, req.userId);
    const file = r ? (await db.query<{ cover_key: string | null; cover_mime: string | null }>('select cover_key, cover_mime from tracks where id = $1', [p.data.id])).rows[0] : null;
    if (!r || !file?.cover_key || !file.cover_mime) return reply.code(404).send({ error: 'not_found' });
    const { stream, size } = await storage.open(file.cover_key);
    return reply
      .header('content-type', file.cover_mime)
      .header('content-length', size)
      .header('cache-control', r.status === 'published' ? 'public, max-age=3600' : 'private, no-store')
      .send(stream);
  });

  // A short-lived address for a song's audio. Guests can listen, so no login is needed.
  app.get('/v1/tracks/:id/stream-url', { ...optional, config: { rateLimit: { max: 120, timeWindow: '1 minute' } } }, async (req, reply) => {
    const p = idParam.safeParse(req.params);
    if (!p.success) return invalid(reply, p.error);
    const r = await visibleTrack(p.data.id, req.userId);
    const playable = r ? (await db.query<{ ok: boolean }>('select (audio_key is not null) as ok from tracks where id = $1', [p.data.id])).rows[0]?.ok : false;
    if (!r || !playable) return reply.code(404).send({ error: 'not_found' });
    if (r.explicit && r.status === 'published' && !(await explicitAllowed(req.userId))) return reply.code(403).send({ error: 'explicit_not_allowed' });
    const exp = Math.floor(now().getTime() / 1000) + STREAM_MINUTES * 60;
    return { url: `/v1/stream/${signStreamToken(secret, p.data.id, exp)}`, expiresAt: new Date(exp * 1000).toISOString() };
  });

  // The audio itself, with byte ranges so players can seek and start quickly.
  app.get('/v1/stream/:token', async (req, reply) => {
    const token = (req.params as { token: string }).token;
    const ok = verifyStreamToken(secret, token, Math.floor(now().getTime() / 1000));
    if (!ok) return reply.code(403).send({ error: 'invalid_or_expired' });
    const row = (
      await db.query<any>('select status, audio_key, audio_mime, stream_key, stream_mime from tracks where id = $1', [ok.trackId])
    ).rows[0];
    const key = row?.stream_key ?? row?.audio_key;
    const mime = row?.stream_key ? row.stream_mime : row?.audio_mime;
    if (!row || row.status === 'removed' || !key) return reply.code(404).send({ error: 'not_found' });
    const size = await storage.size(key);
    if (size === null) return reply.code(404).send({ error: 'not_found' });

    const range = parseRange(req.headers.range, size);
    if (range === 'invalid') return reply.code(416).header('content-range', `bytes */${size}`).send();
    reply.header('content-type', mime ?? 'application/octet-stream').header('accept-ranges', 'bytes').header('cache-control', 'private, max-age=300');
    if (!range) {
      const { stream } = await storage.open(key);
      return reply.header('content-length', size).send(stream);
    }
    const { stream } = await storage.open(key, range);
    return reply
      .code(206)
      .header('content-range', `bytes ${range.start}-${range.end}/${size}`)
      .header('content-length', range.end - range.start + 1)
      .send(stream);
  });
}
