import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { PASSWORD, api, artistBody, makeApp, registerBody, signUpVerified, type TestApp } from './helpers.js';
import type { MemoryMessenger } from '../src/messaging.js';

let app: TestApp;
let messenger: MemoryMessenger;
let call: ReturnType<typeof api>['call'];

beforeAll(async () => {
  const made = await makeApp();
  app = made.app;
  messenger = made.messenger;
  call = api(app).call;
}, 60_000);
afterAll(() => app.close());

describe('accounts', () => {
  it('registers a listener, normalizes the email and records the consent', async () => {
    const res = await call('POST', '/v1/auth/register', null, registerBody('amani'));
    expect(res.statusCode).toBe(201);
    const body = res.json();
    expect(body.user.email).toBe('amani@example.com');
    expect(body.user.modes).toEqual(['listener']);
    expect(body.user.emailVerified).toBe(false);
    expect(body.user.isMinor).toBe(false);
    expect(body.accessToken).toBeTruthy();
    expect(messenger.sent.some((m) => m.to === 'amani@example.com' && m.channel === 'email')).toBe(true);
  });

  it('rejects weak passwords, bad usernames and a missing birth date', async () => {
    expect((await call('POST', '/v1/auth/register', null, registerBody('weak', { password: 'short' }))).statusCode).toBe(400);
    expect((await call('POST', '/v1/auth/register', null, registerBody('bad', { username: 'Bad Name!' }))).statusCode).toBe(400);
    expect((await call('POST', '/v1/auth/register', null, registerBody('nodob', { birthDate: undefined }))).statusCode).toBe(400);
  });

  it('rejects a duplicate email regardless of case', async () => {
    await call('POST', '/v1/auth/register', null, registerBody('dup'));
    const res = await call('POST', '/v1/auth/register', null, registerBody('other', { email: 'DUP@example.com' }));
    expect(res.statusCode).toBe(409);
  });

  it('logs in, and refuses a wrong password', async () => {
    await call('POST', '/v1/auth/register', null, registerBody('login'));
    expect((await call('POST', '/v1/auth/login', null, { email: 'login@example.com', password: PASSWORD })).statusCode).toBe(200);
    expect((await call('POST', '/v1/auth/login', null, { email: 'login@example.com', password: 'wrong-password-1' })).statusCode).toBe(401);
    expect((await call('POST', '/v1/auth/login', null, { email: 'nobody@example.com', password: 'wrong-password-1' })).statusCode).toBe(401);
  });

  it('protects /v1/me and returns the profile with a token', async () => {
    expect((await call('GET', '/v1/me')).statusCode).toBe(401);
    const { accessToken } = (await call('POST', '/v1/auth/register', null, registerBody('me'))).json();
    const res = await call('GET', '/v1/me', accessToken);
    expect(res.statusCode).toBe(200);
    expect(res.json().username).toBe('user_me');
  });

  it('rotates refresh tokens and rejects reuse', async () => {
    const { refreshToken } = (await call('POST', '/v1/auth/register', null, registerBody('rot'))).json();
    const first = await call('POST', '/v1/auth/refresh', null, { refreshToken });
    expect(first.statusCode).toBe(200);
    expect((await call('POST', '/v1/auth/refresh', null, { refreshToken })).statusCode).toBe(401);
    expect((await call('POST', '/v1/auth/refresh', null, { refreshToken: first.json().refreshToken })).statusCode).toBe(200);
  });

  it('deletes the account only with the typed word and the password', async () => {
    const { accessToken } = (await call('POST', '/v1/auth/register', null, registerBody('gone'))).json();
    expect((await call('POST', '/v1/me/delete', accessToken, { confirm: 'DELETE' })).statusCode).toBe(403); // password missing
    expect((await call('POST', '/v1/me/delete', accessToken, { confirm: 'DELETE', password: 'wrong-password-1' })).statusCode).toBe(403);
    expect((await call('POST', '/v1/me/delete', accessToken, { password: PASSWORD })).statusCode).toBe(400); // typed word missing
    expect((await call('POST', '/v1/me/delete', accessToken, { confirm: 'DELETE', password: PASSWORD })).statusCode).toBe(204);
    expect((await call('POST', '/v1/auth/login', null, { email: 'gone@example.com', password: PASSWORD })).statusCode).toBe(401);
    expect((await call('GET', '/v1/me', accessToken)).statusCode).toBe(401);
  });

  it('edits the profile, and refuses a username that is taken', async () => {
    const a = await signUpVerified(app, messenger, 'edita');
    await signUpVerified(app, messenger, 'editb');
    const ok = await call('PATCH', '/v1/me', a.token, { displayName: 'Anna', language: 'sw', country: 'ke' });
    expect(ok.json()).toMatchObject({ displayName: 'Anna', language: 'sw', country: 'KE' });
    expect((await call('PATCH', '/v1/me', a.token, { username: 'user_editb' })).statusCode).toBe(409);
  });
});

describe('artist side', () => {
  it('upgrades a verified listener to an artist with both modes', async () => {
    const u = await signUpVerified(app, messenger, 'art1');
    const res = await call('POST', '/v1/artists/me', u.token, artistBody({ genres: ['Afrobeats'], links: ['https://example.com/me'] }));
    expect(res.statusCode).toBe(201);
    expect(res.json().modes).toEqual(['listener', 'artist']);
    expect(res.json().artist).toMatchObject({ verified: false, genres: ['afrobeats'] });
    expect((await call('POST', '/v1/artists/me', u.token, artistBody({ stageName: 'Second Name' }))).statusCode).toBe(409);
  });

  it('blocks look-alike stage names (case, spaces and punctuation)', async () => {
    const u = await signUpVerified(app, messenger, 'art2');
    for (const name of ['NOVA WAVE', 'nova-wave', 'Nova  Wave!']) {
      const res = await call('POST', '/v1/artists/me', u.token, artistBody({ stageName: name }));
      expect(res.statusCode, name).toBe(409);
      expect(res.json().error).toBe('stage_name_taken');
    }
  });

  it('requires the rights declaration and a verified email or phone', async () => {
    const u = await signUpVerified(app, messenger, 'art3');
    expect((await call('POST', '/v1/artists/me', u.token, artistBody({ stageName: 'No Rights', rightsDeclaration: false }))).statusCode).toBe(400);
    const raw = (await call('POST', '/v1/auth/register', null, registerBody('art4'))).json();
    const res = await call('POST', '/v1/artists/me', raw.accessToken, artistBody({ stageName: 'Unverified Act' }));
    expect(res.statusCode).toBe(403);
    expect(res.json().error).toBe('verify_contact_first');
  });

  it('lets an artist update the bio, genres and links', async () => {
    const u = await signUpVerified(app, messenger, 'art5');
    await call('POST', '/v1/artists/me', u.token, artistBody({ stageName: 'Patch Act' }));
    const res = await call('PATCH', '/v1/artists/me', u.token, { bio: 'New bio', genres: ['Hip-Hop'] });
    expect(res.json().artist).toMatchObject({ bio: 'New bio', genres: ['hip-hop'] });
    const listener = await signUpVerified(app, messenger, 'art6');
    expect((await call('PATCH', '/v1/artists/me', listener.token, { bio: 'x' })).statusCode).toBe(404);
  });
});

describe('config', () => {
  it('ships with paywalls off', async () => {
    const res = await call('GET', '/v1/config');
    expect(res.json().flags.payments_enforced).toBe(false);
    expect(res.json().flags.youtube_enabled).toBe(true);
  });
});
