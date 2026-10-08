import { buildApp } from './app.js';
import { pgDb } from './db.js';
import { makeSocialVerifier } from './idtokens.js';
import { migrate } from './migrate.js';
import { ConsoleMessenger } from './messaging.js';

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
const app = await buildApp({
  db,
  jwtSecret: secret,
  logger: true,
  messenger: new ConsoleMessenger(),
  social: makeSocialVerifier({ googleClientIds: ids('GOOGLE_CLIENT_IDS'), appleClientIds: ids('APPLE_CLIENT_IDS') }),
});
await app.listen({ port: Number(process.env.PORT ?? 3000), host: '0.0.0.0' });
