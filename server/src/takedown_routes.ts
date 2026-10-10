import { z } from 'zod';
import type { Ctx } from './context.js';
import { audit, notifyUser } from './notify.js';

const noticeBody = z.object({
  trackId: z.uuid(),
  claimantName: z.string().trim().min(2).max(120),
  claimantEmail: z.email().max(254),
  claimantCompany: z.string().trim().max(120).optional(),
  statement: z.string().trim().min(30).max(2000),
  signature: z.string().trim().min(2).max(120),
  goodFaith: z.literal(true),
  accurateUnderPenalty: z.literal(true),
});
const counterBody = z.object({
  statement: z.string().trim().min(30).max(2000),
  signature: z.string().trim().min(2).max(120),
  consent: z.literal(true),
});
const idParam = z.object({ id: z.uuid() });

/**
 * Copyright notices from rights holders, and counter-notices from artists. The steps follow the usual
 * notice-and-takedown shape, but the legal wording, time limits and agent details must be settled with a lawyer
 * for each country (requirement SAF-02).
 */
export function registerTakedownRoutes(ctx: Ctx) {
  const { app, db, now, messenger, invalid, requireUser } = ctx;

  // Anyone can send a notice. The song goes offline at once; a person decides later.
  app.post('/v1/takedown-notices', { config: { rateLimit: { max: ctx.noticeRateLimit, timeWindow: '1 hour' } } }, async (req, reply) => {
    const b = noticeBody.safeParse(req.body);
    if (!b.success) return invalid(reply, b.error);
    const t = (
      await db.query<any>(
        `select t.id, t.title, t.status, t.artist_id from tracks t
         where t.id = $1 and t.status in ('ready', 'in_review', 'published', 'held', 'rejected')`,
        [b.data.trackId],
      )
    ).rows[0];
    if (!t) return reply.code(404).send({ error: 'not_found' }); // unknown, private or already removed: say nothing more
    const stamp = now().toISOString();
    const notice = (
      await db.query<{ id: string }>(
        `insert into takedown_notices (track_id, claimant_name, claimant_email, claimant_company, statement, signature, previous_status, created_at)
         values ($1, $2, $3, $4, $5, $6, $7, $8::timestamptz) returning id`,
        [t.id, b.data.claimantName, b.data.claimantEmail.toLowerCase(), b.data.claimantCompany ?? null, b.data.statement, b.data.signature, t.status, stamp],
      )
    ).rows[0]!;
    await db.query("update tracks set status = 'taken_down' where id = $1", [t.id]);
    await audit(db, now(), null, 'takedown.received', 'takedown', notice.id, { trackId: t.id, previous: t.status });
    await notifyUser(
      db,
      messenger,
      t.artist_id,
      'A copyright notice about your song',
      `We received a copyright notice from ${b.data.claimantName} about "${t.title}" and removed it while we look into it. If you believe this is a mistake, open the Studio and send a counter-notice.`,
    );
    await messenger.email(b.data.claimantEmail, 'We received your copyright notice', `We received your notice about "${t.title}" and removed the song while it is reviewed.`).catch(() => undefined);
    return reply.code(202).send({ noticeId: notice.id });
  });

  const artistOnly = {
    preHandler: [
      requireUser,
      async (req: any, reply: any) => {
        const ok = (await db.query('select 1 from artist_profiles where user_id = $1', [req.userId])).rows.length > 0;
        if (!ok) return reply.code(403).send({ error: 'artist_only' });
      },
    ],
  };

  app.get('/v1/artists/me/takedowns', artistOnly, async (req) => {
    const rows = (
      await db.query<any>(
        `select n.id, n.status, n.claimant_name, n.statement, n.created_at, n.counter_at, t.id as track_id, t.title
         from takedown_notices n join tracks t on t.id = n.track_id where t.artist_id = $1 order by n.created_at desc`,
        [req.userId],
      )
    ).rows;
    return {
      notices: rows.map((n) => ({
        id: n.id,
        status: n.status,
        track: { id: n.track_id, title: n.title },
        claimantName: n.claimant_name,
        statement: n.statement,
        createdAt: n.created_at,
        counterFiledAt: n.counter_at,
      })),
    };
  });

  app.post('/v1/artists/me/takedowns/:id/counter-notice', artistOnly, async (req, reply) => {
    const p = idParam.safeParse(req.params);
    const b = counterBody.safeParse(req.body);
    if (!p.success) return invalid(reply, p.error);
    if (!b.success) return invalid(reply, b.error);
    const n = (
      await db.query<any>(
        `select n.id, n.status, n.claimant_email, t.title from takedown_notices n join tracks t on t.id = n.track_id
         where n.id = $1 and t.artist_id = $2`,
        [p.data.id, req.userId],
      )
    ).rows[0];
    if (!n) return reply.code(404).send({ error: 'not_found' });
    if (n.status !== 'open') return reply.code(409).send({ error: 'cannot_counter_now' });
    await db.query("update takedown_notices set status = 'counter_filed', counter_statement = $2, counter_signature = $3, counter_at = $4::timestamptz where id = $1", [n.id, b.data.statement, b.data.signature, now().toISOString()]);
    await audit(db, now(), req.userId!, 'takedown.counter_notice', 'takedown', n.id);
    await messenger.email(n.claimant_email, 'A counter-notice was filed', `The artist filed a counter-notice about "${n.title}". A reviewer will decide whether to restore it.`).catch(() => undefined);
    return { ok: true };
  });
}
