import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { buildApp, type AppDeps } from '../src/app.js';
import { memoryDb } from '../src/db.js';
import { MemoryMessenger } from '../src/messaging.js';
import { migrate } from '../src/migrate.js';
import { LocalDiskStorage } from '../src/storage.js';

export type TestApp = Awaited<ReturnType<typeof buildApp>>;

export async function makeApp(extra: Partial<AppDeps> = {}) {
  const db = await memoryDb();
  await migrate(db);
  const messenger = new MemoryMessenger();
  const dir = mkdtempSync(join(tmpdir(), 'vyro-test-'));
  const app = await buildApp({ db, jwtSecret: 'x'.repeat(40), authRateLimit: 10_000, messenger, storage: new LocalDiskStorage(dir), ...extra });
  return { app, db, messenger, cleanup: () => rmSync(dir, { recursive: true, force: true }) };
}

export const PASSWORD = 'correct-horse-battery';

export function api(app: TestApp) {
  const call = (method: 'GET' | 'POST' | 'PATCH' | 'PUT' | 'DELETE', url: string, token?: string | null, payload?: object) =>
    app.inject({ method, url, payload, headers: token ? { authorization: `Bearer ${token}` } : {} });
  return { call };
}

export const registerBody = (name: string, extra: object = {}) => ({
  email: `${name}@Example.com`,
  password: PASSWORD,
  displayName: `User ${name}`,
  username: `user_${name}`,
  birthDate: '1990-01-15',
  acceptedTermsVersion: '2026-10',
  ...extra,
});

/** Registers an adult and confirms the email with the code that was "sent". */
export async function signUpVerified(app: TestApp, messenger: InstanceType<typeof MemoryMessenger>, name: string, extra: object = {}) {
  const { call } = api(app);
  const res = await call('POST', '/v1/auth/register', null, registerBody(name, extra));
  if (res.statusCode !== 201) throw new Error(`register failed: ${res.statusCode} ${res.body}`);
  const body = res.json();
  const email = `${name}@example.com`;
  const verify = await call('POST', '/v1/auth/email/verify', body.accessToken, { code: messenger.lastCode(email) });
  if (verify.statusCode !== 200) throw new Error(`verify failed: ${verify.statusCode} ${verify.body}`);
  return { id: body.user.id as string, token: body.accessToken as string, refreshToken: body.refreshToken as string, email };
}

export const artistBody = (extra: object = {}) => ({
  stageName: 'Nova Wave',
  artistType: 'solo',
  bio: 'Test artist',
  rightsDeclaration: true,
  agreementVersion: '2026-10',
  ...extra,
});
