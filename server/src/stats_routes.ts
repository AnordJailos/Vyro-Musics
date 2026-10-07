import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';
import type { Db } from './db.js';
import { ARTIST_RANGES, LISTENER_RANGES, artistStats, listenerStats, publicArtist, trackRetention } from './stats.js';

type Guard = (req: FastifyRequest, reply: FastifyReply) => Promise<unknown>;

interface Deps {
  app: FastifyInstance;
  db: Db;
  requireUser: Guard;
  now: () => Date;
  /** Smallest group of listeners a breakdown may show (privacy). */
  minCohort: number;
}

const SOURCES = ['search', 'recommendation', 'playlist', 'chart', 'share', 'library', 'direct'] as const;
const PLATFORMS = ['android', 'ios', 'windows', 'macos', 'linux', 'web'] as const;

const listenEvent = z.object({
  id: z.uuid(),
  trackId: z.uuid(),
  startedAt: z.iso.datetime({ offset: true }),
  listenedMs: z.number().int().min(0).max(21_600_000),
  source: z.enum(SOURCES),
  platform: z.enum(PLATFORMS),
  mode: z.enum(['normal', 'mixing']),
  mixedWithTrackId: z.uuid().optional(),
});
const listensBody = z.object({ events: z.array(listenEvent).min(1).max(100) });
const trackBody = z.object({
  title: z.string().trim().min(1).max(120),
  genre: z.string().trim().toLowerCase().min(1).max(40).default('other'),
  durationMs: z.number().int().min(1000).max(21_600_000),
});
const idParam = z.object({ id: z.uuid() });
const artistRangeQuery = z.object({ range: z.enum(Object.keys(ARTIST_RANGES) as [string, ...string[]]).default('28d') });
const listenerQuery = z.object({
  range: z.enum(LISTENER_RANGES).default('4w'),
  tzOffsetMinutes: z.coerce.number().int().min(-720).max(840).default(0),
});

export function registerStatsRoutes({ app, db, requireUser, now, minCohort }: Deps) {
  const invalid = (reply: FastifyReply, error: z.ZodError) =>
    reply.code(400).send({ error: 'invalid_request', details: error.issues.map((i) => ({ path: i.path.join('.'), message: i.message })) });

  const requireArtist: Guard = async (req, reply) => {
    const ok = (await db.query('select 1 from artist_profiles where user_id = $1', [req.userId])).rows.length > 0;
    if (!ok) return reply.code(403).send({ error: 'artist_only' });
  };
  const artistOnly = { preHandler: [requireUser, requireArtist] };
  const userOnly = { preHandler: requireUser };

  // ---- plays ------------------------------------------------------------

  // Batch ingest. Safe to retry: the client-generated id makes every event idempotent.
  app.post('/v1/events/listens', userOnly, async (req, reply) => {
    const parsed = listensBody.safeParse(req.body);
    if (!parsed.success) return invalid(reply, parsed.error);
    const country = (await db.query<{ country: string | null }>('select country from users where id = $1', [req.userId])).rows[0]?.country ?? null;
    const latest = now().getTime() + 5 * 60_000;
    let accepted = 0;
    for (const ev of parsed.data.events) {
      if (Date.parse(ev.startedAt) > latest) continue;
      const res = await db.query(
        `insert into listen_events (id, user_id, track_id, artist_id, started_at, listened_ms, valid, source, platform, mode, mixed_with_track_id, country)
         select $1::uuid, $2::uuid, t.id, t.artist_id, $3::timestamptz,
                least($4::int, t.duration_ms),
                least($4::int, t.duration_ms) >= least(30000, t.duration_ms / 2),
                $5::text, $6::text, $7::text, (select id from tracks where id = $8::uuid), $9::text
         from tracks t where t.id = $10::uuid
         on conflict (id) do nothing returning id`,
        [ev.id, req.userId, ev.startedAt, ev.listenedMs, ev.source, ev.platform, ev.mode, ev.mixedWithTrackId ?? null, country, ev.trackId],
      );
      accepted += res.rows.length;
    }
    return reply.code(202).send({ accepted, ignored: parsed.data.events.length - accepted });
  });

  // ---- artist: catalog records and statistics -----------------------------

  app.post('/v1/artists/me/tracks', artistOnly, async (req, reply) => {
    const parsed = trackBody.safeParse(req.body);
    if (!parsed.success) return invalid(reply, parsed.error);
    const b = parsed.data;
    const row = (
      await db.query<any>('insert into tracks (artist_id, title, genre, duration_ms) values ($1, $2, $3, $4) returning id, title, genre, duration_ms', [
        req.userId,
        b.title,
        b.genre,
        b.durationMs,
      ])
    ).rows[0];
    return reply.code(201).send({ id: row.id, title: row.title, genre: row.genre, durationMs: row.duration_ms });
  });

  app.get('/v1/artists/me/tracks', artistOnly, async (req) => {
    const rows = (await db.query<any>('select id, title, genre, duration_ms from tracks where artist_id = $1 order by created_at', [req.userId])).rows;
    return { tracks: rows.map((r) => ({ id: r.id, title: r.title, genre: r.genre, durationMs: r.duration_ms })) };
  });

  app.get('/v1/artists/me/stats', artistOnly, async (req, reply) => {
    const q = artistRangeQuery.safeParse(req.query);
    if (!q.success) return invalid(reply, q.error);
    return artistStats(db, req.userId!, q.data.range as keyof typeof ARTIST_RANGES, now(), minCohort);
  });

  app.get('/v1/artists/me/tracks/:id/retention', artistOnly, async (req, reply) => {
    const p = idParam.safeParse(req.params);
    const q = artistRangeQuery.safeParse(req.query);
    if (!p.success) return invalid(reply, p.error);
    if (!q.success) return invalid(reply, q.error);
    const owns = (await db.query('select 1 from tracks where id = $1 and artist_id = $2', [p.data.id, req.userId])).rows.length > 0;
    if (!owns) return reply.code(404).send({ error: 'not_found' });
    return trackRetention(db, p.data.id, q.data.range as keyof typeof ARTIST_RANGES, now());
  });

  // Public artist profile numbers (monthly listeners, followers, top tracks): no login needed.
  app.get('/v1/artists/:id/public', async (req, reply) => {
    const p = idParam.safeParse(req.params);
    if (!p.success) return invalid(reply, p.error);
    const profile = await publicArtist(db, p.data.id, now());
    return profile ?? reply.code(404).send({ error: 'not_found' });
  });

  // ---- follow and save ----------------------------------------------------

  app.post('/v1/artists/:id/follow', userOnly, async (req, reply) => {
    const p = idParam.safeParse(req.params);
    if (!p.success) return invalid(reply, p.error);
    if (p.data.id === req.userId) return reply.code(400).send({ error: 'cannot_follow_yourself' });
    const exists = (await db.query('select 1 from artist_profiles where user_id = $1', [p.data.id])).rows.length > 0;
    if (!exists) return reply.code(404).send({ error: 'not_found' });
    await db.query('insert into follows (user_id, artist_id) values ($1, $2) on conflict do nothing', [req.userId, p.data.id]);
    return reply.code(204).send();
  });

  app.delete('/v1/artists/:id/follow', userOnly, async (req, reply) => {
    const p = idParam.safeParse(req.params);
    if (!p.success) return invalid(reply, p.error);
    await db.query('delete from follows where user_id = $1 and artist_id = $2', [req.userId, p.data.id]);
    return reply.code(204).send();
  });

  app.post('/v1/tracks/:id/save', userOnly, async (req, reply) => {
    const p = idParam.safeParse(req.params);
    if (!p.success) return invalid(reply, p.error);
    const exists = (await db.query('select 1 from tracks where id = $1', [p.data.id])).rows.length > 0;
    if (!exists) return reply.code(404).send({ error: 'not_found' });
    await db.query('insert into saves (user_id, track_id) values ($1, $2) on conflict do nothing', [req.userId, p.data.id]);
    return reply.code(204).send();
  });

  app.delete('/v1/tracks/:id/save', userOnly, async (req, reply) => {
    const p = idParam.safeParse(req.params);
    if (!p.success) return invalid(reply, p.error);
    await db.query('delete from saves where user_id = $1 and track_id = $2', [req.userId, p.data.id]);
    return reply.code(204).send();
  });

  // ---- listener profile statistics ---------------------------------------

  app.get('/v1/me/stats', userOnly, async (req, reply) => {
    const q = listenerQuery.safeParse(req.query);
    if (!q.success) return invalid(reply, q.error);
    return listenerStats(db, req.userId!, q.data.range, now(), q.data.tzOffsetMinutes);
  });
}
