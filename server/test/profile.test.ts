import { randomUUID } from 'node:crypto';
import { mkdtempSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { Db } from '../src/db.js';
import type { MemoryMessenger } from '../src/messaging.js';
import { LocalDiskStorage } from '../src/storage.js';
import { fakePng } from './audio_fixtures.js';
import { PASSWORD, api, artistBody, makeApp, signUpVerified, type TestApp } from './helpers.js';

describe('profile photo and privacy', () => {
  let app: TestApp;
  let db: Db;
  let messenger: MemoryMessenger;
  let cleanup: () => void;
  let call: ReturnType<typeof api>['call'];
  const dir = mkdtempSync(join(tmpdir(), 'vyro-profile-'));
  const files = () => (readdirSync(dir, { recursive: true }) as string[]).filter((f) => /photo-|cover-/.test(f));
  let songId: string;
  let artistToken: string;

  const upload = (token: string | null, body: Buffer | object, type = 'image/png') =>
    app.inject({ method: 'PUT', url: '/v1/me/photo', payload: body, headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), 'content-type': type } });
  const jpeg = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(200, 2)]);

  beforeAll(async () => {
    ({ app, db, messenger, cleanup } = await makeApp({ storage: new LocalDiskStorage(dir) }));
    call = api(app).call;
    const a = await signUpVerified(app, messenger, 'pf_artist');
    await call('POST', '/v1/artists/me', a.token, artistBody({ stageName: 'Profile Act' }));
    artistToken = a.token;
    songId = (await call('POST', '/v1/artists/me/tracks', a.token, { title: 'Profile Song', genre: 'Pop' })).json().id;
    await db.query("update tracks set status = 'published', published_at = now() where id = $1", [songId]);
  }, 60_000);
  afterAll(async () => {
    await app.close();
    cleanup();
    rmSync(dir, { recursive: true, force: true });
  });

  describe('photo', () => {
    it('takes a picture, shows it to its owner only, and replaces the old file', async () => {
      const u = await signUpVerified(app, messenger, 'pf_l1');
      const other = await signUpVerified(app, messenger, 'pf_l2');
      expect((await call('GET', '/v1/me', u.token)).json().photoUrl).toBeNull();
      const res = await upload(u.token, fakePng);
      expect(res.statusCode).toBe(200);
      const url = res.json().photoUrl as string;
      expect(url).toMatch(new RegExp(`^/v1/users/${u.id}/photo\\?v=\\d+$`));
      const before = files().length;

      const own = await call('GET', url, u.token);
      expect([own.statusCode, own.headers['content-type']]).toEqual([200, 'image/png']);
      expect(own.rawPayload.length).toBe(fakePng.length);
      expect((await call('GET', url, null)).statusCode).toBe(404); // a listener's photo is private
      expect((await call('GET', url, other.token)).statusCode).toBe(404);

      const replaced = await upload(u.token, jpeg, 'image/jpeg');
      expect(replaced.json().photoUrl).not.toBe(url); // a new address, so no one sees the old picture from a cache
      expect(files().length).toBe(before); // the old file is gone
      expect((await call('GET', replaced.json().photoUrl, u.token)).headers['content-type']).toBe('image/jpeg');
    });

    it('refuses what is not a picture, and anything over 5 MB, and keeps the current photo', async () => {
      const u = await signUpVerified(app, messenger, 'pf_l3');
      await upload(u.token, fakePng);
      const url = (await call('GET', '/v1/me', u.token)).json().photoUrl as string;
      expect((await upload(u.token, Buffer.from('plain text'))).statusCode).toBe(415);
      expect((await upload(u.token, { not: 'a file' }, 'application/json')).statusCode).toBe(415);
      expect((await upload(u.token, Buffer.concat([fakePng, Buffer.alloc(5 * 1024 * 1024)]))).statusCode).toBe(413);
      expect((await upload(null, fakePng)).statusCode).toBe(401);
      expect((await call('GET', '/v1/me', u.token)).json().photoUrl).toBe(url);
      expect(files().filter((f) => f.includes(u.id)).length).toBe(1); // nothing from the refused uploads was kept
    });

    it('is public for an artist, unless they are suspended', async () => {
      const a = await signUpVerified(app, messenger, 'pf_a2');
      await call('POST', '/v1/artists/me', a.token, artistBody({ stageName: 'Photo Act' }));
      const url = (await upload(a.token, fakePng)).json().photoUrl as string;
      const guest = await call('GET', url, null);
      expect([guest.statusCode, guest.headers['cache-control']]).toEqual([200, 'public, max-age=3600']);
      await db.query('update users set suspended_at = now() where id = $1', [a.id]);
      expect((await call('GET', url, null)).statusCode).toBe(404);
    });

    it('can be removed', async () => {
      const u = await signUpVerified(app, messenger, 'pf_l4');
      const url = (await upload(u.token, fakePng)).json().photoUrl as string;
      expect((await call('DELETE', '/v1/me/photo', u.token)).statusCode).toBe(204);
      expect((await call('GET', url, u.token)).statusCode).toBe(404);
      expect((await call('GET', '/v1/me', u.token)).json().photoUrl).toBeNull();
      expect(files().filter((f) => f.includes(u.id))).toEqual([]);
      expect((await call('DELETE', '/v1/me/photo', u.token)).statusCode).toBe(204); // nothing to remove: still fine
    });
  });

  describe('sharing the country with artists', () => {
    const post = (token: string) =>
      call('POST', '/v1/events/listens', token, { events: [{ id: randomUUID(), trackId: songId, startedAt: new Date().toISOString(), listenedMs: 60000, source: 'direct', platform: 'android', mode: 'normal' }] });
    const lastCountry = async () => (await db.query<{ country: string | null }>('select country from listen_events order by started_at desc, id limit 1')).rows[0]!.country;

    it('records the country by default, and leaves it out once the listener turns it off', async () => {
      const u = await signUpVerified(app, messenger, 'pf_c1');
      await db.query("update users set country = 'KE' where id = $1", [u.id]);
      expect((await call('GET', '/v1/me', u.token)).json().settings.shareCountry).toBe(true);
      await post(u.token);
      expect(await lastCountry()).toBe('KE');

      const patched = await call('PATCH', '/v1/me/settings', u.token, { shareCountry: false });
      expect(patched.json().settings.shareCountry).toBe(false);
      await new Promise((r) => setTimeout(r, 5));
      expect((await post(u.token)).json().accepted).toBe(1); // the play still counts
      expect(await lastCountry()).toBeNull();

      await call('PATCH', '/v1/me/settings', u.token, { shareCountry: true });
      await new Promise((r) => setTimeout(r, 5));
      await post(u.token);
      expect(await lastCountry()).toBe('KE');
    });
  });

  describe('a copy of my data', () => {
    it('holds the person\'s profile, picks, follows, likes, choices and plays, and nobody else\'s', async () => {
      const u = await signUpVerified(app, messenger, 'pf_x1');
      const other = await signUpVerified(app, messenger, 'pf_x2');
      await call('PUT', '/v1/me/taste', u.token, { genres: ['pop'], moods: [], artistIds: [] });
      const artist = (await db.query<{ artist_id: string }>('select artist_id from tracks where id = $1', [songId])).rows[0]!.artist_id;
      await call('POST', `/v1/artists/${artist}/follow`, u.token);
      await call('POST', `/v1/tracks/${songId}/save`, u.token);
      await call('POST', '/v1/recommendations/not-interested', u.token, { kind: 'artist', id: artist });
      const play = (token: string) => call('POST', '/v1/events/listens', token, { events: [{ id: randomUUID(), trackId: songId, startedAt: new Date().toISOString(), listenedMs: 60000, source: 'direct', platform: 'android', mode: 'normal' }] });
      await play(u.token);
      await play(other.token); // someone else's play
      await call('PATCH', '/v1/me/settings', u.token, { privateSession: true });
      await play(u.token); // a private play is not linked to the person

      const res = await call('GET', '/v1/me/export', u.token);
      expect(res.statusCode).toBe(200);
      expect(res.headers['content-disposition']).toContain('vyro-my-data.json');
      const data = res.json();
      expect(data.profile).toMatchObject({ id: u.id, email: expect.stringContaining('pf_x1') });
      expect(data.profile.hasPassword).toBe(true); // only the fact that there is one
      expect(JSON.stringify(data)).not.toMatch(/password_?hash|refreshToken|accessToken|scrypt/i); // never the secrets themselves
      expect(data.taste.genres).toEqual(['pop']);
      expect(data.follows).toMatchObject([{ artistId: artist, stageName: 'Profile Act' }]);
      expect(data.likedSongs).toMatchObject([{ songId, title: 'Profile Song', artist: 'Profile Act' }]);
      expect(data.notInterested).toMatchObject([{ kind: 'artist', targetId: artist }]);
      expect(data.plays.length).toBe(1);
      expect(data.plays[0]).toMatchObject({ title: 'Profile Song', artist: 'Profile Act', source: 'direct', platform: 'android', mode: 'normal' });
      expect(typeof data.plays[0].listenedMs).toBe('number'); // capped at the length of the song, which has no audio here
      expect(data.artistSongs).toEqual([]);
      expect(typeof data.exportedAt).toBe('string');
    });

    it('lists an artist\'s songs too, and needs a login', async () => {
      const data = (await call('GET', '/v1/me/export', artistToken)).json();
      expect(data.artistSongs.map((s: any) => s.title)).toEqual(['Profile Song']);
      expect((await call('GET', '/v1/me/export', null)).statusCode).toBe(401);
    });
  });

  describe('deleting an account', () => {
    it('removes the files too: the photo, and an artist\'s covers', async () => {
      const a = await signUpVerified(app, messenger, 'pf_del');
      await call('POST', '/v1/artists/me', a.token, artistBody({ stageName: 'Gone Act' }));
      const id = (await call('POST', '/v1/artists/me/tracks', a.token, { title: 'Gone Song', genre: 'Pop' })).json().id as string;
      await app.inject({ method: 'PUT', url: `/v1/artists/me/tracks/${id}/cover`, payload: fakePng, headers: { authorization: `Bearer ${a.token}`, 'content-type': 'image/png' } });
      await upload(a.token, fakePng);
      expect(files().filter((f) => f.includes(a.id) || f.includes(id)).length).toBe(2);
      expect((await call('POST', '/v1/me/delete', a.token, { confirm: 'DELETE', password: PASSWORD })).statusCode).toBe(204);
      expect(files().filter((f) => f.includes(a.id) || f.includes(id))).toEqual([]);
    });
  });
});
