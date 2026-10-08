import { Readable } from 'node:stream';
import Fastify, { type FastifyReply, type FastifyRequest } from 'fastify';
import rateLimit from '@fastify/rate-limit';
import type { z } from 'zod';
import { ageOn } from './age.js';
import { FfmpegTranscoder, type Transcoder } from './audio.js';
import { registerAuthRoutes } from './auth_routes.js';
import { registerCatalogRoutes } from './catalog_routes.js';
import type { Ctx } from './context.js';
import type { Db } from './db.js';
import { makeSocialVerifier, type SocialVerifier } from './idtokens.js';
import { registerMeRoutes } from './me_routes.js';
import { ConsoleMessenger, type Messenger } from './messaging.js';
import { hashPassword, newRefreshToken, sha256, tokenKit } from './security.js';
import { LocalDiskStorage, type Storage } from './storage.js';
import { registerStatsRoutes } from './stats_routes.js';
import { registerStudioRoutes } from './studio_routes.js';

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
  /** Delivers email and SMS codes. Defaults to printing them to the console (development only). */
  messenger?: Messenger;
  /** Checks Google and Apple ID tokens. Defaults to "not configured". */
  social?: SocialVerifier;
  /** Where uploaded files are kept. Defaults to the STORAGE_DIR folder (or ./data). */
  storage?: Storage;
  /** ffmpeg helper. Leave out to detect ffmpeg automatically, or pass null to switch it off. */
  transcoder?: Transcoder | null;
  /** Largest song upload accepted, in bytes. */
  maxAudioBytes?: number;
}

const REFRESH_DAYS = 30;

export async function buildApp(deps: AppDeps) {
  const { db, jwtSecret, authRateLimit = 20, logger = false, now = () => new Date(), minCohort = 5 } = deps;
  const app = Fastify({ logger });
  await app.register(rateLimit, { global: false });
  app.decorateRequest('userId', null);
  // Uploads arrive as the raw request body: keep them as a stream instead of loading them into memory.
  app.addContentTypeParser(/^(audio|image)\/.+$|^application\/octet-stream$/, (_req, payload, done) => done(null, payload as Readable));

  const tokens = tokenKit(jwtSecret);

  async function issueTokens(userId: string, deviceName: string | null = null) {
    const refreshToken = newRefreshToken();
    const expires = new Date(now().getTime() + REFRESH_DAYS * 86_400_000).toISOString();
    await db.query('insert into refresh_tokens (user_id, token_hash, expires_at, device_name) values ($1, $2, $3, $4)', [userId, sha256(refreshToken), expires, deviceName]);
    return { accessToken: await tokens.signAccess(userId), refreshToken, expiresIn: 900 };
  }

  async function loadMe(userId: string) {
    const u = (
      await db.query<any>(
        `select id, email, phone, display_name, username, country, language, created_at,
                to_char(birth_date, 'YYYY-MM-DD') as birth_date,
                email_verified_at, phone_verified_at, explicit_allowed, parent_consent,
                private_session, hide_activity, share_listening, personalization,
                (password_hash is not null) as has_password,
                exists (select 1 from taste_profiles t where t.user_id = users.id) as taste_set
         from users where id = $1`,
        [userId],
      )
    ).rows[0];
    if (!u) return null;
    const a = (
      await db.query<any>('select stage_name, bio, artist_type, verified, genres, links from artist_profiles where user_id = $1', [userId])
    ).rows[0];
    const age = u.birth_date ? ageOn(u.birth_date as string, now()) : null;
    return {
      id: u.id,
      email: u.email,
      phone: u.phone,
      displayName: u.display_name,
      username: u.username,
      country: u.country,
      language: u.language,
      createdAt: u.created_at,
      emailVerified: u.email_verified_at != null,
      phoneVerified: u.phone_verified_at != null,
      hasPassword: u.has_password,
      isMinor: age !== null && age < 18,
      parentConsent: u.parent_consent,
      settings: {
        explicitAllowed: u.explicit_allowed,
        privateSession: u.private_session,
        hideActivity: u.hide_activity,
        shareListening: u.share_listening,
        personalization: u.personalization,
      },
      tasteSet: u.taste_set,
      artist: a
        ? { stageName: a.stage_name, bio: a.bio, artistType: a.artist_type, verified: a.verified, genres: a.genres, links: a.links }
        : null,
      modes: a ? ['listener', 'artist'] : ['listener'],
    };
  }

  async function requireUser(req: FastifyRequest, reply: FastifyReply) {
    const header = req.headers.authorization ?? '';
    const userId = header.startsWith('Bearer ') ? await tokens.verifyAccess(header.slice(7)) : null;
    if (!userId) return reply.code(401).send({ error: 'unauthorized' });
    req.userId = userId;
  }

  async function optionalUser(req: FastifyRequest) {
    const header = req.headers.authorization ?? '';
    req.userId = header.startsWith('Bearer ') ? await tokens.verifyAccess(header.slice(7)) : null;
  }

  const ctx: Ctx = {
    app,
    db,
    secret: jwtSecret,
    now,
    messenger: deps.messenger ?? new ConsoleMessenger(),
    social: deps.social ?? makeSocialVerifier({ googleClientIds: [], appleClientIds: [] }),
    tokens,
    limit: { config: { rateLimit: { max: authRateLimit, timeWindow: '1 minute' } } },
    dummyHash: await hashPassword('not-a-real-password'),
    invalid: (reply: FastifyReply, error: z.ZodError) =>
      reply.code(400).send({ error: 'invalid_request', details: error.issues.map((i) => ({ path: i.path.join('.'), message: i.message })) }),
    issueTokens,
    loadMe,
    requireUser,
    optionalUser,
    storage: deps.storage ?? new LocalDiskStorage(process.env.STORAGE_DIR ?? './data'),
    transcoder: deps.transcoder === undefined ? await FfmpegTranscoder.detect() : deps.transcoder,
    maxAudioBytes: deps.maxAudioBytes ?? 300 * 1024 * 1024,
  };

  app.get('/health', async () => ({ status: 'ok' }));
  app.get('/v1/config', async () => {
    const rows = (await db.query<{ key: string; enabled: boolean }>('select key, enabled from feature_flags')).rows;
    return { flags: Object.fromEntries(rows.map((r) => [r.key, r.enabled])) };
  });

  registerAuthRoutes(ctx);
  registerMeRoutes(ctx);
  registerStudioRoutes(ctx);
  registerCatalogRoutes(ctx);
  registerStatsRoutes({ app, db, requireUser, now, minCohort });

  return app;
}
