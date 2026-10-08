import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { FfmpegTranscoder, qualityProblem } from '../src/audio.js';
import { parseRange } from '../src/catalog_routes.js';
import type { Db } from '../src/db.js';
import type { MemoryMessenger } from '../src/messaging.js';
import { signStreamToken, verifyStreamToken } from '../src/security.js';
import { fakePng, makeMp3, makeWav } from './audio_fixtures.js';
import { api, artistBody, makeApp, signUpVerified, type TestApp } from './helpers.js';

const hasFfmpeg = (await FfmpegTranscoder.detect()) !== null;

let clock = new Date('2026-10-06T12:00:00Z');
let app: TestApp;
let db: Db;
let messenger: MemoryMessenger;
let cleanup: () => void;
let call: ReturnType<typeof api>['call'];

type Account = { id: string; token: string };
let artist: Account;
let other: Account;
let listener: Account;
let wav: Buffer;

const put = (url: string, token: string, body: Buffer | string, type = 'audio/wav') =>
  app.inject({ method: 'PUT', url, payload: body, headers: { authorization: `Bearer ${token}`, 'content-type': type } });

async function newTrack(who: Account, title: string, extra: object = {}) {
  const res = await call('POST', '/v1/artists/me/tracks', who.token, { title, genre: 'Afrobeats', ...extra });
  expect(res.statusCode).toBe(201);
  return res.json().id as string;
}

/** Creates a song, uploads audio and publishes it. */
async function publishedTrack(who: Account, title: string, extra: object = {}) {
  const id = await newTrack(who, title, extra);
  expect((await put(`/v1/artists/me/tracks/${id}/audio`, who.token, wav)).statusCode).toBe(200);
  expect((await call('POST', `/v1/artists/me/tracks/${id}/publish`, who.token)).statusCode).toBe(200);
  return id;
}

beforeAll(async () => {
  const made = await makeApp({ now: () => clock, minCohort: 1 });
  ({ app, db, messenger, cleanup } = made);
  call = api(app).call;
  wav = makeWav(12);
  artist = await signUpVerified(app, messenger, 'cat_artist', { country: 'KE' });
  await call('POST', '/v1/artists/me', artist.token, artistBody({ stageName: 'Catalog Star' }));
  other = await signUpVerified(app, messenger, 'cat_other');
  await call('POST', '/v1/artists/me', other.token, artistBody({ stageName: 'Other Voice' }));
  listener = await signUpVerified(app, messenger, 'cat_listener', { country: 'KE' });
}, 60_000);
afterAll(async () => {
  await app.close();
  cleanup();
});

describe('uploading a song', () => {
  it('accepts a lossless file, measures it and prepares it for streaming', async () => {
    const id = await newTrack(artist, 'Upload One');
    const res = await put(`/v1/artists/me/tracks/${id}/audio`, artist.token, wav);
    expect(res.statusCode).toBe(200);
    const t = res.json();
    expect(t).toMatchObject({ status: 'ready', hasAudio: true, lossless: true, sampleRate: 22_050 });
    expect(Math.abs(t.durationMs - 12_000)).toBeLessThan(100);
    if (hasFfmpeg) {
      expect(typeof t.loudnessLufs).toBe('number');
      const row = (await db.query<any>('select stream_mime, stream_bytes, audio_bytes from tracks where id = $1', [id])).rows[0];
      expect(row.stream_mime).toBe('audio/mp4');
      expect(row.stream_bytes).toBeLessThan(row.audio_bytes); // the streaming copy is smaller than the master
    }
  });

  it('refuses files that are not audio, and files that are too short', async () => {
    const id = await newTrack(artist, 'Bad Uploads');
    const text = await put(`/v1/artists/me/tracks/${id}/audio`, artist.token, 'this is not music at all', 'audio/mpeg');
    expect(text.statusCode).toBe(415);
    expect(text.json().error).toBe('unsupported_audio');
    const short = await put(`/v1/artists/me/tracks/${id}/audio`, artist.token, makeWav(3));
    expect(short.statusCode).toBe(422);
    expect(short.json().error).toBe('too_short');
    const row = (await call('GET', '/v1/artists/me/tracks', artist.token)).json().tracks.find((t: any) => t.id === id);
    expect(row).toMatchObject({ hasAudio: false, status: 'draft' });
  });

  it('refuses files over the size limit', async () => {
    const small = await makeApp({ maxAudioBytes: 1000 });
    try {
      const a = await signUpVerified(small.app, small.messenger, 'big_artist');
      const c = api(small.app).call;
      await c('POST', '/v1/artists/me', a.token, artistBody({ stageName: 'Big File Act' }));
      const id = (await c('POST', '/v1/artists/me/tracks', a.token, { title: 'Big' })).json().id;
      const res = await small.app.inject({ method: 'PUT', url: `/v1/artists/me/tracks/${id}/audio`, payload: wav, headers: { authorization: `Bearer ${a.token}`, 'content-type': 'audio/wav' } });
      expect(res.statusCode).toBe(413);
    } finally {
      await small.app.close();
      small.cleanup();
    }
  });

  it('keeps songs private to their artist', async () => {
    const id = await newTrack(artist, 'Mine Only');
    expect((await put(`/v1/artists/me/tracks/${id}/audio`, other.token, wav)).statusCode).toBe(404);
    expect((await call('PATCH', `/v1/artists/me/tracks/${id}`, other.token, { title: 'Stolen' })).statusCode).toBe(404);
    expect((await call('POST', `/v1/artists/me/tracks/${id}/publish`, other.token)).statusCode).toBe(404);
    expect((await put(`/v1/artists/me/tracks/${id}/audio`, listener.token, wav)).statusCode).toBe(403); // not an artist
  });

  it('takes a cover picture, and refuses other files', async () => {
    const id = await newTrack(artist, 'With Cover');
    expect((await put(`/v1/artists/me/tracks/${id}/cover`, artist.token, 'plain text', 'image/png')).statusCode).toBe(415);
    const ok = await put(`/v1/artists/me/tracks/${id}/cover`, artist.token, fakePng, 'image/png');
    expect(ok.statusCode).toBe(200);
    expect(ok.json().hasCover).toBe(true);
    expect((await call('GET', `/v1/tracks/${id}/cover`)).statusCode).toBe(404); // a draft's cover is private
    const own = await call('GET', `/v1/tracks/${id}/cover`, artist.token);
    expect(own.statusCode).toBe(200);
    expect(own.headers['content-type']).toBe('image/png');
    expect(own.rawPayload.length).toBe(fakePng.length);
  });

  it('applies the quality gates', () => {
    const base = { codec: 'mp3', durationMs: 60_000, bitrateKbps: 192, sampleRate: 44_100, lossless: false };
    expect(qualityProblem(base)).toBeNull();
    expect(qualityProblem({ ...base, durationMs: 5_000 })).toBe('too_short');
    expect(qualityProblem({ ...base, durationMs: 7 * 3600_000 })).toBe('too_long');
    expect(qualityProblem({ ...base, bitrateKbps: 96 })).toBe('bitrate_too_low');
    expect(qualityProblem({ ...base, lossless: true, bitrateKbps: 700, sampleRate: 8_000 })).toBe('sample_rate_too_low');
    expect(qualityProblem({ ...base, lossless: true, bitrateKbps: 700 })).toBeNull();
  });
});

describe.skipIf(!hasFfmpeg)('MP3 uploads (needs ffmpeg)', () => {
  it('accepts a good MP3 as it is, without re-encoding it', async () => {
    const id = await newTrack(artist, 'Real Mp3');
    const res = await put(`/v1/artists/me/tracks/${id}/audio`, artist.token, await makeMp3(192), 'audio/mpeg');
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ lossless: false, status: 'ready' });
    expect(res.json().bitrateKbps).toBeGreaterThanOrEqual(190);
    const row = (await db.query<any>('select stream_key, audio_mime from tracks where id = $1', [id])).rows[0];
    expect(row.stream_key).toBeNull();
    expect(row.audio_mime).toBe('audio/mpeg');
  });

  it('refuses a low-quality MP3', async () => {
    const id = await newTrack(artist, 'Low Mp3');
    const res = await put(`/v1/artists/me/tracks/${id}/audio`, artist.token, await makeMp3(64), 'audio/mpeg');
    expect(res.statusCode).toBe(422);
    expect(res.json().error).toBe('bitrate_too_low');
  });
});

describe('publishing and finding songs', () => {
  it('needs audio before publishing, then shows the song to everyone, and hides it again when unpublished', async () => {
    const id = await newTrack(artist, 'Fresh Release');
    const early = await call('POST', `/v1/artists/me/tracks/${id}/publish`, artist.token);
    expect(early.statusCode).toBe(409);
    expect(early.json().error).toBe('upload_audio_first');

    await put(`/v1/artists/me/tracks/${id}/audio`, artist.token, wav);
    const live = await call('POST', `/v1/artists/me/tracks/${id}/publish`, artist.token);
    expect(live.json()).toMatchObject({ status: 'published' });
    expect(live.json().publishedAt).toBeTruthy();

    const fresh = (await call('GET', '/v1/catalog/new')).json().tracks;
    expect(fresh[0]).toMatchObject({ id, title: 'Fresh Release', artist: { stageName: 'Catalog Star' } });
    expect((await call('GET', `/v1/tracks/${id}`)).json().coverUrl).toBeNull();

    await call('POST', `/v1/artists/me/tracks/${id}/unpublish`, artist.token);
    expect((await call('GET', '/v1/catalog/new')).json().tracks.some((t: any) => t.id === id)).toBe(false);
    expect((await call('GET', `/v1/tracks/${id}`)).statusCode).toBe(404);
    expect((await call('GET', `/v1/tracks/${id}`, artist.token)).statusCode).toBe(200); // the artist can still see it
  });

  it('searches by song title or artist name, with prefix matches first, and treats % as plain text', async () => {
    await publishedTrack(artist, 'Sunrise Drive');
    await publishedTrack(other, 'Night Sunrise');
    await publishedTrack(other, 'Zebra');
    const byTitle = (await call('GET', '/v1/catalog/search?q=sunrise')).json().tracks.map((t: any) => t.title);
    expect(byTitle).toEqual(['Sunrise Drive', 'Night Sunrise']);
    const byArtist = (await call('GET', '/v1/catalog/search?q=other%20voice')).json().tracks.map((t: any) => t.title);
    expect(byArtist).toContain('Zebra');
    expect((await call('GET', '/v1/catalog/search?q=%25')).json().tracks).toEqual([]);
    expect((await call('GET', '/v1/catalog/search?q=')).statusCode).toBe(400);
  });

  it('hides explicit songs from guests and minors, and plays them for adults who allow them', async () => {
    const id = await publishedTrack(artist, 'Rated Explicit', { explicit: true });
    const titles = async (token?: string) => (await call('GET', '/v1/catalog/search?q=rated%20explicit', token)).json().tracks.map((t: any) => t.title);
    expect(await titles()).toEqual([]);
    expect(await titles(listener.token)).toEqual(['Rated Explicit']);

    const teen = (await call('POST', '/v1/auth/register', null, { email: 'teen_cat@example.com', password: 'correct-horse-battery', displayName: 'Teen', username: 'teen_cat', birthDate: '2009-03-03', acceptedTermsVersion: '2026-10' })).json();
    expect(await titles(teen.accessToken)).toEqual([]);

    expect((await call('GET', `/v1/tracks/${id}/stream-url`)).json().error).toBe('explicit_not_allowed');
    expect((await call('GET', `/v1/tracks/${id}/stream-url`, listener.token)).statusCode).toBe(200);
  });

  it('removes a song completely, but keeps its past plays for the artist\'s statistics', async () => {
    const id = await publishedTrack(artist, 'To Be Removed');
    await call('POST', '/v1/events/listens', listener.token, {
      events: [{ id: randomUUID(), trackId: id, startedAt: new Date(clock.getTime() - 3600_000).toISOString(), listenedMs: 11_000, source: 'direct', platform: 'android', mode: 'normal' }],
    });
    const url = (await call('GET', `/v1/tracks/${id}/stream-url`)).json().url as string;
    expect((await call('GET', url)).statusCode).toBe(200);

    expect((await call('DELETE', `/v1/artists/me/tracks/${id}`, artist.token)).statusCode).toBe(204);
    expect((await call('GET', url)).statusCode).toBe(404);
    expect((await call('GET', `/v1/tracks/${id}`, artist.token)).statusCode).toBe(404);
    expect((await call('GET', '/v1/artists/me/tracks', artist.token)).json().tracks.some((t: any) => t.id === id)).toBe(false);
    const kept = (await db.query<{ n: number }>('select count(*)::int as n from listen_events where track_id = $1', [id])).rows[0]!.n;
    expect(kept).toBe(1);
  });

  it('ranks the charts by plays, worldwide or for one country', async () => {
    const hit = await publishedTrack(artist, 'Chart Hit');
    const quiet = await publishedTrack(other, 'Chart Quiet');
    const play = (trackId: string) => ({ id: randomUUID(), trackId, startedAt: new Date(clock.getTime() - 2 * 3600_000).toISOString(), listenedMs: 11_000, source: 'chart', platform: 'ios', mode: 'normal' });
    await call('POST', '/v1/events/listens', listener.token, { events: [play(hit), play(hit), play(quiet)] }); // listener is in KE
    const world = (await call('GET', '/v1/catalog/charts?range=7d')).json();
    const top = world.tracks.slice(0, 2);
    expect(top.map((t: any) => [t.title, t.plays, t.rank])).toEqual([['Chart Hit', 2, 1], ['Chart Quiet', 1, 2]]);
    const ke = (await call('GET', '/v1/catalog/charts?country=ke')).json().tracks;
    expect(ke[0].title).toBe('Chart Hit');
    const none = (await call('GET', '/v1/catalog/charts?country=NG')).json().tracks;
    expect(none.every((t: any) => t.plays === 0)).toBe(true);
  });
});

describe('streaming', () => {
  let id: string;
  let url: string;
  let size: number;

  beforeAll(async () => {
    id = await publishedTrack(artist, 'Streamable');
    url = (await call('GET', `/v1/tracks/${id}/stream-url`)).json().url;
    size = (await call('GET', url)).rawPayload.length;
  });

  it('gives a signed address that works without logging in, and plays the whole file', async () => {
    expect(url).toMatch(/^\/v1\/stream\//);
    const res = await call('GET', url);
    expect(res.statusCode).toBe(200);
    expect(res.headers['accept-ranges']).toBe('bytes');
    expect(Number(res.headers['content-length'])).toBe(size);
    expect(res.headers['content-type']).toBe(hasFfmpeg ? 'audio/mp4' : 'audio/wav');
  });

  it('serves byte ranges so players can seek', async () => {
    const get = (range: string) => app.inject({ method: 'GET', url, headers: { range } });
    const first = await get('bytes=0-99');
    expect(first.statusCode).toBe(206);
    expect(first.headers['content-range']).toBe(`bytes 0-99/${size}`);
    expect(first.rawPayload.length).toBe(100);

    const tail = await get('bytes=-50');
    expect(tail.statusCode).toBe(206);
    expect(tail.rawPayload.length).toBe(50);
    expect(tail.headers['content-range']).toBe(`bytes ${size - 50}-${size - 1}/${size}`);

    const open = await get('bytes=100-');
    expect(open.rawPayload.length).toBe(size - 100);
    expect((await get(`bytes=${size + 5}-`)).statusCode).toBe(416);
    expect((await get('bytes=abc')).statusCode).toBe(416);

    const whole = (await call('GET', url)).rawPayload;
    expect(first.rawPayload.equals(whole.subarray(0, 100))).toBe(true);
  });

  it('refuses a tampered or expired address', async () => {
    const parts = url.split('.');
    parts[parts.length - 1] = 'A'.repeat(parts[parts.length - 1]!.length);
    expect((await call('GET', parts.join('.'))).statusCode).toBe(403);
    const before = clock;
    clock = new Date(clock.getTime() + 61 * 60_000);
    expect((await call('GET', url)).statusCode).toBe(403);
    clock = before;
    expect((await call('GET', url)).statusCode).toBe(200);
  });

  it('keeps unpublished songs for their artist only', async () => {
    const draft = await newTrack(artist, 'Draft Only');
    await put(`/v1/artists/me/tracks/${draft}/audio`, artist.token, wav);
    expect((await call('GET', `/v1/tracks/${draft}/stream-url`)).statusCode).toBe(404);
    expect((await call('GET', `/v1/tracks/${draft}/stream-url`, other.token)).statusCode).toBe(404);
    expect((await call('GET', `/v1/tracks/${draft}/stream-url`, artist.token)).statusCode).toBe(200);
  });

  it('has nothing to stream before audio is uploaded', async () => {
    const empty = await newTrack(artist, 'No Audio Yet');
    expect((await call('GET', `/v1/tracks/${empty}/stream-url`, artist.token)).statusCode).toBe(404);
  });
});

describe('helpers', () => {
  it('reads byte-range headers', () => {
    expect(parseRange(undefined, 1000)).toBeNull();
    expect(parseRange('bytes=0-99', 1000)).toEqual({ start: 0, end: 99 });
    expect(parseRange('bytes=900-', 1000)).toEqual({ start: 900, end: 999 });
    expect(parseRange('bytes=-100', 1000)).toEqual({ start: 900, end: 999 });
    expect(parseRange('bytes=0-5000', 1000)).toEqual({ start: 0, end: 999 });
    expect(parseRange('bytes=1000-', 1000)).toBe('invalid');
    expect(parseRange('bytes=-', 1000)).toBe('invalid');
    expect(parseRange('items=0-1', 1000)).toBe('invalid');
  });

  it('signs and checks stream tokens', () => {
    const token = signStreamToken('secret', 'track-1', 2_000);
    expect(verifyStreamToken('secret', token, 1_000)).toEqual({ trackId: 'track-1' });
    expect(verifyStreamToken('secret', token, 2_000)).toBeNull();
    expect(verifyStreamToken('other-secret', token, 1_000)).toBeNull();
    expect(verifyStreamToken('secret', 'a.b', 1_000)).toBeNull();
  });
});
