import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { Db } from '../src/db.js';
import { MAX_LYRICS_CHARS, parseLyrics } from '../src/lrc.js';
import type { MemoryMessenger } from '../src/messaging.js';
import { api, artistBody, makeApp, signUpVerified, type TestApp } from './helpers.js';

describe('reading lyrics', () => {
  it('reads time-stamped lines and ignores the title, artist and album tags', () => {
    const r = parseLyrics('[ar:Someone]\n[ti:Song]\n[al:Album]\n[00:12.00]First line\n[00:15.50]Second line\n[01:02.5]Late line');
    expect(r.synced).toBe(true);
    expect(r.lines).toEqual([
      { timeMs: 12000, text: 'First line' },
      { timeMs: 15500, text: 'Second line' },
      { timeMs: 62500, text: 'Late line' },
    ]);
  });

  it('reads several time stamps on one line, and puts lines in time order', () => {
    const r = parseLyrics('[00:40.00]Verse two\n[00:10.00][01:20.00]Chorus\n[00:05.00]Intro');
    expect(r.lines.map((l) => [l.timeMs, l.text])).toEqual([
      [5000, 'Intro'],
      [10000, 'Chorus'],
      [40000, 'Verse two'],
      [80000, 'Chorus'],
    ]);
  });

  it('applies the offset tag: positive shows lyrics sooner, negative later, never before zero', () => {
    expect(parseLyrics('[offset:+500]\n[00:10.00]Hi').lines[0]!.timeMs).toBe(9500);
    expect(parseLyrics('[offset:-500]\n[00:10.00]Hi').lines[0]!.timeMs).toBe(10500);
    expect(parseLyrics('[offset:+5000]\n[00:01.00]Hi').lines[0]!.timeMs).toBe(0);
  });

  it('accepts the different ways of writing the fraction of a second', () => {
    const t = (s: string) => parseLyrics(s).lines[0]!.timeMs;
    expect([t('[00:10]x'), t('[00:10.5]x'), t('[00:10.50]x'), t('[00:10.500]x'), t('[00:10:50]x'), t('[100:00.00]x')]).toEqual([10000, 10500, 10500, 10500, 10500, 6_000_000]);
  });

  it('drops word-by-word stamps and keeps the words', () => {
    expect(parseLyrics('[00:10.00]<00:10.00>Hel<00:10.50>lo <00:11.00>there').lines[0]!.text).toBe('Hello there');
  });

  it('keeps one gap for an instrumental break, but no leading or doubled gaps', () => {
    const r = parseLyrics('[00:01.00]\n[00:10.00]a\n[00:12.00]\n[00:12.50]\n[00:20.00]b');
    expect(r.lines.map((l) => l.text)).toEqual(['a', '', 'b']);
  });

  it('copes with a byte order mark and Windows line endings', () => {
    expect(parseLyrics('\uFEFF[00:01.00]x\r\n[00:02.00]y').lines.map((l) => l.text)).toEqual(['x', 'y']);
  });

  it('treats text without time stamps as plain lyrics, keeping verse breaks', () => {
    const r = parseLyrics('Line one\n\n\nLine two  \n\n');
    expect(r.synced).toBe(false);
    expect(r.lines).toEqual([
      { timeMs: null, text: 'Line one' },
      { timeMs: null, text: '' },
      { timeMs: null, text: 'Line two' },
    ]);
  });

  it('finds nothing in text that only has tags', () => {
    expect(parseLyrics('[ar:Someone]\n[ti:Song]').lines).toEqual([]);
  });
});

describe('lyrics for songs', () => {
  let app: TestApp;
  let db: Db;
  let messenger: MemoryMessenger;
  let cleanup: () => void;
  let call: ReturnType<typeof api>['call'];
  let artist: { id: string; token: string; email: string };
  let other: { id: string; token: string };
  let listener: { id: string; token: string };
  let teen: { token: string };

  const synced = '[00:05.00]First\n[00:10.00]Second\n[00:15.00]Third';

  async function song(title: string, extra: object = {}, status: 'draft' | 'published' = 'published') {
    const id = (await call('POST', '/v1/artists/me/tracks', artist.token, { title, ...extra })).json().id as string;
    if (status === 'published') await db.query("update tracks set status = 'published', published_at = now() where id = $1", [id]);
    return id;
  }

  beforeAll(async () => {
    const made = await makeApp();
    ({ app, db, messenger, cleanup } = made);
    call = api(app).call;
    artist = await signUpVerified(app, messenger, 'lyr_artist');
    await call('POST', '/v1/artists/me', artist.token, artistBody({ stageName: 'Lyric Act' }));
    other = await signUpVerified(app, messenger, 'lyr_other');
    await call('POST', '/v1/artists/me', other.token, artistBody({ stageName: 'Other Lyric Act' }));
    listener = await signUpVerified(app, messenger, 'lyr_listener');
    const t = (await call('POST', '/v1/auth/register', null, { email: 'lyr_teen@example.com', password: 'correct-horse-battery', displayName: 'Teen', username: 'lyr_teen', birthDate: '2009-03-03', acceptedTermsVersion: '2026-10' })).json();
    teen = { token: t.accessToken };
  }, 60_000);
  afterAll(async () => {
    await app.close();
    cleanup();
  });

  const put = (id: string, token: string, text: string) => call('PUT', `/v1/artists/me/tracks/${id}/lyrics`, token, { text });

  it('saves synced and plain lyrics and tells the artist which kind they are', async () => {
    const id = await song('Synced Song');
    expect((await put(id, artist.token, synced)).json()).toEqual({ synced: true, lineCount: 3 });
    expect((await put(id, artist.token, 'Just words\n\nMore words')).json()).toEqual({ synced: false, lineCount: 3 });
  });

  it('gives the artist their text back exactly, and the public the parsed lines', async () => {
    const id = await song('Round Trip');
    await put(id, artist.token, `[ar:Lyric Act]\n${synced}`);
    expect((await call('GET', `/v1/artists/me/tracks/${id}/lyrics`, artist.token)).json()).toEqual({ text: `[ar:Lyric Act]\n${synced}`, synced: true });
    const pub = (await call('GET', `/v1/tracks/${id}/lyrics`)).json();
    expect(pub.synced).toBe(true);
    expect(pub.lines).toEqual([
      { timeMs: 5000, text: 'First' },
      { timeMs: 10000, text: 'Second' },
      { timeMs: 15000, text: 'Third' },
    ]);
    expect(pub.updatedAt).toBeTruthy();
  });

  it('refuses empty lyrics, tags only, and text that is too long', async () => {
    const id = await song('Bad Lyrics');
    expect((await put(id, artist.token, '   \n  ')).json().error).toBe('empty_lyrics');
    expect((await put(id, artist.token, '[ar:Someone]\n[ti:Song]')).json().error).toBe('empty_lyrics');
    expect((await put(id, artist.token, 'x'.repeat(MAX_LYRICS_CHARS + 1))).statusCode).toBe(400);
    expect((await call('GET', `/v1/tracks/${id}/lyrics`)).statusCode).toBe(404); // nothing was saved
  });

  it('keeps lyrics private to the song\'s artist', async () => {
    const id = await song('Mine');
    expect((await put(id, other.token, synced)).statusCode).toBe(404);
    expect((await put(id, listener.token, synced)).statusCode).toBe(403);
    expect((await call('GET', `/v1/artists/me/tracks/${id}/lyrics`, other.token)).statusCode).toBe(404);
    expect((await call('DELETE', `/v1/artists/me/tracks/${id}/lyrics`, other.token)).statusCode).toBe(404);
  });

  it('shows lyrics of unpublished songs only to their artist', async () => {
    const id = await song('Unreleased', {}, 'draft');
    await put(id, artist.token, synced);
    expect((await call('GET', `/v1/tracks/${id}/lyrics`)).statusCode).toBe(404);
    expect((await call('GET', `/v1/tracks/${id}/lyrics`, other.token)).statusCode).toBe(404);
    expect((await call('GET', `/v1/tracks/${id}/lyrics`, artist.token)).statusCode).toBe(200);
  });

  it('hides lyrics of explicit songs from guests and minors', async () => {
    const id = await song('Explicit Lyrics', { explicit: true });
    await put(id, artist.token, synced);
    expect((await call('GET', `/v1/tracks/${id}/lyrics`)).json().error).toBe('explicit_not_allowed');
    expect((await call('GET', `/v1/tracks/${id}/lyrics`, teen.token)).statusCode).toBe(403);
    expect((await call('GET', `/v1/tracks/${id}/lyrics`, listener.token)).statusCode).toBe(200);
    expect((await call('GET', `/v1/tracks/${id}/lyrics`, artist.token)).statusCode).toBe(200);
  });

  it('hides the lyrics of a suspended artist\'s songs', async () => {
    const hidden = await song('Soon Hidden');
    await put(hidden, artist.token, synced);
    expect((await call('GET', `/v1/tracks/${hidden}/lyrics`)).statusCode).toBe(200);
    await db.query("update users set suspended_at = now() where id = $1", [artist.id]);
    expect((await call('GET', `/v1/tracks/${hidden}/lyrics`)).statusCode).toBe(404);
    await db.query('update users set suspended_at = null where id = $1', [artist.id]);
  });

  it('lets the artist remove lyrics, and shows whether a song has them', async () => {
    const id = await song('Has Lyrics');
    expect((await call('GET', '/v1/artists/me/tracks', artist.token)).json().tracks.find((t: any) => t.id === id).hasLyrics).toBe(false);
    await put(id, artist.token, synced);
    expect((await call('GET', '/v1/artists/me/tracks', artist.token)).json().tracks.find((t: any) => t.id === id).hasLyrics).toBe(true);
    expect((await call('GET', '/v1/catalog/new')).json().tracks.find((t: any) => t.id === id).hasLyrics).toBe(true);
    expect((await call('DELETE', `/v1/artists/me/tracks/${id}/lyrics`, artist.token)).statusCode).toBe(204);
    expect((await call('GET', `/v1/tracks/${id}/lyrics`)).statusCode).toBe(404);
    expect((await call('GET', `/v1/artists/me/tracks/${id}/lyrics`, artist.token)).statusCode).toBe(404);
    expect((await call('GET', '/v1/artists/me/tracks', artist.token)).json().tracks.find((t: any) => t.id === id).hasLyrics).toBe(false);
  });

  it('lets a listener report wrong lyrics once, and tells the artist', async () => {
    const id = await song('Reported Song');
    await put(id, artist.token, synced);
    expect((await call('POST', `/v1/tracks/${id}/lyrics/report`, null, { reason: 'wrong_text' })).statusCode).toBe(401);
    const before = messenger.sent.length;
    expect((await call('POST', `/v1/tracks/${id}/lyrics/report`, listener.token, { reason: 'wrong_timing' })).statusCode).toBe(204);
    expect(messenger.sent.length).toBe(before + 1);
    expect(messenger.sent.at(-1)).toMatchObject({ to: artist.email });
    expect(messenger.sent.at(-1)!.body).toContain('the timing is off');

    expect((await call('POST', `/v1/tracks/${id}/lyrics/report`, listener.token, { reason: 'wrong_text' })).statusCode).toBe(204);
    expect(messenger.sent.length).toBe(before + 1); // the same person reporting again does not spam the artist
    expect((await call('POST', `/v1/tracks/${id}/lyrics/report`, other.token, { reason: 'nonsense' })).statusCode).toBe(400);

    const noLyrics = await song('No Lyrics Here');
    expect((await call('POST', `/v1/tracks/${noLyrics}/lyrics/report`, listener.token, {})).statusCode).toBe(404);
  });

  it('does not change a live song\'s status when its lyrics are corrected', async () => {
    const id = await song('Stays Live');
    await put(id, artist.token, synced);
    await put(id, artist.token, `${synced}\n[00:20.00]Fourth`);
    expect((await db.query<{ status: string }>('select status from tracks where id = $1', [id])).rows[0]!.status).toBe('published');
  });
});
