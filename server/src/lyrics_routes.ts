import { z } from 'zod';
import type { Ctx } from './context.js';
import { MAX_LYRICS_CHARS, parseLyrics } from './lrc.js';
import { audit, notifyUser } from './notify.js';

const idParam = z.object({ id: z.uuid() });
const lyricsBody = z.object({ text: z.string().max(MAX_LYRICS_CHARS) });
const reportBody = z.object({ reason: z.enum(['wrong_text', 'wrong_timing', 'offensive', 'copyright', 'other']).default('other') });

const REASON_TEXT: Record<string, string> = {
  wrong_text: 'the words are wrong',
  wrong_timing: 'the timing is off',
  offensive: 'they contain offensive content',
  copyright: 'they may be copied from someone else',
  other: 'something is wrong with them',
};

/** Lyrics are written by the artist, and listeners can read them while a song plays. */
export function registerLyricsRoutes(ctx: Ctx) {
  const { app, db, now, invalid, requireUser, messenger } = ctx;
  const optional = { preHandler: ctx.optionalUser };

  const requireArtist = async (req: any, reply: any) => {
    const ok = (await db.query('select 1 from artist_profiles where user_id = $1', [req.userId])).rows.length > 0;
    if (!ok) return reply.code(403).send({ error: 'artist_only' });
  };
  const artistOnly = { preHandler: [requireUser, requireArtist] };

  const ownTrack = async (id: string, artistId: string | null) =>
    (await db.query<any>("select id, title, lyrics, lyrics_synced from tracks where id = $1 and artist_id = $2 and status <> 'removed'", [id, artistId])).rows[0];

  app.put('/v1/artists/me/tracks/:id/lyrics', artistOnly, async (req, reply) => {
    const p = idParam.safeParse(req.params);
    const b = lyricsBody.safeParse(req.body);
    if (!p.success) return invalid(reply, p.error);
    if (!b.success) return invalid(reply, b.error);
    const t = await ownTrack(p.data.id, req.userId);
    if (!t) return reply.code(404).send({ error: 'not_found' });
    const parsed = parseLyrics(b.data.text);
    if (parsed.lines.every((l) => l.text === '')) return reply.code(400).send({ error: 'empty_lyrics' });
    const text = b.data.text.replace(/\r\n?/g, '\n').replace(/^\uFEFF/, '');
    await db.query('update tracks set lyrics = $2, lyrics_synced = $3, lyrics_updated_at = $4::timestamptz where id = $1', [t.id, text, parsed.synced, now().toISOString()]);
    await audit(db, now(), req.userId!, 'lyrics.set', 'track', t.id, { synced: parsed.synced, lines: parsed.lines.length });
    return { synced: parsed.synced, lineCount: parsed.lines.length };
  });

  // The artist's own text, exactly as saved, for editing.
  app.get('/v1/artists/me/tracks/:id/lyrics', artistOnly, async (req, reply) => {
    const p = idParam.safeParse(req.params);
    if (!p.success) return invalid(reply, p.error);
    const t = await ownTrack(p.data.id, req.userId);
    if (!t || t.lyrics === null) return reply.code(404).send({ error: 'not_found' });
    return { text: t.lyrics as string, synced: t.lyrics_synced as boolean };
  });

  app.delete('/v1/artists/me/tracks/:id/lyrics', artistOnly, async (req, reply) => {
    const p = idParam.safeParse(req.params);
    if (!p.success) return invalid(reply, p.error);
    const t = await ownTrack(p.data.id, req.userId);
    if (!t) return reply.code(404).send({ error: 'not_found' });
    await db.query('update tracks set lyrics = null, lyrics_synced = false, lyrics_updated_at = null where id = $1', [t.id]);
    return reply.code(204).send();
  });

  /** The lyrics of a song the person is allowed to see (live songs, or their own). */
  async function visible(id: string, userId: string | null) {
    const r = (
      await db.query<any>(
        `select t.id, t.title, t.status, t.explicit, t.lyrics, t.lyrics_synced, t.lyrics_updated_at, t.artist_id,
                exists (select 1 from users su where su.id = t.artist_id and su.suspended_at is not null) as owner_suspended
         from tracks t where t.id = $1`,
        [id],
      )
    ).rows[0];
    if (!r || r.status === 'removed' || r.lyrics === null) return null;
    if (r.status !== 'published' && r.artist_id !== userId) return null;
    if (r.status === 'published' && r.owner_suspended && r.artist_id !== userId) return null;
    return r;
  }

  app.get('/v1/tracks/:id/lyrics', optional, async (req, reply) => {
    const p = idParam.safeParse(req.params);
    if (!p.success) return invalid(reply, p.error);
    const r = await visible(p.data.id, req.userId);
    if (!r) return reply.code(404).send({ error: 'not_found' });
    if (r.explicit && r.status === 'published' && req.userId !== r.artist_id) {
      const allowed = req.userId ? (await db.query<{ explicit_allowed: boolean }>('select explicit_allowed from users where id = $1', [req.userId])).rows[0]?.explicit_allowed : false;
      if (!allowed) return reply.code(403).send({ error: 'explicit_not_allowed' });
    }
    const parsed = parseLyrics(r.lyrics);
    return { synced: parsed.synced, lines: parsed.lines, updatedAt: r.lyrics_updated_at };
  });

  // "These lyrics are wrong": one report per person per song. The artist is told so they can fix them.
  app.post('/v1/tracks/:id/lyrics/report', { preHandler: requireUser, config: { rateLimit: { max: 30, timeWindow: '1 hour' } } }, async (req, reply) => {
    const p = idParam.safeParse(req.params);
    const b = reportBody.safeParse(req.body ?? {});
    if (!p.success) return invalid(reply, p.error);
    if (!b.success) return invalid(reply, b.error);
    const r = await visible(p.data.id, req.userId);
    if (!r) return reply.code(404).send({ error: 'not_found' });
    const res = await db.query('insert into lyric_reports (track_id, user_id, reason, created_at) values ($1, $2, $3, $4::timestamptz) on conflict do nothing returning track_id', [
      r.id,
      req.userId,
      b.data.reason,
      now().toISOString(),
    ]);
    if (res.rows.length > 0) {
      await notifyUser(db, messenger, r.artist_id, 'A listener reported your lyrics', `A listener reported the lyrics of "${r.title}": ${REASON_TEXT[b.data.reason]}. You can correct them in the Studio.`);
    }
    return reply.code(204).send();
  });
}
