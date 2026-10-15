import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { Db } from '../src/db.js';
import type { MemoryMessenger } from '../src/messaging.js';
import { api, artistBody, makeApp, signUpVerified, type TestApp } from './helpers.js';

describe('recommendations for a new listener', () => {
  let app: TestApp;
  let db: Db;
  let messenger: MemoryMessenger;
  let cleanup: () => void;
  let call: ReturnType<typeof api>['call'];
  const ids: Record<string, string> = {}; // song titles to ids
  let acts: Record<'afro' | 'jazz' | 'rock' | 'other', { id: string; token: string }>;

  async function song(act: keyof typeof acts, title: string, genre: string, explicit = false) {
    const id = (await call('POST', '/v1/artists/me/tracks', acts[act].token, { title, genre, explicit })).json().id as string;
    await db.query("update tracks set status = 'published', published_at = now() where id = $1", [id]);
    ids[title] = id;
    return id;
  }

  async function play(title: string, country: string | null, { valid = true, daysAgo = 1 }: { valid?: boolean; daysAgo?: number } = {}) {
    const artist = (await db.query<{ artist_id: string }>('select artist_id from tracks where id = $1', [ids[title]])).rows[0]!.artist_id;
    await db.query(
      `insert into listen_events (id, user_id, track_id, artist_id, started_at, listened_ms, valid, source, platform, mode, country)
       values ($1, null, $2, $3, $4::timestamptz, 60000, $5, 'direct', 'android', 'normal', $6)`,
      [randomUUID(), ids[title], artist, new Date(Date.now() - daysAgo * 86_400_000).toISOString(), valid, country],
    );
  }

  async function listener(name: string, opts: { genres?: string[]; artistIds?: string[]; country?: string | null; explicit?: boolean; personalization?: boolean } = {}) {
    const u = await signUpVerified(app, messenger, name);
    await db.query('update users set country = $2, explicit_allowed = $3, personalization = $4 where id = $1', [u.id, opts.country === undefined ? 'KE' : opts.country, opts.explicit ?? false, opts.personalization ?? true]);
    if (opts.genres || opts.artistIds) await call('PUT', '/v1/me/taste', u.token, { genres: opts.genres ?? [], moods: [], artistIds: opts.artistIds ?? [] });
    return u;
  }

  const home = async (token: string | null, query = '') => (await call('GET', `/v1/recommendations/home${query}`, token)).json().sections as { id: string; kind: string; title: string; tracks: { id: string; title: string; artist: { id: string } }[] }[];
  const section = (sections: Awaited<ReturnType<typeof home>>, id: string) => sections.find((s) => s.id === id);
  const titles = (s?: { tracks: { title: string }[] }) => (s?.tracks ?? []).map((t) => t.title);

  beforeAll(async () => {
    const made = await makeApp();
    ({ app, db, messenger, cleanup } = made);
    call = api(app).call;
    const mk = async (name: string, stage: string) => {
      const u = await signUpVerified(app, messenger, name);
      await call('POST', '/v1/artists/me', u.token, artistBody({ stageName: stage }));
      return { id: u.id, token: u.token };
    };
    acts = { afro: await mk('rec_afro', 'Afro Act'), jazz: await mk('rec_jazz', 'Jazz Act'), rock: await mk('rec_rock', 'Rock Act'), other: await mk('rec_other', 'Other Act') };
    for (const n of [1, 2, 3, 4, 5]) await song('afro', `Afro ${n}`, 'Afrobeats');
    await song('jazz', 'Jazz 1', 'Jazz');
    await song('jazz', 'Jazz 2', 'Jazz');
    await song('rock', 'Rock 1', 'Rock');
    await song('other', 'Explicit Afro', 'afrobeats', true);
    // listening in Kenya: five songs, so Kenya has enough to say what is popular there
    for (const [title, n] of [['Afro 1', 3], ['Afro 2', 2], ['Afro 3', 2], ['Afro 4', 1], ['Afro 5', 1]] as const) for (let i = 0; i < n; i++) await play(title, 'KE');
    for (let i = 0; i < 5; i++) await play('Jazz 1', 'US'); // very popular, but elsewhere
    await play('Jazz 1', 'KE', { valid: false }); // too short to count
    await play('Jazz 2', 'KE', { daysAgo: 40 }); // too old to count
  }, 60_000);
  afterAll(async () => {
    await app.close();
    cleanup();
  });

  describe('picked for you', () => {
    it('puts the artists you picked first, then your genres, and leaves everything else out', async () => {
      const u = await listener('rec_l1', { genres: ['afrobeats'], artistIds: [acts.rock.id] });
      const s = section(await home(u.token), 'for_you')!;
      expect(s.title).toBe('Picked for you');
      expect(titles(s)[0]).toBe('Rock 1'); // an artist you picked beats a genre match
      expect(titles(s).every((t) => t === 'Rock 1' || t.startsWith('Afro'))).toBe(true);
      expect(titles(s).some((t) => t.startsWith('Jazz'))).toBe(false);
    });

    it('does not let one artist fill the list, and puts the most played of an artist first', async () => {
      const u = await listener('rec_l2', { genres: ['afrobeats'] });
      const t = titles(section(await home(u.token), 'for_you'));
      expect(t.filter((x) => x.startsWith('Afro ')).length).toBe(3);
      expect(t.find((x) => x.startsWith('Afro '))).toBe('Afro 1'); // three plays, the most
    });

    it('hides explicit songs unless the listener allows them', async () => {
      const off = await listener('rec_l3', { genres: ['afrobeats'], explicit: false });
      const on = await listener('rec_l4', { genres: ['afrobeats'], explicit: true });
      expect(titles(section(await home(off.token), 'for_you'))).not.toContain('Explicit Afro');
      expect(titles(section(await home(on.token), 'for_you'))).toContain('Explicit Afro');
    });

    it('is left out for guests, for people who skipped the taste picker, and when personalization is paused', async () => {
      expect(section(await home(null), 'for_you')).toBeUndefined();
      const none = await listener('rec_l5');
      expect(section(await home(none.token), 'for_you')).toBeUndefined();
      const paused = await listener('rec_l6', { genres: ['afrobeats'], personalization: false });
      expect(section(await home(paused.token), 'for_you')).toBeUndefined();
      expect(section(await home(paused.token), 'popular')).toBeDefined(); // what is not personal still shows
    });
  });

  describe('popular', () => {
    it('shows what is popular in the listener\'s country, counting only real plays from the last 28 days', async () => {
      const u = await listener('rec_p1', { country: 'KE' });
      const s = section(await home(u.token), 'popular')!;
      expect(s.title).toBe('Popular in Kenya');
      expect(titles(s)[0]).toBe('Afro 1');
      expect(s.tracks.length).toBe(5);
      expect(titles(s)).not.toContain('Jazz 1'); // popular only in the US, and its Kenyan play was too short
      expect(titles(s)).not.toContain('Jazz 2'); // its Kenyan play was too old
    });

    it('falls back to the whole of Vyro when a country has too little listening, and for people with no country', async () => {
      const tz = await listener('rec_p2', { country: 'TZ' });
      const s = section(await home(tz.token), 'popular')!;
      expect(s.title).toBe('Popular on Vyro');
      expect(titles(s)[0]).toBe('Jazz 1'); // five plays in the US make it the most played overall
      const none = await listener('rec_p3', { country: null });
      expect(section(await home(none.token), 'popular')!.title).toBe('Popular on Vyro');
    });

    it('works for guests, who can say where they are', async () => {
      expect(section(await home(null), 'popular')!.title).toBe('Popular on Vyro');
      expect(section(await home(null, '?country=ke'), 'popular')!.title).toBe('Popular in Kenya');
      expect((await call('GET', '/v1/recommendations/home?country=KEN')).statusCode).toBe(400);
    });

    it('hides the songs of a suspended artist', async () => {
      await db.query('update users set suspended_at = now() where id = $1', [acts.afro.id]);
      expect(titles(section(await home(null, '?country=ke'), 'popular'))).not.toContain('Afro 1');
      await db.query('update users set suspended_at = null where id = $1', [acts.afro.id]);
    });
  });

  describe('not interested', () => {
    it('needs a login, knows what exists, and can be said twice', async () => {
      expect((await call('POST', '/v1/recommendations/not-interested', null, { kind: 'track', id: ids['Afro 1'] })).statusCode).toBe(401);
      const u = await listener('rec_n1', { genres: ['afrobeats'] });
      expect((await call('POST', '/v1/recommendations/not-interested', u.token, { kind: 'track', id: randomUUID() })).statusCode).toBe(404);
      expect((await call('POST', '/v1/recommendations/not-interested', u.token, { kind: 'artist', id: randomUUID() })).statusCode).toBe(404);
      for (let i = 0; i < 2; i++) expect((await call('POST', '/v1/recommendations/not-interested', u.token, { kind: 'track', id: ids['Afro 1'] })).statusCode).toBe(204);
      expect((await call('POST', '/v1/recommendations/not-interested', u.token, { kind: 'song', id: ids['Afro 1'] })).statusCode).toBe(400);
    });

    it('removes a song, or all of an artist\'s songs, from every list', async () => {
      const u = await listener('rec_n2', { genres: ['afrobeats'], artistIds: [acts.rock.id], country: 'KE' });
      await call('POST', '/v1/recommendations/not-interested', u.token, { kind: 'track', id: ids['Afro 1'] });
      await call('POST', '/v1/recommendations/not-interested', u.token, { kind: 'artist', id: acts.rock.id });
      const sections = await home(u.token);
      for (const s of sections) {
        expect(titles(s)).not.toContain('Afro 1');
        expect(titles(s)).not.toContain('Rock 1');
      }
      expect(titles(section(sections, 'popular'))[0]).not.toBe('Afro 1');
      expect(titles(section(await home(await listener('rec_n3', { genres: ['afrobeats'] }).then((x) => x.token)), 'for_you'))).toContain('Afro 1'); // other people are not affected
    });

    it('is still honoured while personalization is paused', async () => {
      const u = await listener('rec_n4', { personalization: false, country: 'KE' });
      await call('POST', '/v1/recommendations/not-interested', u.token, { kind: 'track', id: ids['Afro 1'] });
      expect(titles(section(await home(u.token), 'popular'))).not.toContain('Afro 1');
    });

    it('can be reset, which also forgets the taste picks', async () => {
      const u = await listener('rec_n5', { genres: ['afrobeats'] });
      await call('POST', '/v1/recommendations/not-interested', u.token, { kind: 'track', id: ids['Afro 1'] });
      expect((await call('DELETE', '/v1/recommendations', u.token)).statusCode).toBe(204);
      const sections = await home(u.token);
      expect(section(sections, 'for_you')).toBeUndefined(); // the picks are gone
      expect(titles(section(sections, 'popular'))).toContain('Afro 1'); // and so is the "not interested"
      expect((await call('DELETE', '/v1/recommendations', null)).statusCode).toBe(401);
    });
  });

  describe('lists chosen by staff', () => {
    let mod: { id: string; token: string };
    beforeAll(async () => {
      mod = await signUpVerified(app, messenger, 'rec_mod');
      await db.query("update users set role = 'moderator' where id = $1", [mod.id]);
    });

    it('is for staff only', async () => {
      const u = await listener('rec_e0');
      expect((await call('GET', '/v1/admin/editorial', u.token)).statusCode).toBe(403);
      expect((await call('POST', '/v1/admin/editorial', u.token, { title: 'x', trackIds: [] })).statusCode).toBe(403);
      expect((await call('GET', '/v1/admin/editorial', null)).statusCode).toBe(401);
    });

    it('stays hidden until published, then shows its songs in the chosen order', async () => {
      const made = await call('POST', '/v1/admin/editorial', mod.token, { title: 'Late night', description: 'For after dark', trackIds: [ids['Jazz 2'], ids['Jazz 1'], ids['Rock 1']], position: 1 });
      expect(made.statusCode).toBe(201);
      const id = made.json().id as string;
      const guest = await home(null);
      expect(guest.some((s) => s.kind === 'editorial')).toBe(false); // a draft

      expect((await call('PUT', `/v1/admin/editorial/${id}`, mod.token, { title: 'Late night', description: 'For after dark', trackIds: [ids['Jazz 2'], ids['Jazz 1'], ids['Rock 1']], published: true, position: 1 })).statusCode).toBe(200);
      const s = section(await home(null), `editorial:${id}`)!;
      expect([s.title, s.kind]).toEqual(['Late night', 'editorial']);
      expect(titles(s)).toEqual(['Jazz 2', 'Jazz 1', 'Rock 1']);
      expect((await call('GET', '/v1/admin/editorial', mod.token)).json().lists.find((l: any) => l.id === id)).toMatchObject({ published: true, trackCount: 3 });

      // editing replaces the songs
      await call('PUT', `/v1/admin/editorial/${id}`, mod.token, { title: 'Late night', trackIds: [ids['Rock 1']], published: true });
      expect(titles(section(await home(null), `editorial:${id}`))).toEqual(['Rock 1']);
      expect((await call('DELETE', `/v1/admin/editorial/${id}`, mod.token)).statusCode).toBe(204);
      expect(section(await home(null), `editorial:${id}`)).toBeUndefined();
      expect((await call('DELETE', `/v1/admin/editorial/${id}`, mod.token)).statusCode).toBe(404);
    });

    it('follows the same rules as everything else: explicit songs, unpublished songs, "not interested", and empty lists', async () => {
      const draft = await song('afro', 'Not Live Yet', 'Afrobeats');
      await db.query("update tracks set status = 'draft' where id = $1", [draft]);
      const listId = (await call('POST', '/v1/admin/editorial', mod.token, { title: 'Mixed bag', trackIds: [ids['Explicit Afro'], draft, ids['Jazz 1']], published: true })).json().id as string;
      const empty = (await call('POST', '/v1/admin/editorial', mod.token, { title: 'Only a draft song', trackIds: [draft], published: true })).json().id as string;

      expect(titles(section(await home(null), `editorial:${listId}`))).toEqual(['Jazz 1']); // no explicit song for guests, no unpublished song
      expect(section(await home(null), `editorial:${empty}`)).toBeUndefined(); // nothing to show, so no list
      const adult = await listener('rec_e1', { explicit: true });
      expect(titles(section(await home(adult.token), `editorial:${listId}`))).toEqual(['Explicit Afro', 'Jazz 1']);
      await call('POST', '/v1/recommendations/not-interested', adult.token, { kind: 'track', id: ids['Jazz 1'] });
      expect(titles(section(await home(adult.token), `editorial:${listId}`))).toEqual(['Explicit Afro']);

      await call('DELETE', `/v1/admin/editorial/${listId}`, mod.token);
      await call('DELETE', `/v1/admin/editorial/${empty}`, mod.token);
    });

    it('refuses songs that do not exist, and bad input', async () => {
      expect((await call('POST', '/v1/admin/editorial', mod.token, { title: 'Ghosts', trackIds: [randomUUID()] })).json().error).toBe('unknown_track');
      expect((await call('POST', '/v1/admin/editorial', mod.token, { title: '', trackIds: [] })).statusCode).toBe(400);
      expect((await call('PUT', `/v1/admin/editorial/${randomUUID()}`, mod.token, { title: 'x', trackIds: [] })).statusCode).toBe(404);
    });
  });
});
