import { promoteAdmins } from './admins.js';
import { buildApp } from './app.js';
import { AcoustIdChecker } from './copyright.js';
import { pgDb } from './db.js';
import { makeSocialVerifier } from './idtokens.js';
import { migrate } from './migrate.js';
import { ConsoleMessenger } from './messaging.js';
import type { ReviewPolicy } from './review.js';

const url = process.env.DATABASE_URL;
const secret = process.env.JWT_SECRET;
if (!url || !secret || secret.length < 32) {
  console.error('DATABASE_URL and JWT_SECRET (at least 32 characters) are required.');
  process.exit(1);
}

const ids = (name: string) => (process.env[name] ?? '').split(',').map((s) => s.trim()).filter(Boolean);

console.warn(
  'Email and SMS codes are printed to this console. Connect a real email and SMS provider (see src/messaging.ts) before real users sign up.',
);

const db = await pgDb(url);
await migrate(db);

const admins = await promoteAdmins(db, ids('ADMIN_EMAILS'));
if (admins > 0) console.log(`${admins} account(s) promoted to administrator from ADMIN_EMAILS.`);

const policy = (process.env.REVIEW_POLICY ?? 'all') as ReviewPolicy;
if (!['all', 'new_artists', 'none'].includes(policy)) throw new Error('REVIEW_POLICY must be all, new_artists or none');
const app = await buildApp({
  db,
  jwtSecret: secret,
  logger: true,
  messenger: new ConsoleMessenger(),
  reviewPolicy: policy,
  copyright: process.env.ACOUSTID_API_KEY ? new AcoustIdChecker(process.env.ACOUSTID_API_KEY) : null,
  social: makeSocialVerifier({ googleClientIds: ids('GOOGLE_CLIENT_IDS'), appleClientIds: ids('APPLE_CLIENT_IDS') }),
});
await app.listen({ port: Number(process.env.PORT ?? 3000), host: '0.0.0.0' });
