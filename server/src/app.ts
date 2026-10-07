import Fastify, { type FastifyReply, type FastifyRequest } from 'fastify';
import rateLimit from '@fastify/rate-limit';
import { z } from 'zod';
import { isUniqueViolation, type Db } from './db.js';
import { hashPassword, newRefreshToken, sha256, tokenKit, verifyPassword } from './security.js';
import { registerStatsRoutes } from './stats_routes.js';

declare module 'fastify' {
  interface FastifyRequest {
    userId: string | null;
  }
}

export interface AppDeps {
  db: Db;
  jwtSecret: string;
  authRateLimit?: number;
  logger?: boolean;
  /** Clock, replaceable in tests. */
  now?: () => Date;
  /** Smallest group of listeners that a statistics breakdown may reveal. */
  minCohort?: number;
}

const REFRESH_DAYS = 30;

const registerBody = z.object({
  email: z.email().max(254),
  password: z.string().min(8).max(128),
  displayName: z.string().trim().min(1).max(60),
  username: z.string().regex(/^[a-z0-9_]{3,24}$/),
  country: z.string().length(2).optional(),
  acceptedTermsVersion: z.string().min(1).max(32),
});
const loginBody = z.object({ email: z.email(), password: z.string().min(1).max(128) });
const refreshBody = z.object({ refreshToken: z.string().min(20).max(200) });
const artistBody = z.object({
  stageName: z.string().trim().min(2).max(60),
  artistType: z.enum(['solo', 'group', 'producer_dj', 'label_manager']),
  bio: z.string().max(500).default(''),
  rightsDeclaration: z.literal(true),
  agreementVersion: z.string().min(1).max(32),
});

export async function buildApp({ db, jwtSecret, authRateLimit = 20, logger = false, now = () => new Date(), minCohort = 5 }: AppDeps) {
  const app = Fastify({ logger });
  await app.register(rateLimit, { global: false });
  app.decorateRequest('userId', null);

  const tokens = tokenKit(jwtSecret);
  const dummyHash = await hashPassword('not-a-real-password');
  const limit = { config: { rateLimit: { max: authRateLimit, timeWindow: '1 minute' } } };

  const invalid = (reply: FastifyReply, error: z.ZodError) =>
    reply.code(400).send({ error: 'invalid_request', details: error.issues.map((i) => ({ path: i.path.join('.'), message: i.message })) });

  async function issueTokens(userId: string) {
    const refreshToken = newRefreshToken();
    const expires = new Date(Date.now() + REFRESH_DAYS * 86_400_000).toISOString();
    await db.query('insert into refresh_tokens (user_id, token_hash, expires_at) values ($1, $2, $3)', [userId, sha256(refreshToken), expires]);
    return { accessToken: await tokens.signAccess(userId), refreshToken, expiresIn: 900 };
  }

  async function loadMe(userId: string) {
    const u = (await db.query<any>('select id, email, display_name, username, country, created_at from users where id = $1', [userId])).rows[0];
    if (!u) return null;
    const a = (await db.query<any>('select stage_name, bio, artist_type, verified, created_at from artist_profiles where user_id = $1', [userId])).rows[0];
    return {
      id: u.id,
      email: u.email,
      displayName: u.display_name,
      username: u.username,
      country: u.country,
      createdAt: u.created_at,
      artist: a ? { stageName: a.stage_name, bio: a.bio, artistType: a.artist_type, verified: a.verified } : null,
      modes: a ? ['listener', 'artist'] : ['listener'],
    };
  }

  async function requireUser(req: FastifyRequest, reply: FastifyReply) {
    const header = req.headers.authorization ?? '';
    const userId = header.startsWith('Bearer ') ? await tokens.verifyAccess(header.slice(7)) : null;
    if (!userId) return reply.code(401).send({ error: 'unauthorized' });
    req.userId = userId;
  }

  app.get('/health', async () => ({ status: 'ok' }));

  app.get('/v1/config', async () => {
    const rows = (await db.query<{ key: string; enabled: boolean }>('select key, enabled from feature_flags')).rows;
    return { flags: Object.fromEntries(rows.map((r) => [r.key, r.enabled])) };
  });

  app.post('/v1/auth/register', limit, async (req, reply) => {
    const parsed = registerBody.safeParse(req.body);
    if (!parsed.success) return invalid(reply, parsed.error);
    const b = parsed.data;
    try {
      const ins = await db.query<{ id: string }>(
        'insert into users (email, password_hash, display_name, username, country) values ($1, $2, $3, $4, $5) returning id',
        [b.email.toLowerCase(), await hashPassword(b.password), b.displayName, b.username, b.country?.toUpperCase() ?? null],
      );
      const id = ins.rows[0]!.id;
      for (const doc of ['terms', 'privacy']) {
        await db.query('insert into consents (user_id, document, version) values ($1, $2, $3)', [id, doc, b.acceptedTermsVersion]);
      }
      return reply.code(201).send({ user: await loadMe(id), ...(await issueTokens(id)) });
    } catch (e) {
      if (isUniqueViolation(e)) return reply.code(409).send({ error: 'email_or_username_taken' });
      throw e;
    }
  });

  app.post('/v1/auth/login', limit, async (req, reply) => {
    const parsed = loginBody.safeParse(req.body);
    if (!parsed.success) return invalid(reply, parsed.error);
    const row = (await db.query<{ id: string; password_hash: string }>('select id, password_hash from users where email = $1', [parsed.data.email.toLowerCase()])).rows[0];
    const ok = await verifyPassword(parsed.data.password, row?.password_hash ?? dummyHash);
    if (!row || !ok) return reply.code(401).send({ error: 'invalid_credentials' });
    return { user: await loadMe(row.id), ...(await issueTokens(row.id)) };
  });

  app.post('/v1/auth/refresh', limit, async (req, reply) => {
    const parsed = refreshBody.safeParse(req.body);
    if (!parsed.success) return invalid(reply, parsed.error);
    const row = (
      await db.query<{ user_id: string }>(
        'update refresh_tokens set revoked_at = now() where token_hash = $1 and revoked_at is null and expires_at > now() returning user_id',
        [sha256(parsed.data.refreshToken)],
      )
    ).rows[0];
    if (!row) return reply.code(401).send({ error: 'invalid_refresh_token' });
    return issueTokens(row.user_id);
  });

  app.post('/v1/auth/logout', async (req, reply) => {
    const parsed = refreshBody.safeParse(req.body);
    if (!parsed.success) return invalid(reply, parsed.error);
    await db.query('update refresh_tokens set revoked_at = now() where token_hash = $1 and revoked_at is null', [sha256(parsed.data.refreshToken)]);
    return reply.code(204).send();
  });

  app.get('/v1/me', { preHandler: requireUser }, async (req, reply) => {
    const me = await loadMe(req.userId!);
    return me ?? reply.code(401).send({ error: 'unauthorized' });
  });

  app.delete('/v1/me', { preHandler: requireUser }, async (req, reply) => {
    await db.query('delete from users where id = $1', [req.userId]);
    return reply.code(204).send();
  });

  app.post('/v1/artists/me', { preHandler: requireUser }, async (req, reply) => {
    const parsed = artistBody.safeParse(req.body);
    if (!parsed.success) return invalid(reply, parsed.error);
    const b = parsed.data;
    try {
      await db.query(
        'insert into artist_profiles (user_id, stage_name, bio, artist_type, rights_accepted_at, agreement_version) values ($1, $2, $3, $4, now(), $5)',
        [req.userId, b.stageName, b.bio, b.artistType, b.agreementVersion],
      );
    } catch (e) {
      if (isUniqueViolation(e)) return reply.code(409).send({ error: 'already_artist_or_stage_name_taken' });
      throw e;
    }
    return reply.code(201).send(await loadMe(req.userId!));
  });

  registerStatsRoutes({ app, db, requireUser, now, minCohort });

  return app;
}
