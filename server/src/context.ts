import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import type { z } from 'zod';
import type { Db } from './db.js';
import type { SocialVerifier } from './idtokens.js';
import type { Transcoder } from './audio.js';
import type { Messenger } from './messaging.js';
import type { tokenKit } from './security.js';
import type { Storage } from './storage.js';

export type Guard = (req: FastifyRequest, reply: FastifyReply) => Promise<unknown>;

/** What every group of routes needs. */
export interface Ctx {
  app: FastifyInstance;
  db: Db;
  secret: string;
  now: () => Date;
  messenger: Messenger;
  social: SocialVerifier;
  tokens: ReturnType<typeof tokenKit>;
  /** Route options that rate-limit sign-in style endpoints. */
  limit: { config: { rateLimit: { max: number; timeWindow: string } } };
  dummyHash: string;
  invalid(reply: FastifyReply, error: z.ZodError): FastifyReply;
  issueTokens(userId: string, deviceName?: string | null): Promise<{ accessToken: string; refreshToken: string; expiresIn: number }>;
  loadMe(userId: string): Promise<Record<string, unknown> | null>;
  requireUser: Guard;
  /** Fills in the signed-in person when there is one, and lets everyone else through. */
  optionalUser: Guard;
  storage: Storage;
  /** ffmpeg, when available: streaming copies and loudness measurement. */
  transcoder: Transcoder | null;
  maxAudioBytes: number;
}
