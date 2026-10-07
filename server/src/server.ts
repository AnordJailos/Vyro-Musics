import { buildApp } from './app.js';
import { pgDb } from './db.js';
import { migrate } from './migrate.js';

const url = process.env.DATABASE_URL;
const secret = process.env.JWT_SECRET;
if (!url || !secret || secret.length < 32) {
  console.error('DATABASE_URL and JWT_SECRET (at least 32 characters) are required.');
  process.exit(1);
}

const db = await pgDb(url);
await migrate(db);
const app = await buildApp({ db, jwtSecret: secret, logger: true });
await app.listen({ port: Number(process.env.PORT ?? 3000), host: '0.0.0.0' });
