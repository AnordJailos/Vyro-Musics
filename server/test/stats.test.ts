import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';
import { memoryDb, type Db } from '../src/db.js';
import { migrate } from '../src/migrate.js';
import { artistStats, personaFromClock, streakFrom } from '../src/stats.js';

const NOW = new Date('2026-10-06T12:00:00Z');
const HOUR = 3_600_000;
const DAY = 86_400_000;

let app: Awaited<ReturnType<typeof buildApp>>;
let db: Db;

const call = (method: 'GET' | 'POST' | 'DELETE', url: string, token?: string, payload?: object) =>
  app.inject({ method, url, payload, headers: token ? { authorization: `Bearer ${token}` } : {} });

async function signUp(name: string, country: string) {
  const res = await call('POST', '/v1/auth/register', undefined, {
    email: `${name}@example.com`,
    password: 'correct-horse-battery',
    displayName: name,
    username: name,
    country,
    acceptedTermsVersion: '2026-10',
  });
  const body = res.json();
  return { id: body.user.id as string, token: body.accessToken as string };
}

const play = (trackId: string, daysAgo: number, listenedMs: number, extra: object = {}) => ({
  id: randomUUID(),
  trackId,
  startedAt: new Date(NOW.getTime() - daysAgo * DAY - 2 * HOUR).toISOString(), // 10:00 UTC
  listenedMs,
  source: 'direct',
  platform: 'android',
  mode: 'normal',
  ...extra,
});

let artist: { id: string; token: string };
let l1: { id: string; token: string };
let l2: { id: string; token: string };
let l3: { id: string; token: string };
let l4: { id: string; token: string };
let t1: string;
let t2: string;

beforeAll(async () => {
  db = await memoryDb();
  await migrate(db);
  app = await buildApp({ db, jwtSecret: 'x'.repeat(40), authRateLimit: 1000, now: () => NOW, minCohort: 1 });

  artist = await signUp('starartist', 'TZ');
  await call('POST', '/v1/artists/me', artist.token, { stageName: 'Stats Star', artistType: 'solo', rightsDeclaration: true, agreementVersion: '2026-10' });
  t1 = (await call('POST', '/v1/artists/me/tracks', artist.token, { title: 'Song One', genre: 'Afrobeats', durationMs: 200_000 })).json().id;
  t2 = (await call('POST', '/v1/artists/me/tracks', artist.token, { title: 'Song Two', genre: 'hiphop', durationMs: 100_000 })).json().id;

  l1 = await signUp('listenerone', 'TZ');
  l2 = await signUp('listenertwo', 'TZ');
  l3 = await signUp('listenerthree', 'KE');
  l4 = await signUp('listenerfour', 'UG');

  const post = (u: { token: string }, events: object[]) => call('POST', '/v1/events/listens', u.token, { events });
  await post(l1, [
    ...[1, 2, 3, 4, 5].map((d) => play(t1, d, 200_000)),
    play(t2, 1, 100_000, { source: 'recommendation', mode: 'mixing', mixedWithTrackId: t1 }),
  ]);
  await post(l2, [play(t1, 2, 120_000), play(t1, 3, 8_000)]);
  await post(l3, [play(t1, 10, 200_000, { source: 'search' })]);
  await post(l4, [play(t1, 40, 200_000), play(t1, 2, 200_000)]);

  await call('POST', `/v1/artists/${artist.id}/follow`, l1.token);
  await call('POST', `/v1/artists/${artist.id}/follow`, l2.token);
  await call('POST', `/v1/tracks/${t1}/save`, l1.token);
}, 60_000);
afterAll(() => app.close());

describe('play ingest', () => {
  it('counts a stream only after 30 seconds, and ignores retries, future plays and unknown tracks', async () => {
    const u = await signUp('ingestuser', 'TZ');
    const events = [play(t2, 100, 10_000), play(t2, 100, 31_000)]; // outside every stats window
    const first = await call('POST', '/v1/events/listens', u.token, { events });
    expect(first.statusCode).toBe(202);
    expect(first.json().accepted).toBe(2);

    const retry = await call('POST', '/v1/events/listens', u.token, { events });
    expect(retry.json()).toEqual({ accepted: 0, ignored: 2 });

    const future = play(t2, -2, 60_000); // two days from now
    const unknown = play(randomUUID(), 1, 60_000);
    const odd = await call('POST', '/v1/events/listens', u.token, { events: [future, unknown] });
    expect(odd.json().accepted).toBe(0);

    const me = (await call('GET', '/v1/me/stats?range=all', u.token)).json();
    expect(me.plays).toBe(1); // only the 31 s play is a valid stream
    await call('DELETE', '/v1/me', u.token);
  });

  it('requires a login', async () => {
    expect((await call('POST', '/v1/events/listens', undefined, { events: [play(t1, 1, 1000)] })).statusCode).toBe(401);
  });
});

describe('artist statistics', () => {
  it('summarizes the period against the one before it', async () => {
    const res = await call('GET', '/v1/artists/me/stats?range=28d', artist.token);
    expect(res.statusCode).toBe(200);
    const s = res.json();
    expect(s.summary.plays).toEqual({ value: 9, previous: 1 });
    expect(s.summary.listeners).toEqual({ value: 4, previous: 1 });
    expect(s.summary.newFollowers.value).toBe(2);
    expect(s.summary.followers).toBe(2);
    expect(s.summary.saves.value).toBe(1);
    expect(s.daily).toHaveLength(28);
    expect(s.daily.reduce((n: number, d: any) => n + d.plays, 0)).toBe(9);
    expect(s.realtime).toHaveLength(48);
  });

  it('splits the audience into new, returning and super listeners', async () => {
    const s = (await call('GET', '/v1/artists/me/stats', artist.token)).json();
    expect(s.audience).toEqual({ newListeners: 3, returningListeners: 1, superListeners: 1 });
  });

  it('breaks plays down by source, country and song', async () => {
    const s = (await call('GET', '/v1/artists/me/stats', artist.token)).json();
    expect(s.sources.find((x: any) => x.source === 'direct').plays).toBe(7);
    expect(s.sources.find((x: any) => x.source === 'search').plays).toBe(1);
    expect(s.countries.find((x: any) => x.country === 'TZ').plays).toBe(7);

    const one = s.songs.find((x: any) => x.title === 'Song One');
    expect(one.plays).toBe(8);
    expect(one.completionRate).toBeCloseTo(0.875, 3); // 7 of 8 streams reached 90%
    expect(one.skipRate).toBeCloseTo(1 / 9, 3);
    expect(one.saves).toBe(1);
  });

  it('shows which songs get mixed together', async () => {
    const s = (await call('GET', '/v1/artists/me/stats', artist.token)).json();
    expect(s.mixedWith[0]).toEqual({ track: 'Song Two', partner: 'Song One', times: 1 });
  });

  it('hides small groups: countries with too few listeners are folded into OTHER', async () => {
    const s = await artistStats(db, artist.id, '28d', NOW, 2);
    expect(s.countries.map((c) => c.country).sort()).toEqual(['OTHER', 'TZ']);
    expect(s.countries.find((c) => c.country === 'OTHER')).toMatchObject({ plays: 2, listeners: 2 });
  });

  it('draws a retention curve that starts at 100% and never rises', async () => {
    const r = (await call('GET', `/v1/artists/me/tracks/${t1}/retention`, artist.token)).json();
    expect(r.points).toHaveLength(11);
    expect(r.points[0]).toEqual({ percent: 0, share: 1 });
    const shares = r.points.map((p: any) => p.share);
    expect([...shares].sort((a, b) => b - a)).toEqual(shares);
    expect(r.points[10].share).toBeCloseTo(7 / 9, 3);
  });

  it('is private to artists, and to their own songs', async () => {
    expect((await call('GET', '/v1/artists/me/stats', l1.token)).statusCode).toBe(403);
    expect((await call('GET', '/v1/artists/me/stats')).statusCode).toBe(401);
    const other = await signUp('otherartist', 'TZ');
    await call('POST', '/v1/artists/me', other.token, { stageName: 'Other Act', artistType: 'solo', rightsDeclaration: true, agreementVersion: '2026-10' });
    expect((await call('GET', `/v1/artists/me/tracks/${t1}/retention`, other.token)).statusCode).toBe(404);
  });
});

describe('public artist profile', () => {
  it('shows monthly listeners, followers and top tracks without a login', async () => {
    const res = await call('GET', `/v1/artists/${artist.id}/public`);
    expect(res.statusCode).toBe(200);
    const p = res.json();
    expect(p).toMatchObject({ stageName: 'Stats Star', monthlyListeners: 4, followers: 2 });
    expect(p.topTracks[0].title).toBe('Song One');
    expect((await call('GET', `/v1/artists/${randomUUID()}/public`)).statusCode).toBe(404);
  });

  it('lets listeners follow and unfollow, but not follow themselves', async () => {
    expect((await call('POST', `/v1/artists/${artist.id}/follow`, artist.token)).statusCode).toBe(400);
    expect((await call('DELETE', `/v1/artists/${artist.id}/follow`, l2.token)).statusCode).toBe(204);
    expect((await call('GET', `/v1/artists/${artist.id}/public`)).json().followers).toBe(1);
    await call('POST', `/v1/artists/${artist.id}/follow`, l2.token);
  });
});

describe('listener profile statistics', () => {
  it('summarizes a listener', async () => {
    const s = (await call('GET', '/v1/me/stats?range=year', l1.token)).json();
    expect(s.minutes).toBe(18);
    expect(s.plays).toBe(6);
    expect(s.songsBlended).toBe(1);
    expect(s.artistsHeard).toBe(1);
    expect(s.newArtists).toBe(1);
    expect(s.streakDays).toBe(5);
    expect(s.persona).toBe('daytime');
    expect(s.topArtists[0]).toMatchObject({ name: 'Stats Star', plays: 6 });
    expect(s.topTracks[0].title).toBe('Song One');
    expect(s.topGenres[0].genre).toBe('afrobeats');
    expect(s.clock[10]).toBe(18);
  });

  it('shifts the listening clock to the listener\'s own time zone', async () => {
    const s = (await call('GET', '/v1/me/stats?range=year&tzOffsetMinutes=180', l1.token)).json();
    expect(s.clock[13]).toBe(18);
    expect(s.clock[10]).toBe(0);
  });

  it('validates the range', async () => {
    expect((await call('GET', '/v1/me/stats?range=forever', l1.token)).statusCode).toBe(400);
  });
});

describe('helpers', () => {
  it('counts listening streaks that end today or yesterday', () => {
    expect(streakFrom(['2026-10-06', '2026-10-05', '2026-10-03'], '2026-10-06')).toBe(2);
    expect(streakFrom(['2026-10-05', '2026-10-04'], '2026-10-06')).toBe(2);
    expect(streakFrom(['2026-10-03'], '2026-10-06')).toBe(0);
    expect(streakFrom([], '2026-10-06')).toBe(0);
  });

  it('names listening personalities', () => {
    const at = (hour: number, minutes: number) => Object.assign(Array.from({ length: 24 }, () => 0), { [hour]: minutes });
    expect(personaFromClock(at(23, 100))).toBe('night_owl');
    expect(personaFromClock(at(6, 100))).toBe('early_bird');
    expect(personaFromClock(at(14, 100))).toBe('daytime');
    expect(personaFromClock(at(19, 100))).toBe('all_day');
    expect(personaFromClock(at(1, 0))).toBe('none');
  });
});
