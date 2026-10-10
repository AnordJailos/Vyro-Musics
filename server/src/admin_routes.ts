import type { FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';
import type { Ctx } from './context.js';
import { audit, notifyUser } from './notify.js';
import { signStreamToken } from './security.js';

export const REJECT_REASONS = ['copyright', 'duplicate', 'low_quality', 'explicit_not_marked', 'misleading', 'other'] as const;
export type RejectReason = (typeof REJECT_REASONS)[number];

const REASON_TEXT: Record<RejectReason, string> = {
  copyright: 'it appears to use music you do not have the rights to',
  duplicate: 'it duplicates another song on Vyro',
  low_quality: 'the audio quality is too low',
  explicit_not_marked: 'it contains explicit content that was not marked explicit',
  misleading: 'the title or artist name is misleading',
  other: 'it does not meet our guidelines',
};

/** An artist whose copyright notices have been upheld this many times is suspended (repeat-infringer policy). */
export const STRIKE_LIMIT = 3;

const RANK = { user: 0, moderator: 1, admin: 2 } as const;
type Role = keyof typeof RANK;

const idParam = z.object({ id: z.uuid() });
const note = z.string().trim().max(500).optional();

export function registerAdminRoutes(ctx: Ctx) {
  const { app, db, now, invalid, requireUser, messenger } = ctx;

  const needs = (min: Role) => async (req: FastifyRequest, reply: FastifyReply) => {
    const row = (await db.query<{ role: Role }>('select role from users where id = $1', [req.userId])).rows[0];
    if (!row || RANK[row.role] < RANK[min]) return reply.code(403).send({ error: 'staff_only' });
  };
  const staff = { preHandler: [requireUser, needs('moderator')] };
  const adminOnly = { preHandler: [requireUser, needs('admin')] };

  // ---- review queue --------------------------------------------------------

  app.get('/v1/admin/review/queue', staff, async (req, reply) => {
    const q = z.object({ status: z.enum(['in_review', 'held']).default('in_review'), limit: z.coerce.number().int().min(1).max(100).default(50) }).safeParse(req.query);
    if (!q.success) return invalid(reply, q.error);
    const rows = (
      await db.query<any>(
        `select t.id, t.title, t.genre, t.duration_ms, t.explicit, t.status, t.loudness_lufs, t.bitrate_kbps, t.codec, t.lossless, t.submitted_at, t.checks,
                ap.user_id as artist_id, ap.stage_name, ap.verified,
                (select count(*)::int from copyright_strikes s where s.artist_id = ap.user_id) as strikes,
                (select count(*)::int from tracks p where p.artist_id = ap.user_id and p.status = 'published') as published_count
         from tracks t join artist_profiles ap on ap.user_id = t.artist_id
         where t.status = $1 order by t.submitted_at asc nulls last limit $2`,
        [q.data.status, q.data.limit],
      )
    ).rows;
    return {
      items: rows.map((r) => ({
        id: r.id,
        title: r.title,
        genre: r.genre,
        explicit: r.explicit,
        status: r.status,
        durationMs: r.duration_ms,
        codec: r.codec,
        bitrateKbps: r.bitrate_kbps,
        lossless: r.lossless,
        loudnessLufs: r.loudness_lufs === null ? null : Math.round(Number(r.loudness_lufs) * 10) / 10,
        submittedAt: r.submitted_at,
        checks: r.checks,
        artist: { id: r.artist_id, stageName: r.stage_name, verified: r.verified, strikes: r.strikes, publishedCount: r.published_count },
      })),
    };
  });

  /** Approves or rejects one song waiting for review. Returns false when it was not waiting. */
  async function decideOne(id: string, action: 'approve' | 'reject', actorId: string, reason: RejectReason | null, noteText: string | null): Promise<boolean> {
    const stamp = now().toISOString();
    const res =
      action === 'approve'
        ? await db.query<any>(
            `update tracks set status = 'published', published_at = coalesce(published_at, $2::timestamptz), reviewed_at = $2::timestamptz,
                    reviewed_by = $3, review_note = $4, reject_reason = null
             where id = $1 and status in ('in_review', 'held') returning title, artist_id`,
            [id, stamp, actorId, noteText],
          )
        : await db.query<any>(
            `update tracks set status = 'rejected', reviewed_at = $2::timestamptz, reviewed_by = $3, review_note = $4, reject_reason = $5
             where id = $1 and status in ('in_review', 'held') returning title, artist_id`,
            [id, stamp, actorId, noteText, reason],
          );
    const row = res.rows[0];
    if (!row) return false;
    await audit(db, now(), actorId, `track.${action}`, 'track', id, { reason, note: noteText });
    if (action === 'approve') {
      await notifyUser(db, messenger, row.artist_id, 'Your song is live', `Your song "${row.title}" was approved and is now live on Vyro.`);
    } else {
      await notifyUser(
        db,
        messenger,
        row.artist_id,
        'Your song was not approved',
        `Your song "${row.title}" was not approved because ${REASON_TEXT[reason!]}.${noteText ? ` ${noteText}` : ''} You can fix it and submit it again from the Studio.`,
      );
    }
    return true;
  }

  const decisionBody = z.object({ reason: z.enum(REJECT_REASONS).optional(), note });

  app.post('/v1/admin/review/tracks/:id/approve', staff, async (req, reply) => {
    const p = idParam.safeParse(req.params);
    const b = decisionBody.safeParse(req.body ?? {});
    if (!p.success) return invalid(reply, p.error);
    if (!b.success) return invalid(reply, b.error);
    return (await decideOne(p.data.id, 'approve', req.userId!, null, b.data.note ?? null)) ? { ok: true } : reply.code(409).send({ error: 'not_waiting_for_review' });
  });

  app.post('/v1/admin/review/tracks/:id/reject', staff, async (req, reply) => {
    const p = idParam.safeParse(req.params);
    const b = decisionBody.safeParse(req.body ?? {});
    if (!p.success) return invalid(reply, p.error);
    if (!b.success) return invalid(reply, b.error);
    if (!b.data.reason) return reply.code(400).send({ error: 'reason_required' });
    return (await decideOne(p.data.id, 'reject', req.userId!, b.data.reason, b.data.note ?? null)) ? { ok: true } : reply.code(409).send({ error: 'not_waiting_for_review' });
  });

  // Many songs at once (ADM-02).
  app.post('/v1/admin/review/bulk', staff, async (req, reply) => {
    const b = z.object({ action: z.enum(['approve', 'reject']), ids: z.array(z.uuid()).min(1).max(100), reason: z.enum(REJECT_REASONS).optional(), note }).safeParse(req.body);
    if (!b.success) return invalid(reply, b.error);
    if (b.data.action === 'reject' && !b.data.reason) return reply.code(400).send({ error: 'reason_required' });
    const skipped: string[] = [];
    let done = 0;
    for (const id of b.data.ids) {
      if (await decideOne(id, b.data.action, req.userId!, b.data.reason ?? null, b.data.note ?? null)) done++;
      else skipped.push(id);
    }
    return { done, skipped };
  });

  // Lets a reviewer listen to a song that is not public yet.
  app.get('/v1/admin/tracks/:id/stream-url', staff, async (req, reply) => {
    const p = idParam.safeParse(req.params);
    if (!p.success) return invalid(reply, p.error);
    const row = (await db.query<{ ok: boolean }>("select (audio_key is not null and status <> 'removed') as ok from tracks where id = $1", [p.data.id])).rows[0];
    if (!row?.ok) return reply.code(404).send({ error: 'not_found' });
    const exp = Math.floor(now().getTime() / 1000) + 3600;
    return { url: `/v1/stream/${signStreamToken(ctx.secret, p.data.id, exp)}`, expiresAt: new Date(exp * 1000).toISOString() };
  });

  // ---- copyright notices ---------------------------------------------------

  app.get('/v1/admin/takedowns', staff, async (req, reply) => {
    const q = z.object({ status: z.enum(['pending', 'open', 'counter_filed', 'upheld', 'restored']).default('pending') }).safeParse(req.query);
    if (!q.success) return invalid(reply, q.error);
    const rows = (
      await db.query<any>(
        `select n.*, t.title, ap.user_id as artist_id, ap.stage_name,
                (select count(*)::int from copyright_strikes s where s.artist_id = ap.user_id) as strikes
         from takedown_notices n join tracks t on t.id = n.track_id join artist_profiles ap on ap.user_id = t.artist_id
         where ($1 = 'pending' and n.status in ('open', 'counter_filed')) or n.status = $1
         order by n.created_at asc limit 100`,
        [q.data.status],
      )
    ).rows;
    return {
      notices: rows.map((n) => ({
        id: n.id,
        status: n.status,
        createdAt: n.created_at,
        track: { id: n.track_id, title: n.title },
        artist: { id: n.artist_id, stageName: n.stage_name, strikes: n.strikes },
        claimant: { name: n.claimant_name, email: n.claimant_email, company: n.claimant_company },
        statement: n.statement,
        counter: n.counter_statement ? { statement: n.counter_statement, signature: n.counter_signature, at: n.counter_at } : null,
      })),
    };
  });

  app.post('/v1/admin/takedowns/:id/resolve', staff, async (req, reply) => {
    const p = idParam.safeParse(req.params);
    const b = z.object({ decision: z.enum(['uphold', 'restore']), note }).safeParse(req.body);
    if (!p.success) return invalid(reply, p.error);
    if (!b.success) return invalid(reply, b.error);
    const n = (
      await db.query<any>(
        `select n.id, n.status, n.previous_status, n.track_id, n.claimant_email, t.title, t.artist_id
         from takedown_notices n join tracks t on t.id = n.track_id where n.id = $1`,
        [p.data.id],
      )
    ).rows[0];
    if (!n) return reply.code(404).send({ error: 'not_found' });
    if (n.status === 'upheld' || n.status === 'restored') return reply.code(409).send({ error: 'already_resolved' });
    const stamp = now().toISOString();

    if (b.data.decision === 'uphold') {
      await db.query("update takedown_notices set status = 'upheld', resolved_at = $2::timestamptz, resolved_by = $3 where id = $1", [n.id, stamp, req.userId]);
      await db.query('insert into copyright_strikes (artist_id, notice_id, created_at) values ($1, $2, $3::timestamptz)', [n.artist_id, n.id, stamp]);
      const strikes = (await db.query<{ n: number }>('select count(*)::int as n from copyright_strikes where artist_id = $1', [n.artist_id])).rows[0]!.n;
      await audit(db, now(), req.userId!, 'takedown.uphold', 'takedown', n.id, { strikes, note: b.data.note ?? null });
      await notifyUser(db, messenger, n.artist_id, 'Copyright notice upheld', `The copyright notice about "${n.title}" was upheld, so the song stays removed. This is strike ${strikes} of ${STRIKE_LIMIT}.`);
      if (strikes >= STRIKE_LIMIT) {
        await suspend(n.artist_id, req.userId!, 'Repeat copyright infringement');
        await notifyUser(db, messenger, n.artist_id, 'Account suspended', 'Your account was suspended after repeated upheld copyright notices.');
      }
    } else {
      // Back to where the song was before the notice (never straight to live if it was not live before).
      await db.query("update takedown_notices set status = 'restored', resolved_at = $2::timestamptz, resolved_by = $3 where id = $1", [n.id, stamp, req.userId]);
      await db.query("update tracks set status = $2 where id = $1 and status = 'taken_down'", [n.track_id, n.previous_status]);
      await audit(db, now(), req.userId!, 'takedown.restore', 'takedown', n.id, { note: b.data.note ?? null });
      await notifyUser(db, messenger, n.artist_id, 'Your song was restored', `The copyright notice about "${n.title}" was resolved in your favor and the song is back.`);
      await messenger.email(n.claimant_email, 'Your copyright notice', `After reviewing the counter-notice, we restored "${n.title}". If you disagree, you can pursue the matter through the courts.`).catch(() => undefined);
    }
    return { ok: true };
  });

  // ---- people --------------------------------------------------------------

  app.get('/v1/admin/artists', staff, async (req, reply) => {
    const q = z.object({ q: z.string().trim().max(80).default(''), limit: z.coerce.number().int().min(1).max(50).default(30) }).safeParse(req.query);
    if (!q.success) return invalid(reply, q.error);
    const like = `%${q.data.q.replace(/[\\%_]/g, (c) => `\\${c}`)}%`;
    const rows = (
      await db.query<any>(
        `select ap.user_id as id, ap.stage_name, ap.verified, u.username, (u.suspended_at is not null) as suspended, u.suspension_reason,
                (select count(*)::int from copyright_strikes s where s.artist_id = ap.user_id) as strikes,
                (select count(*)::int from tracks t where t.artist_id = ap.user_id and t.status <> 'removed') as tracks
         from artist_profiles ap join users u on u.id = ap.user_id
         where ap.stage_name ilike $1 escape '\\' or u.username ilike $1 escape '\\'
         order by ap.stage_name limit $2`,
        [like, q.data.limit],
      )
    ).rows;
    return {
      artists: rows.map((r) => ({ id: r.id, stageName: r.stage_name, username: r.username, verified: r.verified, suspended: r.suspended, suspensionReason: r.suspension_reason, strikes: r.strikes, trackCount: r.tracks })),
    };
  });

  app.post('/v1/admin/artists/:id/verify', staff, async (req, reply) => {
    const p = idParam.safeParse(req.params);
    const b = z.object({ verified: z.boolean() }).safeParse(req.body);
    if (!p.success) return invalid(reply, p.error);
    if (!b.success) return invalid(reply, b.error);
    const res = await db.query('update artist_profiles set verified = $2 where user_id = $1 returning user_id', [p.data.id, b.data.verified]);
    if (res.rows.length === 0) return reply.code(404).send({ error: 'not_found' });
    await audit(db, now(), req.userId!, b.data.verified ? 'artist.verify' : 'artist.unverify', 'user', p.data.id);
    return { ok: true };
  });

  async function suspend(userId: string, actorId: string, reason: string) {
    await db.query('update users set suspended_at = $2::timestamptz, suspension_reason = $3 where id = $1', [userId, now().toISOString(), reason]);
    await db.query('update refresh_tokens set revoked_at = now() where user_id = $1 and revoked_at is null', [userId]); // signs them out everywhere
    await audit(db, now(), actorId, 'user.suspend', 'user', userId, { reason });
  }

  app.post('/v1/admin/users/:id/suspend', staff, async (req, reply) => {
    const p = idParam.safeParse(req.params);
    const b = z.object({ reason: z.string().trim().min(3).max(300) }).safeParse(req.body);
    if (!p.success) return invalid(reply, p.error);
    if (!b.success) return invalid(reply, b.error);
    const target = (await db.query<{ role: Role }>('select role from users where id = $1', [p.data.id])).rows[0];
    if (!target) return reply.code(404).send({ error: 'not_found' });
    if (target.role !== 'user' || p.data.id === req.userId) return reply.code(403).send({ error: 'cannot_suspend_staff' });
    await suspend(p.data.id, req.userId!, b.data.reason);
    await notifyUser(db, messenger, p.data.id, 'Account suspended', `Your account was suspended: ${b.data.reason}`);
    return { ok: true };
  });

  app.post('/v1/admin/users/:id/unsuspend', staff, async (req, reply) => {
    const p = idParam.safeParse(req.params);
    if (!p.success) return invalid(reply, p.error);
    const res = await db.query('update users set suspended_at = null, suspension_reason = null where id = $1 and suspended_at is not null returning id', [p.data.id]);
    if (res.rows.length === 0) return reply.code(404).send({ error: 'not_found' });
    await audit(db, now(), req.userId!, 'user.unsuspend', 'user', p.data.id);
    return { ok: true };
  });

  app.post('/v1/admin/users/:id/role', adminOnly, async (req, reply) => {
    const p = idParam.safeParse(req.params);
    const b = z.object({ role: z.enum(['user', 'moderator', 'admin']) }).safeParse(req.body);
    if (!p.success) return invalid(reply, p.error);
    if (!b.success) return invalid(reply, b.error);
    if (p.data.id === req.userId) return reply.code(403).send({ error: 'cannot_change_own_role' });
    const res = await db.query('update users set role = $2 where id = $1 returning id', [p.data.id, b.data.role]);
    if (res.rows.length === 0) return reply.code(404).send({ error: 'not_found' });
    await audit(db, now(), req.userId!, 'user.role', 'user', p.data.id, { role: b.data.role });
    return { ok: true };
  });

  app.get('/v1/admin/audit', adminOnly, async (req, reply) => {
    const q = z.object({ limit: z.coerce.number().int().min(1).max(200).default(50) }).safeParse(req.query);
    if (!q.success) return invalid(reply, q.error);
    const rows = (await db.query<any>('select id, actor_id, action, target_type, target_id, details, created_at from audit_log order by created_at desc limit $1', [q.data.limit])).rows;
    return { entries: rows.map((r) => ({ id: r.id, actorId: r.actor_id, action: r.action, targetType: r.target_type, targetId: r.target_id, details: r.details, at: r.created_at })) };
  });
}
