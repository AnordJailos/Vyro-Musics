import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';
import { memoryDb } from '../src/db.js';
import { migrate } from '../src/migrate.js';

let app: Awaited<ReturnType<typeof buildApp>>;

beforeAll(async () => {
  const db = await memoryDb();
  await migrate(db);
  app = await buildApp({ db, jwtSecret: 'x'.repeat(40), authRateLimit: 1000 });
}, 60_000);
afterAll(() => app.close());

const post = (url: string, payload: unknown, token?: string) =>
  app.inject({ method: 'POST', url, payload: payload as object, headers: token ? { authorization: `Bearer ${token}` } : {} });

const newUser = (n: string, extra: object = {}) => ({
  email: `${n}@Example.com`,
  password: 'correct-horse-battery',
  displayName: `User ${n}`,
  username: `user_${n}`,
  acceptedTermsVersion: '2026-10',
  ...extra,
});

describe('accounts', () => {
  it('registers a listener and normalizes the email', async () => {
    const res = await post('/v1/auth/register', newUser('amani'));
    expect(res.statusCode).toBe(201);
    const body = res.json();
    expect(body.user.email).toBe('amani@example.com');
    expect(body.user.modes).toEqual(['listener']);
    expect(body.accessToken).toBeTruthy();
  });

  it('rejects weak passwords and bad usernames', async () => {
    expect((await post('/v1/auth/register', newUser('weak', { password: 'short' }))).statusCode).toBe(400);
    expect((await post('/v1/auth/register', newUser('bad', { username: 'Bad Name!' }))).statusCode).toBe(400);
  });

  it('rejects a duplicate email regardless of case', async () => {
    await post('/v1/auth/register', newUser('dup'));
    const res = await post('/v1/auth/register', newUser('other', { email: 'DUP@example.com' }));
    expect(res.statusCode).toBe(409);
  });

  it('logs in, and refuses a wrong password', async () => {
    await post('/v1/auth/register', newUser('login'));
    expect((await post('/v1/auth/login', { email: 'login@example.com', password: 'correct-horse-battery' })).statusCode).toBe(200);
    expect((await post('/v1/auth/login', { email: 'login@example.com', password: 'wrong-password-1' })).statusCode).toBe(401);
    expect((await post('/v1/auth/login', { email: 'nobody@example.com', password: 'wrong-password-1' })).statusCode).toBe(401);
  });

  it('protects /v1/me and returns the profile with a token', async () => {
    expect((await app.inject({ method: 'GET', url: '/v1/me' })).statusCode).toBe(401);
    const { accessToken } = (await post('/v1/auth/register', newUser('me'))).json();
    const res = await app.inject({ method: 'GET', url: '/v1/me', headers: { authorization: `Bearer ${accessToken}` } });
    expect(res.statusCode).toBe(200);
    expect(res.json().username).toBe('user_me');
  });

  it('rotates refresh tokens and rejects reuse', async () => {
    const { refreshToken } = (await post('/v1/auth/register', newUser('rot'))).json();
    const first = await post('/v1/auth/refresh', { refreshToken });
    expect(first.statusCode).toBe(200);
    expect((await post('/v1/auth/refresh', { refreshToken })).statusCode).toBe(401);
    expect((await post('/v1/auth/refresh', { refreshToken: first.json().refreshToken })).statusCode).toBe(200);
  });

  it('deletes the account and everything with it', async () => {
    const { accessToken } = (await post('/v1/auth/register', newUser('gone'))).json();
    const del = await app.inject({ method: 'DELETE', url: '/v1/me', headers: { authorization: `Bearer ${accessToken}` } });
    expect(del.statusCode).toBe(204);
    expect((await post('/v1/auth/login', { email: 'gone@example.com', password: 'correct-horse-battery' })).statusCode).toBe(401);
    expect((await app.inject({ method: 'GET', url: '/v1/me', headers: { authorization: `Bearer ${accessToken}` } })).statusCode).toBe(401);
  });
});

describe('artist side', () => {
  const artist = (extra: object = {}) => ({
    stageName: 'Nova Wave',
    artistType: 'solo',
    bio: 'Test artist',
    rightsDeclaration: true,
    agreementVersion: '2026-10',
    ...extra,
  });

  it('upgrades a listener to an artist with both modes', async () => {
    const { accessToken } = (await post('/v1/auth/register', newUser('art1'))).json();
    const res = await post('/v1/artists/me', artist(), accessToken);
    expect(res.statusCode).toBe(201);
    expect(res.json().modes).toEqual(['listener', 'artist']);
    expect(res.json().artist.verified).toBe(false);
    expect((await post('/v1/artists/me', artist({ stageName: 'Second Name' }), accessToken)).statusCode).toBe(409);
  });

  it('blocks a duplicate stage name in any letter case (impersonation guard)', async () => {
    const { accessToken } = (await post('/v1/auth/register', newUser('art2'))).json();
    expect((await post('/v1/artists/me', artist({ stageName: 'NOVA WAVE' }), accessToken)).statusCode).toBe(409);
  });

  it('requires the rights declaration', async () => {
    const { accessToken } = (await post('/v1/auth/register', newUser('art3'))).json();
    expect((await post('/v1/artists/me', artist({ stageName: 'No Rights', rightsDeclaration: false }), accessToken)).statusCode).toBe(400);
  });
});

describe('config', () => {
  it('ships with paywalls off', async () => {
    const res = await app.inject({ method: 'GET', url: '/v1/config' });
    expect(res.json().flags.payments_enforced).toBe(false);
    expect(res.json().flags.youtube_enabled).toBe(true);
  });
});
