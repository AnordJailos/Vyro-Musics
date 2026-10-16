import { z } from 'zod';
import type { Ctx } from './context.js';
import { TooLarge, firstBytes, limited, sniffImage } from './studio_routes.js';
import { Readable } from 'node:stream';

const MAX_PHOTO_BYTES = 5 * 1024 * 1024;
const idParam = z.object({ id: z.uuid() });

/** The person's profile photo, and a copy of everything Vyro holds about them. */
export function registerProfileRoutes(ctx: Ctx) {
  const { app, db, now, requireUser, loadMe, storage } = ctx;
  const userOnly = { preHandler: requireUser };

  app.put('/v1/me/photo', userOnly, async (req, reply) => {
    if (!(req.body instanceof Readable)) return reply.code(415).send({ error: 'send_the_file_as_the_request_body' });
    const key = `photos/${req.userId}/photo-${now().getTime()}`;
    try {
      await storage.put(key, limited(req.body, MAX_PHOTO_BYTES));
    } catch (e) {
      req.body.destroy();
      if (e instanceof TooLarge) return reply.header('connection', 'close').code(413).send({ error: 'file_too_large' });
      throw e;
    }
    const mime = sniffImage(await firstBytes(ctx, key, 16));
    if (!mime) {
      await storage.delete(key);
      return reply.code(415).send({ error: 'unsupported_image' });
    }
    const old = (await db.query<{ photo_key: string | null }>('select photo_key from users where id = $1', [req.userId])).rows[0]?.photo_key;
    await db.query('update users set photo_key = $2, photo_mime = $3, photo_updated_at = $4::timestamptz where id = $1', [req.userId, key, mime, now().toISOString()]);
    if (old) await storage.delete(old);
    return loadMe(req.userId!);
  });

  app.delete('/v1/me/photo', userOnly, async (req, reply) => {
    const old = (await db.query<{ photo_key: string | null }>('select photo_key from users where id = $1', [req.userId])).rows[0]?.photo_key;
    await db.query('update users set photo_key = null, photo_mime = null, photo_updated_at = null where id = $1', [req.userId]);
    if (old) await storage.delete(old);
    return reply.code(204).send();
  });

  // A photo is private to its owner, except an artist's, which is part of their public page.
  app.get('/v1/users/:id/photo', { preHandler: ctx.optionalUser }, async (req, reply) => {
    const p = idParam.safeParse(req.params);
    if (!p.success) return reply.code(400).send({ error: 'invalid_request' });
    const row = (
      await db.query<{ photo_key: string | null; photo_mime: string | null; is_artist: boolean; suspended: boolean }>(
        `select photo_key, photo_mime, exists (select 1 from artist_profiles ap where ap.user_id = users.id) as is_artist, (suspended_at is not null) as suspended
         from users where id = $1`,
        [p.data.id],
      )
    ).rows[0];
    const isOwner = req.userId === p.data.id;
    if (!row?.photo_key || !row.photo_mime || (!isOwner && (!row.is_artist || row.suspended))) return reply.code(404).send({ error: 'not_found' });
    const { stream, size } = await storage.open(row.photo_key);
    return reply
      .header('content-type', row.photo_mime)
      .header('content-length', size)
      .header('cache-control', isOwner && !row.is_artist ? 'private, max-age=3600' : 'public, max-age=3600')
      .send(stream);
  });

  // A copy of the person's data (AUTH-10, SAF-05): their profile and settings, taste picks, follows, liked songs, "not
  // interested" choices and the plays linked to them. Plays made in a private session were never linked, so are not here.
  app.get('/v1/me/export', { preHandler: requireUser, config: { rateLimit: { max: 5, timeWindow: '1 hour' } } }, async (req, reply) => {
    const id = req.userId!;
    const q = async <T = any>(sql: string) => (await db.query<T>(sql, [id])).rows;
    const profile = await loadMe(id);
    const body = {
      exportedAt: now().toISOString(),
      profile,
      taste: (await q('select genres, moods, artist_ids as "artistIds" from taste_profiles where user_id = $1'))[0] ?? null,
      follows: await q('select ap.user_id as "artistId", ap.stage_name as "stageName", f.created_at as "followedAt" from follows f join artist_profiles ap on ap.user_id = f.artist_id where f.user_id = $1 order by f.created_at desc'),
      likedSongs: await q('select t.id as "songId", t.title, ap.stage_name as artist, s.created_at as "likedAt" from saves s join tracks t on t.id = s.track_id join artist_profiles ap on ap.user_id = t.artist_id where s.user_id = $1 order by s.created_at desc'),
      notInterested: await q('select kind, target_id as "targetId", created_at as "at" from rec_dislikes where user_id = $1 order by created_at desc'),
      plays: await q(
        `select e.started_at as "startedAt", t.title, ap.stage_name as artist, e.listened_ms as "listenedMs", e.source, e.platform, e.mode
         from listen_events e join tracks t on t.id = e.track_id join artist_profiles ap on ap.user_id = e.artist_id
         where e.user_id = $1 order by e.started_at desc limit 50000`,
      ),
      artistSongs: profile?.artist
        ? await q('select id, title, genre, status, created_at as "createdAt" from tracks where artist_id = $1 order by created_at desc')
        : [],
    };
    return reply.header('content-disposition', 'attachment; filename="vyro-my-data.json"').send(body);
  });
}
