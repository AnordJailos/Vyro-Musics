import { z } from 'zod';
import { ARTIST_MIN_AGE, ageOn } from './age.js';
import type { Ctx } from './context.js';
import { isUniqueViolation } from './db.js';
import { normalizeName } from './names.js';
import { verifyPassword } from './security.js';

const profilePatch = z.object({
  displayName: z.string().trim().min(1).max(60).optional(),
  username: z.string().regex(/^[a-z0-9_]{3,24}$/).optional(),
  country: z.string().length(2).nullable().optional(),
  language: z.string().min(2).max(10).optional(),
});
const settingsPatch = z.object({
  explicitAllowed: z.boolean().optional(),
  privateSession: z.boolean().optional(),
  hideActivity: z.boolean().optional(),
  shareListening: z.boolean().optional(),
  personalization: z.boolean().optional(),
});
const tag = z.string().trim().toLowerCase().min(1).max(40);
const tasteBody = z.object({
  genres: z.array(tag).max(30).default([]),
  moods: z.array(tag).max(30).default([]),
  artistIds: z.array(z.uuid()).max(50).default([]),
});
const deleteBody = z.object({ confirm: z.literal('DELETE'), password: z.string().max(128).optional() });
const artistBody = z.object({
  stageName: z.string().trim().min(2).max(60),
  artistType: z.enum(['solo', 'group', 'producer_dj', 'label_manager']),
  bio: z.string().max(500).default(''),
  genres: z.array(tag).max(10).default([]),
  links: z.array(z.url().max(300)).max(8).default([]),
  rightsDeclaration: z.literal(true),
  agreementVersion: z.string().min(1).max(32),
});
const artistPatch = z.object({
  bio: z.string().max(500).optional(),
  genres: z.array(tag).max(10).optional(),
  links: z.array(z.url().max(300)).max(8).optional(),
});
const suggestedQuery = z.object({ limit: z.coerce.number().int().min(1).max(50).default(20) });

export function registerMeRoutes(ctx: Ctx) {
  const { app, db, now, invalid, loadMe, requireUser } = ctx;
  const userOnly = { preHandler: requireUser };

  app.get('/v1/me', userOnly, async (req, reply) => (await loadMe(req.userId!)) ?? reply.code(401).send({ error: 'unauthorized' }));

  app.patch('/v1/me', userOnly, async (req, reply) => {
    const parsed = profilePatch.safeParse(req.body);
    if (!parsed.success) return invalid(reply, parsed.error);
    const p = parsed.data;
    try {
      await db.query(
        `update users set display_name = coalesce($2, display_name), username = coalesce($3, username),
                country = case when $4::boolean then $5 else country end, language = coalesce($6, language)
         where id = $1`,
        [req.userId, p.displayName ?? null, p.username ?? null, p.country !== undefined, p.country?.toUpperCase() ?? null, p.language ?? null],
      );
    } catch (e) {
      if (isUniqueViolation(e)) return reply.code(409).send({ error: 'username_taken' });
      throw e;
    }
    return loadMe(req.userId!);
  });

  // Privacy and content settings (AUTH-10).
  app.patch('/v1/me/settings', userOnly, async (req, reply) => {
    const parsed = settingsPatch.safeParse(req.body);
    if (!parsed.success) return invalid(reply, parsed.error);
    const p = parsed.data;
    if (p.explicitAllowed === true) {
      const u = (await db.query<{ birth_date: string | null; parent_consent: string }>("select to_char(birth_date, 'YYYY-MM-DD') as birth_date, parent_consent from users where id = $1", [req.userId])).rows[0];
      const age = u?.birth_date ? ageOn(u.birth_date, now()) : 18;
      if (age < 18) return reply.code(403).send({ error: 'age_restricted' }); // explicit content stays off for minors
    }
    await db.query(
      `update users set explicit_allowed = coalesce($2, explicit_allowed), private_session = coalesce($3, private_session),
              hide_activity = coalesce($4, hide_activity), share_listening = coalesce($5, share_listening),
              personalization = coalesce($6, personalization)
       where id = $1`,
      [req.userId, p.explicitAllowed ?? null, p.privateSession ?? null, p.hideActivity ?? null, p.shareListening ?? null, p.personalization ?? null],
    );
    return loadMe(req.userId!);
  });

  // First-launch taste picker (AUTH-05). Replaces the previous choice.
  app.put('/v1/me/taste', userOnly, async (req, reply) => {
    const parsed = tasteBody.safeParse(req.body);
    if (!parsed.success) return invalid(reply, parsed.error);
    const { genres, moods, artistIds } = parsed.data;
    let known: string[] = [];
    if (artistIds.length > 0) {
      const marks = artistIds.map((_, i) => `$${i + 1}`).join(', ');
      known = (await db.query<{ user_id: string }>(`select user_id from artist_profiles where user_id in (${marks})`, artistIds)).rows.map((r) => r.user_id);
    }
    await db.query(
      `insert into taste_profiles (user_id, genres, moods, artist_ids, updated_at) values ($1, $2::jsonb, $3::jsonb, $4::jsonb, $5::timestamptz)
       on conflict (user_id) do update set genres = excluded.genres, moods = excluded.moods, artist_ids = excluded.artist_ids, updated_at = excluded.updated_at`,
      [req.userId, JSON.stringify(genres), JSON.stringify(moods), JSON.stringify(known), now().toISOString()],
    );
    for (const id of known) {
      if (id !== req.userId) await db.query('insert into follows (user_id, artist_id, created_at) values ($1, $2, $3::timestamptz) on conflict do nothing', [req.userId, id, now().toISOString()]);
    }
    return loadMe(req.userId!);
  });

  app.get('/v1/artists/suggested', userOnly, async (req, reply) => {
    const q = suggestedQuery.safeParse(req.query);
    if (!q.success) return invalid(reply, q.error);
    const rows = (
      await db.query<any>(
        `select ap.user_id as id, ap.stage_name, ap.genres, (select count(*) from follows f where f.artist_id = ap.user_id)::int as followers
         from artist_profiles ap where ap.user_id <> $1 order by followers desc, ap.created_at desc limit $2`,
        [req.userId, q.data.limit],
      )
    ).rows;
    return { artists: rows.map((r) => ({ id: r.id, stageName: r.stage_name, genres: r.genres, followers: r.followers })) };
  });

  // Deleting an account needs the typed word, and the password when the account has one (AUTH-08).
  app.post('/v1/me/delete', userOnly, async (req, reply) => {
    const parsed = deleteBody.safeParse(req.body);
    if (!parsed.success) return invalid(reply, parsed.error);
    const row = (await db.query<{ password_hash: string | null }>('select password_hash from users where id = $1', [req.userId])).rows[0];
    if (!row) return reply.code(401).send({ error: 'unauthorized' });
    if (row.password_hash && (!parsed.data.password || !(await verifyPassword(parsed.data.password, row.password_hash)))) {
      return reply.code(403).send({ error: 'password_required' });
    }
    await db.query('delete from users where id = $1', [req.userId]);
    return reply.code(204).send();
  });

  // ---- becoming an artist (ART-01) -------------------------------------------

  app.post('/v1/artists/me', userOnly, async (req, reply) => {
    const parsed = artistBody.safeParse(req.body);
    if (!parsed.success) return invalid(reply, parsed.error);
    const b = parsed.data;
    const u = (
      await db.query<any>(
        `select email_verified_at, phone_verified_at, parent_consent, to_char(birth_date, 'YYYY-MM-DD') as birth_date,
                exists (select 1 from artist_profiles a where a.user_id = users.id) as is_artist
         from users where id = $1`,
        [req.userId],
      )
    ).rows[0];
    if (!u) return reply.code(401).send({ error: 'unauthorized' });
    if (u.is_artist) return reply.code(409).send({ error: 'already_artist' });
    if (!u.email_verified_at && !u.phone_verified_at) return reply.code(403).send({ error: 'verify_contact_first' });
    if (u.parent_consent === 'pending') return reply.code(403).send({ error: 'parent_consent_pending' });
    if (u.birth_date && ageOn(u.birth_date, now()) < ARTIST_MIN_AGE) return reply.code(403).send({ error: 'artist_requires_adult' });
    const key = normalizeName(b.stageName);
    if (key.length < 2) return invalid(reply, new z.ZodError([{ code: 'custom', path: ['stageName'], message: 'Use letters or numbers in the name.', input: b.stageName }]));
    try {
      await db.query(
        `insert into artist_profiles (user_id, stage_name, stage_name_key, bio, artist_type, genres, links, rights_accepted_at, agreement_version)
         values ($1, $2, $3, $4, $5, $6::jsonb, $7::jsonb, $8::timestamptz, $9)`,
        [req.userId, b.stageName, key, b.bio, b.artistType, JSON.stringify(b.genres), JSON.stringify(b.links), now().toISOString(), b.agreementVersion],
      );
    } catch (e) {
      if (isUniqueViolation(e)) return reply.code(409).send({ error: 'stage_name_taken' });
      throw e;
    }
    return reply.code(201).send(await loadMe(req.userId!));
  });

  app.patch('/v1/artists/me', userOnly, async (req, reply) => {
    const parsed = artistPatch.safeParse(req.body);
    if (!parsed.success) return invalid(reply, parsed.error);
    const p = parsed.data;
    const res = await db.query(
      `update artist_profiles set bio = coalesce($2, bio), genres = coalesce($3::jsonb, genres), links = coalesce($4::jsonb, links)
       where user_id = $1 returning user_id`,
      [req.userId, p.bio ?? null, p.genres ? JSON.stringify(p.genres) : null, p.links ? JSON.stringify(p.links) : null],
    );
    if (res.rows.length === 0) return reply.code(404).send({ error: 'not_an_artist' });
    return loadMe(req.userId!);
  });
}
