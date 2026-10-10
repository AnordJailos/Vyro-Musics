import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { promoteAdmins } from '../src/admins.js';
import { AcoustIdChecker, type CopyrightChecker, type CopyrightMatch } from '../src/copyright.js';
import type { Db } from '../src/db.js';
import { bitSimilarity, detectFingerprintTool } from '../src/fingerprint.js';
import type { MemoryMessenger } from '../src/messaging.js';
import { makeMp3, makeWav, reencode } from './audio_fixtures.js';
import { api, artistBody, makeApp, signUpVerified, type TestApp } from './helpers.js';

const hasFingerprints = (await detectFingerprintTool()) !== null;
const clock = new Date('2026-10-06T12:00:00Z');

type Account = { id: string; token: string; email: string; refreshToken: string };
type Harness = { app: TestApp; db: Db; messenger: MemoryMessenger; cleanup: () => void; call: ReturnType<typeof api>['call'] };

let seed = 1000;
const wavSeed = () => makeWav(12, 22_050, ++seed);

async function setup(extra: Parameters<typeof makeApp>[0] = {}): Promise<Harness> {
  const made = await makeApp({ now: () => clock, ...extra });
  return { ...made, call: api(made.app).call };
}

async function artistIn(h: Harness, name: string): Promise<Account> {
  const u = await signUpVerified(h.app, h.messenger, name);
  await h.call('POST', '/v1/artists/me', u.token, artistBody({ stageName: `Act ${name}` }));
  return u;
}

async function staffIn(h: Harness, name: string, role: 'moderator' | 'admin'): Promise<Account> {
  const u = await signUpVerified(h.app, h.messenger, name);
  await h.db.query('update users set role = $2 where id = $1', [u.id, role]);
  return u;
}

const put = (h: Harness, url: string, token: string, body: Buffer, type = 'audio/wav') =>
  h.app.inject({ method: 'PUT', url, payload: body, headers: { authorization: `Bearer ${token}`, 'content-type': type } });

/** A song with audio, ready to be submitted. */
async function readySong(h: Harness, who: Account, title: string, audio: Buffer = wavSeed(), type = 'audio/wav') {
  const id = (await h.call('POST', '/v1/artists/me/tracks', who.token, { title })).json().id as string;
  const up = await put(h, `/v1/artists/me/tracks/${id}/audio`, who.token, audio, type);
  expect(up.statusCode).toBe(200);
  return id;
}

const submit = async (h: Harness, who: Account, id: string) => (await h.call('POST', `/v1/artists/me/tracks/${id}/publish`, who.token)).json();
const isLive = async (h: Harness, id: string) => (await h.call('GET', `/v1/tracks/${id}`)).statusCode === 200;

describe.skipIf(!hasFingerprints)('review queue (every song is reviewed first)', () => {
  let h: Harness;
  let artist: Account;
  let mod: Account;
  let admin: Account;
  let listener: Account;

  beforeAll(async () => {
    h = await setup();
    artist = await artistIn(h, 'rev_artist');
    mod = await staffIn(h, 'rev_mod', 'moderator');
    admin = await staffIn(h, 'rev_admin', 'admin');
    listener = await signUpVerified(h.app, h.messenger, 'rev_listener');
  }, 60_000);
  afterAll(async () => {
    await h.app.close();
    h.cleanup();
  });

  it('holds a submitted song for review instead of publishing it', async () => {
    const id = await readySong(h, artist, 'Waiting Song');
    const view = await submit(h, artist, id);
    expect(view.status).toBe('in_review');
    expect(await isLive(h, id)).toBe(false);
    expect((await h.call('GET', '/v1/catalog/new')).json().tracks.some((t: any) => t.id === id)).toBe(false);
    expect((await h.call('POST', `/v1/artists/me/tracks/${id}/publish`, artist.token)).json().error).toBe('already_submitted');
  });

  it('shows the queue only to staff, with what the checks found', async () => {
    expect((await h.call('GET', '/v1/admin/review/queue', listener.token)).statusCode).toBe(403);
    expect((await h.call('GET', '/v1/admin/review/queue', artist.token)).statusCode).toBe(403);
    expect((await h.call('GET', '/v1/admin/review/queue')).statusCode).toBe(401);
    const queue = (await h.call('GET', '/v1/admin/review/queue', mod.token)).json().items;
    const item = queue.find((i: any) => i.title === 'Waiting Song');
    expect(item).toBeTruthy();
    expect(item.artist.stageName).toBe('Act rev_artist');
    expect(item.checks).toMatchObject({ fingerprinted: true, duplicates: [], external: { status: 'off' } });
  });

  it('lets a reviewer listen before deciding, but not the public', async () => {
    const item = (await h.call('GET', '/v1/admin/review/queue', mod.token)).json().items.find((i: any) => i.title === 'Waiting Song');
    const url = (await h.call('GET', `/v1/admin/tracks/${item.id}/stream-url`, mod.token)).json().url as string;
    expect((await h.call('GET', url)).statusCode).toBe(200);
    expect((await h.call('GET', `/v1/admin/tracks/${item.id}/stream-url`, listener.token)).statusCode).toBe(403);
    expect((await h.call('GET', `/v1/tracks/${item.id}/stream-url`)).statusCode).toBe(404); // the public route still refuses
  });

  it('approves a song: it goes live, the artist is told, and the decision is recorded', async () => {
    const item = (await h.call('GET', '/v1/admin/review/queue', mod.token)).json().items.find((i: any) => i.title === 'Waiting Song');
    expect((await h.call('POST', `/v1/admin/review/tracks/${item.id}/approve`, listener.token)).statusCode).toBe(403);
    expect((await h.call('POST', `/v1/admin/review/tracks/${item.id}/approve`, mod.token, { note: 'Sounds great' })).statusCode).toBe(200);
    expect(await isLive(h, item.id)).toBe(true);
    expect(h.messenger.sent.some((m) => m.to === artist.email && m.body.includes('"Waiting Song" was approved'))).toBe(true);
    const audit = (await h.call('GET', '/v1/admin/audit', admin.token)).json().entries;
    expect(audit.some((e: any) => e.action === 'track.approve' && e.targetId === item.id && e.actorId === mod.id)).toBe(true);
    expect((await h.call('POST', `/v1/admin/review/tracks/${item.id}/approve`, mod.token)).statusCode).toBe(409); // already decided
    expect((await h.call('GET', '/v1/admin/audit', mod.token)).statusCode).toBe(403); // the audit log is for admins
  });

  it('rejects with a reason the artist can read, and lets them fix and resubmit', async () => {
    const id = await readySong(h, artist, 'Needs Work');
    await submit(h, artist, id);
    expect((await h.call('POST', `/v1/admin/review/tracks/${id}/reject`, mod.token, {})).json().error).toBe('reason_required');
    expect((await h.call('POST', `/v1/admin/review/tracks/${id}/reject`, mod.token, { reason: 'low_quality', note: 'Please remaster it.' })).statusCode).toBe(200);

    const mine = (await h.call('GET', '/v1/artists/me/tracks', artist.token)).json().tracks.find((t: any) => t.id === id);
    expect(mine).toMatchObject({ status: 'rejected', rejectReason: 'low_quality', reviewNote: 'Please remaster it.' });
    expect(h.messenger.sent.some((m) => m.to === artist.email && m.body.includes('audio quality is too low'))).toBe(true);

    expect((await submit(h, artist, id)).status).toBe('in_review'); // submitted again
  });

  it('decides many songs at once, and says which ones it skipped', async () => {
    const ids = [await readySong(h, artist, 'Bulk 1'), await readySong(h, artist, 'Bulk 2'), await readySong(h, artist, 'Bulk 3')];
    for (const id of ids) await submit(h, artist, id);
    const stranger = randomUUID();
    const res = (await h.call('POST', '/v1/admin/review/bulk', mod.token, { action: 'approve', ids: [...ids, stranger] })).json();
    expect(res.done).toBe(3);
    expect(res.skipped).toEqual([stranger]);
    for (const id of ids) expect(await isLive(h, id)).toBe(true);
    expect((await h.call('POST', '/v1/admin/review/bulk', mod.token, { action: 'reject', ids })).json().error).toBe('reason_required');
  });

  it('takes a live song offline when new audio is uploaded, so approved songs cannot be swapped', async () => {
    const id = await readySong(h, artist, 'Swap Attempt');
    await submit(h, artist, id);
    await h.call('POST', `/v1/admin/review/tracks/${id}/approve`, mod.token);
    expect(await isLive(h, id)).toBe(true);
    await put(h, `/v1/artists/me/tracks/${id}/audio`, artist.token, wavSeed());
    expect(await isLive(h, id)).toBe(false);
    expect((await h.call('GET', '/v1/artists/me/tracks', artist.token)).json().tracks.find((t: any) => t.id === id).status).toBe('ready');
    expect((await submit(h, artist, id)).status).toBe('in_review');
  });
});

describe.skipIf(!hasFingerprints)('copyright checks on upload', () => {
  let h: Harness;
  let a: Account;
  let b: Account;
  let mod: Account;
  let original: Buffer;
  let originalId: string;

  beforeAll(async () => {
    h = await setup();
    a = await artistIn(h, 'orig_artist');
    b = await artistIn(h, 'copy_artist');
    mod = await staffIn(h, 'dup_mod', 'moderator');
    original = makeWav(15, 22_050, 777);
    originalId = await readySong(h, a, 'The Original', original);
    await submit(h, a, originalId);
    await h.call('POST', `/v1/admin/review/tracks/${originalId}/approve`, mod.token);
  }, 60_000);
  afterAll(async () => {
    await h.app.close();
    h.cleanup();
  });

  it('holds a copy of a song that is already on Vyro, whatever file format it comes in', async () => {
    const exact = await readySong(h, b, 'Exact Copy', original);
    const view = await submit(h, b, exact);
    expect(view.status).toBe('held');
    const item = (await h.call('GET', '/v1/admin/review/queue?status=held', mod.token)).json().items.find((i: any) => i.id === exact);
    expect(item.checks.duplicates[0]).toMatchObject({ trackId: originalId, artistName: 'Act orig_artist', sameArtist: false });
    expect(item.checks.duplicates[0].similarity).toBeGreaterThan(0.99);

    const mp3 = await reencode(original, 'mp3');
    const lossy = await readySong(h, b, 'Lossy Copy', mp3.data, mp3.type);
    expect((await submit(h, b, lossy)).status).toBe('held');
    const trimmed = await reencode(original, 'trimmed');
    const cut = await readySong(h, b, 'Trimmed Copy', trimmed.data, trimmed.type);
    expect((await submit(h, b, cut)).status).toBe('held');
  });

  it('lets a reviewer reject the copy as a duplicate', async () => {
    const queue = (await h.call('GET', '/v1/admin/review/queue?status=held', mod.token)).json().items;
    const copy = queue.find((i: any) => i.title === 'Exact Copy');
    expect((await h.call('POST', `/v1/admin/review/tracks/${copy.id}/reject`, mod.token, { reason: 'duplicate' })).statusCode).toBe(200);
    expect((await h.call('GET', '/v1/artists/me/tracks', b.token)).json().tracks.find((t: any) => t.id === copy.id).rejectReason).toBe('duplicate');
  });

  it('does not hold a different song, and does not hold an artist\'s own re-upload (it is only flagged)', async () => {
    const different = await readySong(h, b, 'Truly Different', makeWav(15, 22_050, 888));
    const view = await submit(h, b, different);
    expect(view.status).toBe('in_review');
    const mine = await readySong(h, a, 'Another Version', original);
    expect((await submit(h, a, mine)).status).toBe('in_review');
    const item = (await h.call('GET', '/v1/admin/review/queue', mod.token)).json().items.find((i: any) => i.id === mine);
    expect(item.checks.duplicates.some((d: any) => d.sameArtist)).toBe(true);
  });

  it('keeps recognizing a song after it has been taken down', async () => {
    const notice = await h.call('POST', '/v1/takedown-notices', null, {
      trackId: originalId,
      claimantName: 'Rights Holder',
      claimantEmail: 'rights@example.com',
      statement: 'This recording is mine and was uploaded without my permission.',
      signature: 'Rights Holder',
      goodFaith: true,
      accurateUnderPenalty: true,
    });
    expect(notice.statusCode).toBe(202);
    const again = await readySong(h, b, 'Re-upload After Takedown', original);
    expect((await submit(h, b, again)).status).toBe('held');
  });

  it('compares fingerprints sensibly', () => {
    const noise = (n: number, s: number) => Array.from({ length: n }, (_, i) => Math.imul(i + s, 2654435761) | 0);
    const a1 = noise(200, 1);
    expect(bitSimilarity(a1, a1).similarity).toBe(1);
    expect(bitSimilarity(a1, noise(200, 99999)).similarity).toBeLessThan(0.75);
    expect(bitSimilarity(a1, a1.slice(30)).similarity).toBeGreaterThan(0.99); // a copy with the start cut off
    expect(bitSimilarity(a1.slice(0, 10), a1.slice(0, 10)).similarity).toBe(0); // too short to compare
  });
});

describe('who can skip review', () => {
  it('never publishes audio that could not be fingerprinted, even when the policy is "none"', async () => {
    const h = await setup({ reviewPolicy: 'none', fingerprint: null });
    try {
      const u = await artistIn(h, 'nofp');
      const id = await readySong(h, u, 'Unchecked');
      expect((await submit(h, u, id)).status).toBe('in_review');
    } finally {
      await h.app.close();
      h.cleanup();
    }
  });

  it.skipIf(!hasFingerprints)('publishes clean songs at once when the policy is "none"', async () => {
    const h = await setup({ reviewPolicy: 'none' });
    try {
      const u = await artistIn(h, 'open_policy');
      const id = await readySong(h, u, 'Straight Through');
      expect((await submit(h, u, id)).status).toBe('published');
      expect(await isLive(h, id)).toBe(true);
    } finally {
      await h.app.close();
      h.cleanup();
    }
  });

  it.skipIf(!hasFingerprints)('trusts verified artists and artists with three approved songs, under "new_artists"', async () => {
    const h = await setup({ reviewPolicy: 'new_artists' });
    try {
      const mod = await staffIn(h, 'trust_mod', 'moderator');
      const newcomer = await artistIn(h, 'newcomer');
      for (let i = 1; i <= 3; i++) {
        const id = await readySong(h, newcomer, `Early ${i}`);
        expect((await submit(h, newcomer, id)).status).toBe('in_review');
        await h.call('POST', `/v1/admin/review/tracks/${id}/approve`, mod.token);
      }
      expect((await submit(h, newcomer, await readySong(h, newcomer, 'Fourth'))).status).toBe('published');

      const famous = await artistIn(h, 'famous');
      expect((await h.call('POST', `/v1/admin/artists/${famous.id}/verify`, mod.token, { verified: true })).statusCode).toBe(200);
      expect((await h.call('GET', '/v1/me', famous.token)).json().artist.verified).toBe(true);
      expect((await submit(h, famous, await readySong(h, famous, 'Verified Release'))).status).toBe('published');
    } finally {
      await h.app.close();
      h.cleanup();
    }
  });
});

describe.skipIf(!hasFingerprints)('lookup against released music', () => {
  const run = async (checker: CopyrightChecker) => {
    const h = await setup({ copyright: checker, reviewPolicy: 'none' });
    try {
      const u = await artistIn(h, 'lookup');
      return (await submit(h, u, await readySong(h, u, 'Looked Up'))).status as string;
    } finally {
      await h.app.close();
      h.cleanup();
    }
  };
  const hit: CopyrightMatch = { source: 'test', title: 'A Famous Song', artists: ['Famous Artist'], score: 0.97 };

  it('holds a song when the lookup finds released music', async () => {
    expect(await run({ check: async () => [hit] })).toBe('held');
  });

  it('lets a clean result through, and sends an unchecked one to a person', async () => {
    expect(await run({ check: async () => [] })).toBe('published');
    expect(await run({ check: async () => null })).toBe('in_review');
  });
});

describe('AcoustID lookup', () => {
  const checker = (body: unknown, ok = true) => new AcoustIdChecker('key', (async () => ({ ok, json: async () => body })) as unknown as typeof fetch);

  it('reads matches above the score threshold', async () => {
    const found = await checker({ status: 'ok', results: [{ score: 0.96, recordings: [{ title: 'Song', artists: [{ name: 'Someone' }] }] }, { score: 0.4, recordings: [{ title: 'Weak', artists: [] }] }] }).check({ compressed: 'AQAA', durationSec: 30 });
    expect(found).toEqual([{ source: 'acoustid', title: 'Song', artists: ['Someone'], score: 0.96 }]);
  });

  it('says "nothing found" with an empty list, and "could not check" with null', async () => {
    expect(await checker({ status: 'ok', results: [] }).check({ compressed: 'AQAA', durationSec: 30 })).toEqual([]);
    expect(await checker({ status: 'error' }).check({ compressed: 'AQAA', durationSec: 30 })).toBeNull();
    expect(await checker({}, false).check({ compressed: 'AQAA', durationSec: 30 })).toBeNull();
    const broken = new AcoustIdChecker('key', (async () => { throw new Error('offline'); }) as unknown as typeof fetch);
    expect(await broken.check({ compressed: 'AQAA', durationSec: 30 })).toBeNull();
  });
});

describe('copyright notices and strikes', () => {
  let h: Harness;
  let artist: Account;
  let mod: Account;
  let admin: Account;
  const notice = (trackId: string, extra: object = {}) =>
    h.call('POST', '/v1/takedown-notices', null, {
      trackId,
      claimantName: 'Rights Holder',
      claimantEmail: 'rights@example.com',
      statement: 'This recording is mine and was uploaded without my permission.',
      signature: 'Rights Holder',
      goodFaith: true,
      accurateUnderPenalty: true,
      ...extra,
    });

  async function liveSong(title: string) {
    const id = await readySong(h, artist, title);
    await submit(h, artist, id);
    await h.call('POST', `/v1/admin/review/tracks/${id}/approve`, mod.token);
    return id;
  }

  beforeAll(async () => {
    h = await setup({ reviewPolicy: 'all' });
    artist = await artistIn(h, 'strike_artist');
    mod = await staffIn(h, 'strike_mod', 'moderator');
    admin = await staffIn(h, 'strike_admin', 'admin');
  }, 60_000);
  afterAll(async () => {
    await h.app.close();
    h.cleanup();
  });

  it('takes a song offline at once, even for streaming addresses already handed out', async () => {
    const id = await liveSong('Disputed');
    const url = (await h.call('GET', `/v1/tracks/${id}/stream-url`)).json().url as string;
    expect((await h.call('GET', url)).statusCode).toBe(200);

    const res = await notice(id);
    expect(res.statusCode).toBe(202);
    expect(await isLive(h, id)).toBe(false);
    expect((await h.call('GET', url)).statusCode).toBe(404);
    expect(h.messenger.sent.some((m) => m.to === artist.email && m.body.includes('copyright notice'))).toBe(true);
    expect(h.messenger.sent.some((m) => m.to === 'rights@example.com')).toBe(true);
    expect((await h.call('GET', '/v1/artists/me/tracks', artist.token)).json().tracks.find((t: any) => t.id === id).status).toBe('taken_down');
    expect((await h.call('POST', `/v1/artists/me/tracks/${id}/publish`, artist.token)).json().error).toBe('taken_down');
  });

  it('checks the notice, and tells strangers nothing about private songs', async () => {
    const id = await liveSong('Another Disputed');
    expect((await notice(id, { statement: 'too short' })).statusCode).toBe(400);
    expect((await notice(id, { goodFaith: false })).statusCode).toBe(400);
    expect((await notice(randomUUID())).statusCode).toBe(404);
    const draft = (await h.call('POST', '/v1/artists/me/tracks', artist.token, { title: 'Private Draft' })).json().id;
    expect((await notice(draft)).statusCode).toBe(404);
    expect(await isLive(h, id)).toBe(true); // nothing happened to it
  });

  it('lets the artist send a counter-notice and a reviewer restore the song', async () => {
    const id = await liveSong('Counter Me');
    await notice(id);
    const mine = (await h.call('GET', '/v1/artists/me/takedowns', artist.token)).json().notices.find((n: any) => n.track.id === id);
    expect(mine.status).toBe('open');
    const body = { statement: 'I wrote and recorded this song myself and the notice is mistaken.', signature: 'Strike Artist', consent: true };
    expect((await h.call('POST', `/v1/artists/me/takedowns/${mine.id}/counter-notice`, artist.token, { ...body, consent: false })).statusCode).toBe(400);
    expect((await h.call('POST', `/v1/artists/me/takedowns/${mine.id}/counter-notice`, artist.token, body)).statusCode).toBe(200);
    expect((await h.call('POST', `/v1/artists/me/takedowns/${mine.id}/counter-notice`, artist.token, body)).json().error).toBe('cannot_counter_now');

    const pending = (await h.call('GET', '/v1/admin/takedowns', mod.token)).json().notices.find((n: any) => n.id === mine.id);
    expect(pending.status).toBe('counter_filed');
    expect(pending.counter.statement).toContain('I wrote and recorded');

    expect((await h.call('POST', `/v1/admin/takedowns/${mine.id}/resolve`, mod.token, { decision: 'restore' })).statusCode).toBe(200);
    expect(await isLive(h, id)).toBe(true);
    expect((await h.call('POST', `/v1/admin/takedowns/${mine.id}/resolve`, mod.token, { decision: 'restore' })).json().error).toBe('already_resolved');
  });

  it('suspends an artist after three upheld notices (repeat-infringer policy)', async () => {
    const victim = await artistIn(h, 'repeat_offender');
    const survivor = await readySong(h, victim, 'Their Other Song');
    await submit(h, victim, survivor);
    await h.call('POST', `/v1/admin/review/tracks/${survivor}/approve`, mod.token);
    expect(await isLive(h, survivor)).toBe(true);

    for (let i = 1; i <= 3; i++) {
      const id = await readySong(h, victim, `Infringing ${i}`);
      await submit(h, victim, id);
      await h.call('POST', `/v1/admin/review/tracks/${id}/approve`, mod.token);
      const n = (await notice(id)).json().noticeId as string;
      expect((await h.call('POST', `/v1/admin/takedowns/${n}/resolve`, mod.token, { decision: 'uphold' })).statusCode).toBe(200);
      const suspended = (await h.call('GET', '/v1/admin/artists?q=repeat_offender', mod.token)).json().artists[0];
      expect(suspended.strikes).toBe(i);
      expect(suspended.suspended).toBe(i === 3);
    }
    expect((await h.call('POST', '/v1/auth/login', null, { email: victim.email, password: 'correct-horse-battery' })).json().error).toBe('account_suspended');
    expect((await h.call('GET', '/v1/me', victim.token)).statusCode).toBe(403); // an access token they already had stops working
    expect((await h.call('POST', '/v1/auth/refresh', null, { refreshToken: victim.refreshToken })).statusCode).toBe(401);
    expect(await isLive(h, survivor)).toBe(false); // their other songs are hidden too
    expect((await h.call('GET', '/v1/admin/audit', admin.token)).json().entries.some((e: any) => e.action === 'user.suspend' && e.targetId === victim.id)).toBe(true);
  });
});

describe('suspensions and roles', () => {
  let h: Harness;
  let mod: Account;
  let admin: Account;
  let artist: Account;

  beforeAll(async () => {
    h = await setup({ reviewPolicy: 'none', fingerprint: null });
    mod = await staffIn(h, 'sus_mod', 'moderator');
    admin = await staffIn(h, 'sus_admin', 'admin');
    artist = await artistIn(h, 'sus_artist');
  }, 60_000);
  afterAll(async () => {
    await h.app.close();
    h.cleanup();
  });

  it('suspends and restores a person, signing them out everywhere', async () => {
    const live = await readySong(h, artist, 'Visible Song');
    await submit(h, artist, live);
    await h.call('POST', `/v1/admin/review/tracks/${live}/approve`, mod.token);
    expect(await isLive(h, live)).toBe(true);

    expect((await h.call('POST', `/v1/admin/users/${artist.id}/suspend`, mod.token, { reason: 'x' })).statusCode).toBe(400);
    expect((await h.call('POST', `/v1/admin/users/${artist.id}/suspend`, mod.token, { reason: 'Breaking the rules' })).statusCode).toBe(200);
    expect((await h.call('GET', '/v1/me', artist.token)).json().error).toBe('account_suspended');
    expect((await h.call('POST', '/v1/auth/login', null, { email: artist.email, password: 'correct-horse-battery' })).statusCode).toBe(403);
    expect(await isLive(h, live)).toBe(false);
    expect(h.messenger.sent.some((m) => m.to === artist.email && m.body.includes('Breaking the rules'))).toBe(true);

    expect((await h.call('POST', `/v1/admin/users/${artist.id}/unsuspend`, mod.token)).statusCode).toBe(200);
    expect((await h.call('POST', '/v1/auth/login', null, { email: artist.email, password: 'correct-horse-battery' })).statusCode).toBe(200);
    expect(await isLive(h, live)).toBe(true);
  });

  it('keeps staff safe from each other, and keeps role changes to admins', async () => {
    expect((await h.call('POST', `/v1/admin/users/${admin.id}/suspend`, mod.token, { reason: 'Because I can' })).statusCode).toBe(403);
    expect((await h.call('POST', `/v1/admin/users/${mod.id}/suspend`, admin.token, { reason: 'Because I can' })).statusCode).toBe(403);
    expect((await h.call('POST', `/v1/admin/users/${artist.id}/role`, mod.token, { role: 'admin' })).statusCode).toBe(403);
    expect((await h.call('POST', `/v1/admin/users/${admin.id}/role`, admin.token, { role: 'user' })).json().error).toBe('cannot_change_own_role');
    expect((await h.call('POST', `/v1/admin/users/${artist.id}/role`, admin.token, { role: 'moderator' })).statusCode).toBe(200);
    expect((await h.call('GET', '/v1/me', artist.token)).json().role).toBe('moderator');
    expect((await h.call('GET', '/v1/admin/review/queue', artist.token)).statusCode).toBe(200);
  });

  it('finds artists by name or username, and records verification in the audit log', async () => {
    const found = (await h.call('GET', '/v1/admin/artists?q=sus_artist', mod.token)).json().artists;
    expect(found[0]).toMatchObject({ stageName: 'Act sus_artist', suspended: false });
    expect((await h.call('GET', '/v1/admin/artists?q=%25', mod.token)).json().artists).toEqual([]);
    await h.call('POST', `/v1/admin/artists/${found[0].id}/verify`, mod.token, { verified: true });
    expect((await h.call('GET', '/v1/admin/audit', admin.token)).json().entries.some((e: any) => e.action === 'artist.verify')).toBe(true);
  });

  it('makes administrators from a list of confirmed email addresses', async () => {
    const unverified = (await h.call('POST', '/v1/auth/register', null, { email: 'boss@example.com', password: 'correct-horse-battery', displayName: 'Boss', username: 'boss_user', birthDate: '1990-01-01', acceptedTermsVersion: '2026-10' })).json();
    expect(await promoteAdmins(h.db, ['boss@example.com'])).toBe(0); // email not confirmed yet
    await h.call('POST', '/v1/auth/email/verify', unverified.accessToken, { code: h.messenger.lastCode('boss@example.com') });
    expect(await promoteAdmins(h.db, ['BOSS@example.com', 'nobody@example.com'])).toBe(1);
    expect((await h.call('GET', '/v1/me', unverified.accessToken)).json().role).toBe('admin');
    expect(await promoteAdmins(h.db, ['boss@example.com'])).toBe(0); // nothing left to change
  });
});

describe('MP3 files go through the same checks', () => {
  it.skipIf(!hasFingerprints)('fingerprints a real MP3 upload', async () => {
    const h = await setup();
    try {
      const u = await artistIn(h, 'mp3_fp');
      const mod = await staffIn(h, 'mp3_mod', 'moderator');
      const id = await readySong(h, u, 'Mp3 Song', await makeMp3(192), 'audio/mpeg');
      expect((await submit(h, u, id)).status).toBe('in_review');
      const item = (await h.call('GET', '/v1/admin/review/queue', mod.token)).json().items.find((i: any) => i.id === id);
      expect(item.checks.fingerprinted).toBe(true);
    } finally {
      await h.app.close();
      h.cleanup();
    }
  });
});
