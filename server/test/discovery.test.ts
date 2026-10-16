import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { Db } from '../src/db.js';
import { editDistance, matchScore, normalize } from '../src/fuzzy.js';
import type { MemoryMessenger } from '../src/messaging.js';
import { api, artistBody, makeApp, signUpVerified, type TestApp } from './helpers.js';

describe('matching what someone typed', () => {
  it('ignores accents, capitals and punctuation', () => {
    expect(normalize('  Beyoncé!!  Knowles ')).toBe('beyonce knowles');
    expect(matchScore('beyonce', 'Beyoncé')).toBe(100);
  });

  it('counts swapped and missing letters as one slip', () => {
    expect(editDistance('nova', 'nvoa', 2)).toBe(1);
    expect(editDistance('nova', 'nov', 2)).toBe(1);
    expect(editDistance('nova', 'novaaaa', 2)).toBe(3); // more than allowed: reported as max + 1
    expect(editDistance('kitten', 'sitting', 3)).toBe(3);
  });

  it('prefers exact, then the start, then inside, then a slip of the keys', () => {
    const exact = matchScore('nova wave', 'Nova Wave');
    const start = matchScore('nova', 'Nova Wave');
    const inside = matchScore('wave', 'Nova Wave');
    const slip = matchScore('novva wave', 'Nova Wave');
    expect([exact, start, inside]).toEqual([100, 92, 75]);
    expect(slip).toBeGreaterThan(0);
    expect(slip).toBeLessThan(inside);
  });

  it('forgives one slip in an ordinary word and two in a long one, but none in a very short one', () => {
    expect(matchScore('nvoa', 'Nova')).toBeGreaterThan(0);
    expect(matchScore('beyonse', 'Beyonce')).toBeGreaterThan(0);
    expect(matchScore('ab', 'ac')).toBe(0);
    expect(matchScore('wve', 'Wave')).toBeGreaterThan(0); // a three-letter word may lose a letter if it starts right
    expect(matchScore('xve', 'Wave')).toBe(0);
    expect(matchScore('xyz', 'Nova Wave')).toBe(0);
    expect(matchScore('amapianno', 'Amapiano')).toBeGreaterThan(0);
  });

  it('needs every typed word to match something', () => {
    expect(matchScore('nova zzzz', 'Nova Wave')).toBe(0);
    expect(matchScore('', 'Nova')).toBe(0);
  });
});

describe('finding things', () => {
  let app: TestApp;
  let db: Db;
  let messenger: MemoryMessenger;
  let cleanup: () => void;
  let call: ReturnType<typeof api>['call'];
  const ids: Record<string, string> = {};
  const acts: Record<string, { id: string; token: string }> = {};

  async function song(act: string, title: string, genre: string, opts: { explicit?: boolean; publish?: boolean; daysAgo?: number } = {}) {
    const id = (await call('POST', '/v1/artists/me/tracks', acts[act]!.token, { title, genre, explicit: opts.explicit ?? false })).json().id as string;
    if (opts.publish !== false) await db.query("update tracks set status = 'published', published_at = now() - ($2 || ' days')::interval where id = $1", [id, String(opts.daysAgo ?? 0)]);
    ids[title] = id;
  }

  async function play(title: string, country: string | null, daysAgo: number, times = 1, userId: string | null = null) {
    const artist = (await db.query<{ artist_id: string }>('select artist_id from tracks where id = $1', [ids[title]])).rows[0]!.artist_id;
    for (let i = 0; i < times; i++) {
      await db.query(
        `insert into listen_events (id, user_id, track_id, artist_id, started_at, listened_ms, valid, source, platform, mode, country)
         values ($1, $2, $3, $4, $5::timestamptz, 60000, true, 'direct', 'android', 'normal', $6)`,
        [randomUUID(), userId, ids[title], artist, new Date(Date.now() - daysAgo * 86_400_000).toISOString(), country],
      );
    }
  }

  const search = async (q: string, token: string | null = null, extra = '') => (await call('GET', `/v1/search?q=${encodeURIComponent(q)}${extra}`, token)).json() as { artists: any[]; tracks: any[] };
  const suggest = async (q: string) => (await call('GET', `/v1/search/suggest?q=${encodeURIComponent(q)}`, null)).json().suggestions as { kind: string; text: string; id: string }[];

  beforeAll(async () => {
    ({ app, db, messenger, cleanup } = await makeApp());
    call = api(app).call;
    for (const [key, stage] of [['nova', 'Nova Wave'], ['kito', 'Kito Beats'], ['zuri', 'Zúri'], ['rising', 'Rising Star'], ['steady', 'Steady Act']] as const) {
      const u = await signUpVerified(app, messenger, `ds_${key}`);
      await call('POST', '/v1/artists/me', u.token, artistBody({ stageName: stage }));
      acts[key] = { id: u.id, token: u.token };
    }
    await song('nova', 'Night Drive', 'Afrobeats', { daysAgo: 3 });
    await song('nova', 'Sunrise Run', 'afrobeats', { daysAgo: 1 });
    await song('kito', 'Jazz Night', 'Jazz', { daysAgo: 2 });
    await song('zuri', 'Explicit Jam', 'Afrobeats', { explicit: true, daysAgo: 4 });
    await song('zuri', 'Clean Jam', 'Afrobeats', { daysAgo: 5 });
    await song('nova', 'Unreleased', 'Afrobeats', { publish: false });
    await song('kito', 'Odd One', 'other', { daysAgo: 6 });
    await song('rising', 'Climbing', 'Pop');
    await song('steady', 'Same As Ever', 'Pop');
    // listening: Night Drive is the favourite of Nova Wave
    await play('Night Drive', 'KE', 2, 5);
    await play('Sunrise Run', 'KE', 2, 2);
    await play('Jazz Night', 'US', 2, 4);
    await play('Climbing', 'KE', 1, 6); // this week
    await play('Climbing', 'KE', 10, 2); // the week before
    await play('Same As Ever', 'KE', 1, 10);
    await play('Same As Ever', 'KE', 10, 10);
  }, 90_000);
  afterAll(async () => {
    await app.close();
    cleanup();
  });

  describe('search', () => {
    it('finds songs by title and artists by name, together', async () => {
      const r = await search('night');
      expect(r.tracks.map((t) => t.title)).toEqual(expect.arrayContaining(['Night Drive', 'Jazz Night']));
      expect(r.tracks[0].title).toBe('Night Drive'); // starts with it
      const n = await search('nova');
      expect(n.artists.map((a) => a.stageName)).toEqual(['Nova Wave']);
      expect(n.tracks.map((t) => t.title)).toEqual(expect.arrayContaining(['Night Drive', 'Sunrise Run'])); // songs by that artist
      expect(n.artists[0]).toMatchObject({ verified: false, followers: 0 });
    });

    it('forgives typos and accents', async () => {
      expect((await search('nova wve')).artists.map((a) => a.stageName)).toEqual(['Nova Wave']);
      expect((await search('nigth drive')).tracks[0].title).toBe('Night Drive');
      expect((await search('zuri')).artists.map((a) => a.stageName)).toEqual(['Zúri']); // the artist wrote an accent, the listener did not
      expect((await search('sunrize run')).tracks.map((t) => t.title)).toContain('Sunrise Run');
    });

    it('finds nothing for nonsense, and refuses an empty search', async () => {
      const r = await search('qqqqqq');
      expect([r.artists.length, r.tracks.length]).toEqual([0, 0]);
      expect((await call('GET', '/v1/search?q=', null)).statusCode).toBe(400);
      expect((await call('GET', '/v1/search', null)).statusCode).toBe(400);
    });

    it('hides explicit songs unless allowed, unpublished songs, and the songs of suspended artists', async () => {
      expect((await search('jam')).tracks.map((t) => t.title)).toEqual(['Clean Jam']);
      const adult = await signUpVerified(app, messenger, 'ds_adult');
      await db.query('update users set explicit_allowed = true where id = $1', [adult.id]);
      expect((await search('jam', adult.token)).tracks.map((t) => t.title).sort()).toEqual(['Clean Jam', 'Explicit Jam']);
      expect((await search('unreleased')).tracks).toEqual([]);
      await db.query('update users set suspended_at = now() where id = $1', [acts.kito!.id]);
      const r = await search('kito');
      expect([r.artists.length, r.tracks.length]).toEqual([0, 0]);
      await db.query('update users set suspended_at = null where id = $1', [acts.kito!.id]);
    });

    it('limits the number of songs', async () => {
      expect((await search('a', null, '&limit=2')).tracks.length).toBeLessThanOrEqual(2);
    });
  });

  describe('suggestions while typing', () => {
    it('offers artists first, then songs, each with what it is', async () => {
      const s = await suggest('nov');
      expect(s[0]).toMatchObject({ kind: 'artist', text: 'Nova Wave', id: acts.nova!.id });
      const n = await suggest('night');
      expect(n.map((x) => [x.kind, x.text])).toEqual([['song', 'Night Drive'], ['song', 'Jazz Night']]); // starts with it first
    });

    it('works with a slip of the keys, and is quiet when nothing fits', async () => {
      expect((await suggest('nigth')).map((x) => x.text)).toContain('Night Drive');
      expect(await suggest('qqqq')).toEqual([]);
    });
  });

  describe('browse by genre', () => {
    it('lists the genres with how many songs each has, "other" last', async () => {
      const g = (await call('GET', '/v1/browse/genres', null)).json().genres as { genre: string; count: number }[];
      expect(g.map((x) => x.genre)).toEqual(['afrobeats', 'pop', 'jazz', 'other']); // Afrobeats and afrobeats are one genre; explicit hidden from guests
      expect(g[0]!.count).toBe(3); // Night Drive, Sunrise Run, Clean Jam
      expect(g.at(-1)).toMatchObject({ genre: 'other', count: 1 });
    });

    it('lists the songs of a genre, newest first or most played, whatever the capitals', async () => {
      const newest = (await call('GET', '/v1/browse/genres/Afrobeats', null)).json();
      expect(newest.genre).toBe('afrobeats');
      expect(newest.tracks.map((t: any) => t.title)).toEqual(['Sunrise Run', 'Night Drive', 'Clean Jam']);
      const popular = (await call('GET', '/v1/browse/genres/afrobeats?sort=popular', null)).json();
      expect(popular.tracks[0].title).toBe('Night Drive'); // five plays
      expect((await call('GET', '/v1/browse/genres/nothing', null)).json().tracks).toEqual([]);
      expect((await call('GET', '/v1/browse/genres/afrobeats?sort=loudest', null)).statusCode).toBe(400);
    });
  });

  describe('artist page', () => {
    it('shows the most played songs, the whole catalog newest first, and the numbers', async () => {
      const fan = await signUpVerified(app, messenger, 'ds_fan');
      await call('POST', `/v1/artists/${acts.nova!.id}/follow`, fan.token);
      await play('Night Drive', 'KE', 1, 1, fan.id);
      const page = (await call('GET', `/v1/artists/${acts.nova!.id}/page`, fan.token)).json();
      expect(page.artist).toMatchObject({ id: acts.nova!.id, stageName: 'Nova Wave', verified: false, followers: 1, monthlyListeners: 1 });
      expect(page.following).toBe(true);
      expect(page.topTracks.map((t: any) => [t.title, t.plays])).toEqual([['Night Drive', 6], ['Sunrise Run', 2]]);
      expect(page.discography.map((t: any) => t.title)).toEqual(['Sunrise Run', 'Night Drive']); // newest first; the unreleased one is not there
      const guest = (await call('GET', `/v1/artists/${acts.nova!.id}/page`, null)).json();
      expect(guest.following).toBe(false);
    });

    it('suggests similar artists: the ones with songs in the same genres, never the artist themselves', async () => {
      const page = (await call('GET', `/v1/artists/${acts.nova!.id}/page`, null)).json();
      expect(page.similar.map((a: any) => a.stageName)).toEqual(['Zúri']); // Afrobeats in common; Kito Beats is Jazz
    });

    it('keeps explicit songs from guests, and says nothing about a suspended or unknown artist', async () => {
      const zuri = (await call('GET', `/v1/artists/${acts.zuri!.id}/page`, null)).json();
      expect(zuri.discography.map((t: any) => t.title)).toEqual(['Clean Jam']);
      await db.query('update users set suspended_at = now() where id = $1', [acts.zuri!.id]);
      expect((await call('GET', `/v1/artists/${acts.zuri!.id}/page`, null)).statusCode).toBe(404);
      await db.query('update users set suspended_at = null where id = $1', [acts.zuri!.id]);
      expect((await call('GET', `/v1/artists/${randomUUID()}/page`, null)).statusCode).toBe(404);
      expect((await call('GET', '/v1/artists/not-an-id/page', null)).statusCode).toBe(400);
    });
  });

  describe('artist charts', () => {
    it('ranks artists by plays in the last 28 days, worldwide or for one country', async () => {
      const top = (await call('GET', '/v1/charts/artists', null)).json();
      expect(top.kind).toBe('top');
      expect(top.artists[0]).toMatchObject({ rank: 1, stageName: 'Steady Act' }); // 10 plays inside the 28 days
      expect(top.artists.map((a: any) => a.stageName)).toEqual(expect.arrayContaining(['Nova Wave', 'Kito Beats', 'Rising Star']));
      const ke = (await call('GET', '/v1/charts/artists?country=ke', null)).json();
      expect(ke.artists.map((a: any) => a.stageName)).not.toContain('Kito Beats'); // only played in the US
    });

    it('lists rising artists: more plays than the week before, and enough to mean something', async () => {
      const r = (await call('GET', '/v1/charts/artists?kind=rising', null)).json();
      // biggest gain first: Nova Wave went from 0 to 8, Rising Star from 2 to 6, Kito Beats from 0 to 4. Steady Act did 10 and 10: not rising.
      expect(r.artists.map((a: any) => a.stageName)).toEqual(['Nova Wave', 'Rising Star', 'Kito Beats']);
      expect(r.artists[1]).toMatchObject({ plays: 6, change: 4 });
      expect(r.artists[0]).toMatchObject({ plays: 8, change: 8 });
    });

    it('does not call an artist rising for a handful of plays', async () => {
      const a = (await call('GET', '/v1/charts/artists?kind=rising&country=US', null)).json();
      expect(a.artists.map((x: any) => x.stageName)).toEqual(['Kito Beats']); // 4 plays in the US: enough
      await play('Odd One', 'DE', 1, 2); // two plays only
      const b = (await call('GET', '/v1/charts/artists?kind=rising&country=DE', null)).json();
      expect(b.artists).toEqual([]);
    });

    it('refuses a country that is not two letters', async () => {
      expect((await call('GET', '/v1/charts/artists?country=KEN', null)).statusCode).toBe(400);
    });
  });
});
