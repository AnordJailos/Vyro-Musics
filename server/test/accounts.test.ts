import { randomUUID } from 'node:crypto';
import { SignJWT, createLocalJWKSet, exportJWK, generateKeyPair } from 'jose';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { ageOn, agePolicy } from '../src/age.js';
import type { Db } from '../src/db.js';
import { makeSocialVerifier } from '../src/idtokens.js';
import type { MemoryMessenger } from '../src/messaging.js';
import { normalizeName } from '../src/names.js';
import { PASSWORD, api, artistBody, makeApp, registerBody, signUpVerified, type TestApp } from './helpers.js';

let clock = new Date('2026-10-06T12:00:00Z');
let app: TestApp;
let db: Db;
let messenger: MemoryMessenger;
let call: ReturnType<typeof api>['call'];
let sign: (claims: Record<string, unknown>, o?: { audience?: string; subject?: string }) => Promise<string>;

beforeAll(async () => {
  const { privateKey, publicKey } = await generateKeyPair('RS256');
  const jwk = { ...(await exportJWK(publicKey)), kid: 'k1', alg: 'RS256', use: 'sig' };
  sign = (claims, o = {}) =>
    new SignJWT(claims)
      .setProtectedHeader({ alg: 'RS256', kid: 'k1' })
      .setIssuer('https://accounts.google.com')
      .setAudience(o.audience ?? 'google-client')
      .setSubject(o.subject ?? 'g-123')
      .setIssuedAt()
      .setExpirationTime('10m')
      .sign(privateKey);
  const social = makeSocialVerifier({ googleClientIds: ['google-client'], appleClientIds: [], keys: { google: createLocalJWKSet({ keys: [jwk] }) } });
  const made = await makeApp({ now: () => clock, social });
  app = made.app;
  db = made.db;
  messenger = made.messenger;
  call = api(app).call;
}, 60_000);
afterAll(() => app.close());

const wrongCodeFor = (real: string) => String((Number(real) + 1) % 1_000_000).padStart(6, '0');

describe('email check', () => {
  it('confirms the email with the right code', async () => {
    const reg = (await call('POST', '/v1/auth/register', null, registerBody('mail1'))).json();
    expect(reg.user.emailVerified).toBe(false);
    const res = await call('POST', '/v1/auth/email/verify', reg.accessToken, { code: messenger.lastCode('mail1@example.com') });
    expect(res.statusCode).toBe(200);
    expect(res.json().emailVerified).toBe(true);
  });

  it('locks a code after five wrong tries, even for the right code', async () => {
    const reg = (await call('POST', '/v1/auth/register', null, registerBody('mail2'))).json();
    const real = messenger.lastCode('mail2@example.com');
    for (let i = 0; i < 5; i++) {
      const bad = await call('POST', '/v1/auth/email/verify', reg.accessToken, { code: wrongCodeFor(real) });
      expect(bad.json().error).toBe('invalid_code');
    }
    const locked = await call('POST', '/v1/auth/email/verify', reg.accessToken, { code: real });
    expect(locked.statusCode).toBe(400);
    expect(locked.json().error).toBe('too_many_attempts');
  });

  it('expires a code after ten minutes', async () => {
    const reg = (await call('POST', '/v1/auth/register', null, registerBody('mail3'))).json();
    const real = messenger.lastCode('mail3@example.com');
    clock = new Date(clock.getTime() + 11 * 60_000);
    const res = await call('POST', '/v1/auth/email/verify', reg.accessToken, { code: real });
    expect(res.json().error).toBe('code_expired');
    clock = new Date(clock.getTime() + 60 * 60_000); // let the hourly allowance reset for later tests
  });

  it('sends at most five codes an hour, and a new code replaces the old one', async () => {
    const reg = (await call('POST', '/v1/auth/register', null, registerBody('mail4'))).json();
    const first = messenger.lastCode('mail4@example.com');
    for (let i = 0; i < 4; i++) expect((await call('POST', '/v1/auth/email/resend', reg.accessToken)).statusCode).toBe(202);
    expect((await call('POST', '/v1/auth/email/resend', reg.accessToken)).statusCode).toBe(429);
    const latest = messenger.lastCode('mail4@example.com');
    if (latest !== first) {
      expect((await call('POST', '/v1/auth/email/verify', reg.accessToken, { code: first })).statusCode).toBe(400);
    }
    expect((await call('POST', '/v1/auth/email/verify', reg.accessToken, { code: latest })).statusCode).toBe(200);
    expect((await call('POST', '/v1/auth/email/resend', reg.accessToken)).statusCode).toBe(409); // already verified
  });
});

describe('age rules', () => {
  it('turns away children under 13', async () => {
    const res = await call('POST', '/v1/auth/register', null, registerBody('kid', { birthDate: '2014-01-01' }));
    expect(res.statusCode).toBe(403);
    expect(res.json().error).toBe('too_young');
  });

  it('asks for a parent email at 13 to 15, then waits for the parent code', async () => {
    const none = await call('POST', '/v1/auth/register', null, registerBody('teen1', { birthDate: '2012-05-05' }));
    expect(none.json().error).toBe('parent_email_required');
    const same = await call('POST', '/v1/auth/register', null, registerBody('teen1', { birthDate: '2012-05-05', parentEmail: 'TEEN1@example.com' }));
    expect(same.json().error).toBe('parent_email_must_differ');

    const res = await call('POST', '/v1/auth/register', null, registerBody('teen1', { birthDate: '2012-05-05', parentEmail: 'parent1@example.com' }));
    expect(res.statusCode).toBe(201);
    const { user, accessToken } = res.json();
    expect(user).toMatchObject({ isMinor: true, parentConsent: 'pending' });
    expect(user.settings.explicitAllowed).toBe(false);

    const wrong = await call('POST', '/v1/me/parent-consent/confirm', accessToken, { code: wrongCodeFor(messenger.lastCode('parent1@example.com')) });
    expect(wrong.statusCode).toBe(400);
    const ok = await call('POST', '/v1/me/parent-consent/confirm', accessToken, { code: messenger.lastCode('parent1@example.com') });
    expect(ok.json().parentConsent).toBe('granted');
    expect((await call('POST', '/v1/me/parent-consent/confirm', accessToken, { code: '123456' })).statusCode).toBe(409);
  });

  it('keeps explicit content off for anyone under 18, and lets adults choose', async () => {
    const teen = (await call('POST', '/v1/auth/register', null, registerBody('teen2', { birthDate: '2009-03-03' }))).json();
    expect(teen.user.settings.explicitAllowed).toBe(false);
    expect((await call('PATCH', '/v1/me/settings', teen.accessToken, { explicitAllowed: true })).statusCode).toBe(403);

    const adult = await signUpVerified(app, messenger, 'adult1');
    expect((await call('GET', '/v1/me', adult.token)).json().settings.explicitAllowed).toBe(true);
    expect((await call('PATCH', '/v1/me/settings', adult.token, { explicitAllowed: false })).json().settings.explicitAllowed).toBe(false);
    expect((await call('PATCH', '/v1/me/settings', adult.token, { explicitAllowed: true })).statusCode).toBe(200);
  });

  it('keeps under-18s and unconfirmed minors from becoming artists', async () => {
    const t17 = (await call('POST', '/v1/auth/register', null, registerBody('teen3', { birthDate: '2009-03-03' }))).json();
    await call('POST', '/v1/auth/email/verify', t17.accessToken, { code: messenger.lastCode('teen3@example.com') });
    const a = await call('POST', '/v1/artists/me', t17.accessToken, artistBody({ stageName: 'Teen Act' }));
    expect(a.json().error).toBe('artist_requires_adult');

    const t14 = (await call('POST', '/v1/auth/register', null, registerBody('teen4', { birthDate: '2012-05-05', parentEmail: 'parent4@example.com' }))).json();
    await call('POST', '/v1/auth/email/verify', t14.accessToken, { code: messenger.lastCode('teen4@example.com') });
    const b = await call('POST', '/v1/artists/me', t14.accessToken, artistBody({ stageName: 'Younger Act' }));
    expect(b.json().error).toBe('parent_consent_pending');
  });

  it('calculates age and policy correctly around birthdays', () => {
    const now = new Date('2026-10-06T12:00:00Z');
    expect(ageOn('2013-10-06', now)).toBe(13);
    expect(ageOn('2013-10-07', now)).toBe(12);
    expect(agePolicy(12).allowed).toBe(false);
    expect(agePolicy(15)).toMatchObject({ allowed: true, needsParent: true, minor: true, explicitAllowed: false });
    expect(agePolicy(16)).toMatchObject({ needsParent: false, minor: true });
    expect(agePolicy(18)).toMatchObject({ minor: false, explicitAllowed: true });
  });
});

describe('phone number sign-in', () => {
  const number = '+14155550123';

  it('signs a new person up with a code, then signs them in again', async () => {
    expect((await call('POST', '/v1/auth/phone/request', null, { phone: '12345' })).statusCode).toBe(400);
    expect((await call('POST', '/v1/auth/phone/request', null, { phone: '+1 (415) 555-0123' })).statusCode).toBe(202);
    const code = messenger.lastCode(number);

    expect((await call('POST', '/v1/auth/phone/verify', null, { phone: number, code: wrongCodeFor(code) })).json().error).toBe('invalid_code');
    const verified = (await call('POST', '/v1/auth/phone/verify', null, { phone: number, code })).json();
    expect(verified.needsProfile).toBe(true);

    expect((await call('POST', '/v1/auth/complete-profile', null, { signupToken: 'x'.repeat(30), ...registerBody('ph1'), email: undefined, password: undefined })).statusCode).toBe(401);

    const done = await call('POST', '/v1/auth/complete-profile', null, {
      signupToken: verified.signupToken,
      displayName: 'Phone User',
      username: 'phone_user',
      birthDate: '1992-02-02',
      acceptedTermsVersion: '2026-10',
    });
    expect(done.statusCode).toBe(201);
    expect(done.json().user).toMatchObject({ phone: number, phoneVerified: true, email: null, hasPassword: false });

    await call('POST', '/v1/auth/phone/request', null, { phone: number });
    const again = (await call('POST', '/v1/auth/phone/verify', null, { phone: number, code: messenger.lastCode(number) })).json();
    expect(again.accessToken).toBeTruthy();
    expect(again.user.username).toBe('phone_user');
  });

  it('does not accept an access token as a sign-up pass', async () => {
    const u = await signUpVerified(app, messenger, 'ph2');
    const res = await call('POST', '/v1/auth/complete-profile', null, { signupToken: u.token, displayName: 'X', username: 'phone_x', birthDate: '1990-01-01', acceptedTermsVersion: '2026-10' });
    expect(res.statusCode).toBe(401);
  });

  it('lets a phone-only account delete itself with just the typed word', async () => {
    const n = '+442071838750';
    await call('POST', '/v1/auth/phone/request', null, { phone: n });
    const v = (await call('POST', '/v1/auth/phone/verify', null, { phone: n, code: messenger.lastCode(n) })).json();
    const made = (await call('POST', '/v1/auth/complete-profile', null, { signupToken: v.signupToken, displayName: 'Del', username: 'phone_del', birthDate: '1990-01-01', acceptedTermsVersion: '2026-10' })).json();
    expect((await call('POST', '/v1/me/delete', made.accessToken, { confirm: 'DELETE' })).statusCode).toBe(204);
  });
});

describe('Google sign-in', () => {
  it('is switched off for providers without client IDs', async () => {
    const res = await call('POST', '/v1/auth/social', null, { provider: 'apple', idToken: 'x'.repeat(40) });
    expect(res.statusCode).toBe(501);
  });

  it('refuses tokens for another app, bad tokens, and unchecked emails', async () => {
    expect((await call('POST', '/v1/auth/social', null, { provider: 'google', idToken: await sign({ email: 'a@x.com', email_verified: true }, { audience: 'someone-else' }) })).statusCode).toBe(401);
    expect((await call('POST', '/v1/auth/social', null, { provider: 'google', idToken: 'not-a-token-at-all-but-long-enough' })).statusCode).toBe(401);
    const unchecked = await call('POST', '/v1/auth/social', null, { provider: 'google', idToken: await sign({ email: 'a@x.com', email_verified: false }, { subject: 'g-unchecked' }) });
    expect(unchecked.statusCode).toBe(403);
  });

  it('creates an account, then signs the same person in directly', async () => {
    const token = await sign({ email: 'Gina@Example.com', email_verified: true }, { subject: 'g-gina' });
    const first = (await call('POST', '/v1/auth/social', null, { provider: 'google', idToken: token })).json();
    expect(first.needsProfile).toBe(true);
    expect(first.suggestedEmail).toBe('gina@example.com');

    const done = await call('POST', '/v1/auth/complete-profile', null, { signupToken: first.signupToken, displayName: 'Gina', username: 'gina_g', birthDate: '1995-05-05', acceptedTermsVersion: '2026-10' });
    expect(done.statusCode).toBe(201);
    expect(done.json().user).toMatchObject({ email: 'gina@example.com', emailVerified: true, hasPassword: false });

    const again = (await call('POST', '/v1/auth/social', null, { provider: 'google', idToken: token })).json();
    expect(again.user.username).toBe('gina_g');
  });

  it('links to an existing account that has the same checked email', async () => {
    const existing = await signUpVerified(app, messenger, 'linkme');
    const res = (await call('POST', '/v1/auth/social', null, { provider: 'google', idToken: await sign({ email: 'linkme@example.com', email_verified: true }, { subject: 'g-link' }) })).json();
    expect(res.user.id).toBe(existing.id);
  });
});

describe('password reset', () => {
  it('says the same thing whether or not the account exists, and sends no mail for strangers', async () => {
    const before = messenger.sent.length;
    expect((await call('POST', '/v1/auth/password-reset/request', null, { email: 'nobody-here@example.com' })).statusCode).toBe(202);
    expect(messenger.sent.length).toBe(before);
  });

  it('sets a new password with the emailed code and signs out every device', async () => {
    const u = await signUpVerified(app, messenger, 'reset1');
    expect((await call('POST', '/v1/auth/password-reset/request', null, { email: 'RESET1@example.com' })).statusCode).toBe(202);
    const code = messenger.lastCode('reset1@example.com');

    const bad = await call('POST', '/v1/auth/password-reset/confirm', null, { email: u.email, code: wrongCodeFor(code), newPassword: 'a-brand-new-password' });
    expect(bad.statusCode).toBe(400);
    const ok = await call('POST', '/v1/auth/password-reset/confirm', null, { email: u.email, code, newPassword: 'a-brand-new-password' });
    expect(ok.statusCode).toBe(204);

    expect((await call('POST', '/v1/auth/login', null, { email: u.email, password: PASSWORD })).statusCode).toBe(401);
    expect((await call('POST', '/v1/auth/login', null, { email: u.email, password: 'a-brand-new-password' })).statusCode).toBe(200);
    expect((await call('POST', '/v1/auth/refresh', null, { refreshToken: u.refreshToken })).statusCode).toBe(401);
    expect((await call('POST', '/v1/auth/password-reset/confirm', null, { email: u.email, code, newPassword: 'another-new-password' })).statusCode).toBe(400); // code already used
  });
});

describe('privacy and taste', () => {
  it('keeps plays from private sessions for the artist but not for the listener', async () => {
    const artist = await signUpVerified(app, messenger, 'privart');
    await call('POST', '/v1/artists/me', artist.token, artistBody({ stageName: 'Private Test Act' }));
    const track = (await call('POST', '/v1/artists/me/tracks', artist.token, { title: 'T', durationMs: 120_000 })).json().id as string;
    const listener = await signUpVerified(app, messenger, 'privlisten');
    const play = () => ({ id: randomUUID(), trackId: track, startedAt: new Date(clock.getTime() - 3_600_000).toISOString(), listenedMs: 100_000, source: 'direct', platform: 'android', mode: 'normal' });

    const normal = play();
    await call('POST', '/v1/events/listens', listener.token, { events: [normal] });
    await call('PATCH', '/v1/me/settings', listener.token, { privateSession: true });
    const priv = play();
    await call('POST', '/v1/events/listens', listener.token, { events: [priv] });

    const owner = async (id: string) => (await db.query<{ user_id: string | null }>('select user_id from listen_events where id = $1', [id])).rows[0]!.user_id;
    expect(await owner(normal.id)).toBe(listener.id);
    expect(await owner(priv.id)).toBeNull();
    const plays = (await db.query<{ n: number }>('select count(*)::int as n from listen_events where track_id = $1 and valid', [track])).rows[0]!.n;
    expect(plays).toBe(2); // both count for the artist
  });

  it('stores the taste picks, follows the chosen artists and ignores unknown ones', async () => {
    const artist = await signUpVerified(app, messenger, 'tasteart');
    await call('POST', '/v1/artists/me', artist.token, artistBody({ stageName: 'Taste Test Act' }));
    const u = await signUpVerified(app, messenger, 'tasteuser');
    expect((await call('GET', '/v1/me', u.token)).json().tasteSet).toBe(false);

    const suggested = (await call('GET', '/v1/artists/suggested', u.token)).json().artists as { id: string; stageName: string }[];
    expect(suggested.some((a) => a.id === artist.id)).toBe(true);
    expect((await call('GET', '/v1/artists/suggested', artist.token)).json().artists.some((a: { id: string }) => a.id === artist.id)).toBe(false);

    const res = await call('PUT', '/v1/me/taste', u.token, { genres: ['Afrobeats', 'Gospel'], moods: ['Chill'], artistIds: [artist.id, randomUUID()] });
    expect(res.json().tasteSet).toBe(true);
    const follows = (await db.query<{ n: number }>('select count(*)::int as n from follows where user_id = $1', [u.id])).rows[0]!.n;
    expect(follows).toBe(1);
  });
});

describe('helpers', () => {
  it('turns look-alike names into the same key', () => {
    expect(normalizeName('Nova  Wave!')).toBe(normalizeName('nova-wave'));
    expect(normalizeName('Ñandú')).toBe(normalizeName('nandu'));
    expect(normalizeName('مرحبا')).not.toBe(''); // names in other scripts keep their letters
    expect(normalizeName('مرحبا')).not.toBe(normalizeName('سلام'));
  });
});
