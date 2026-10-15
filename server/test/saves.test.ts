import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { Db } from '../src/db.js';
import type { MemoryMessenger } from '../src/messaging.js';
import { api, artistBody, makeApp, signUpVerified, type TestApp } from './helpers.js';

describe('liked songs', () => {
  let app: TestApp;
  let db: Db;
  let messenger: MemoryMessenger;
  let cleanup: () => void;
  let call: ReturnType<typeof api>['call'];
  let artist: { id: string; token: string };
  const ids: Record<string, string> = {};

  async function song(title: string, extra: object = {}, publish = true) {
    const id = (await call('POST', '/v1/artists/me/tracks', artist.token, { title, ...extra })).json().id as string;
    if (publish) await db.query("update tracks set status = 'published', published_at = now() where id = $1", [id]);
    ids[title] = id;
  }
  const titles = async (token: string) => ((await call('GET', '/v1/me/saves', token)).json().tracks as { title: string }[]).map((t) => t.title);

  beforeAll(async () => {
    ({ app, db, messenger, cleanup } = await makeApp());
    call = api(app).call;
    const u = await signUpVerified(app, messenger, 'sv_artist');
    await call('POST', '/v1/artists/me', u.token, artistBody({ stageName: 'Save Act' }));
    artist = { id: u.id, token: u.token };
    await song('One');
    await song('Two');
    await song('Three');
    await song('Rude', { explicit: true });
    await song('Draft', {}, false);
  }, 60_000);
  afterAll(async () => {
    await app.close();
    cleanup();
  });

  it('lists the songs a person liked, newest first, and forgets the ones they unlike', async () => {
    const u = await signUpVerified(app, messenger, 'sv_l1');
    for (const t of ['One', 'Two', 'Three']) {
      expect((await call('POST', `/v1/tracks/${ids[t]}/save`, u.token)).statusCode).toBe(204);
      await new Promise((r) => setTimeout(r, 5)); // so the order is clear
    }
    expect(await titles(u.token)).toEqual(['Three', 'Two', 'One']);
    await call('DELETE', `/v1/tracks/${ids['Two']}/save`, u.token);
    expect(await titles(u.token)).toEqual(['Three', 'One']);
    const row = (await call('GET', '/v1/me/saves', u.token)).json().tracks[0];
    expect(row).toMatchObject({ title: 'Three', artist: { stageName: 'Save Act' } });
    expect(row.savedAt).toBeTruthy();
  });

  it('is private to the person, and needs a login', async () => {
    const a = await signUpVerified(app, messenger, 'sv_l2');
    const b = await signUpVerified(app, messenger, 'sv_l3');
    await call('POST', `/v1/tracks/${ids['One']}/save`, a.token);
    expect(await titles(b.token)).toEqual([]);
    expect((await call('GET', '/v1/me/saves', null)).statusCode).toBe(401);
  });

  it('hides explicit songs from anyone who turned them off, and songs that are no longer live', async () => {
    const u = await signUpVerified(app, messenger, 'sv_l4');
    await song('Soon Gone');
    for (const t of ['One', 'Rude', 'Soon Gone']) await call('POST', `/v1/tracks/${ids[t]}/save`, u.token);
    await db.query('update users set explicit_allowed = false where id = $1', [u.id]);
    expect((await titles(u.token)).sort()).toEqual(['One', 'Soon Gone']);
    await db.query('update users set explicit_allowed = true where id = $1', [u.id]);
    expect((await titles(u.token)).sort()).toEqual(['One', 'Rude', 'Soon Gone']);
    await db.query("update tracks set status = 'taken_down' where id = $1", [ids['Soon Gone']]);
    expect((await titles(u.token)).sort()).toEqual(['One', 'Rude']);
    await db.query('update users set suspended_at = now() where id = $1', [artist.id]);
    expect(await titles(u.token)).toEqual([]); // a suspended artist's songs are hidden
    await db.query('update users set suspended_at = null where id = $1', [artist.id]);
  });
});
