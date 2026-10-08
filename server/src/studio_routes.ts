import { createReadStream } from 'node:fs';
import { rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { Readable, Transform } from 'node:stream';
import { z } from 'zod';
import { inspectAudio, qualityProblem } from './audio.js';
import type { Ctx } from './context.js';
import { OWNER_COLUMNS, ownerView } from './track_views.js';

const trackBody = z.object({
  title: z.string().trim().min(1).max(120),
  genre: z.string().trim().toLowerCase().min(1).max(40).default('other'),
  durationMs: z.number().int().min(1000).max(21_600_000).optional(),
  explicit: z.boolean().default(false),
  allowMixing: z.boolean().default(true),
  allowDownload: z.boolean().default(true),
});
const trackPatch = z.object({
  title: z.string().trim().min(1).max(120).optional(),
  genre: z.string().trim().toLowerCase().min(1).max(40).optional(),
  explicit: z.boolean().optional(),
  allowMixing: z.boolean().optional(),
  allowDownload: z.boolean().optional(),
});
const idParam = z.object({ id: z.uuid() });

const MAX_COVER_BYTES = 5 * 1024 * 1024;

class TooLarge extends Error {}

/** Passes a stream through, failing once more than [max] bytes have gone by. */
function limited(source: Readable, max: number): Readable {
  let seen = 0;
  let over = false;
  const counter = new Transform({
    transform(chunk: Buffer, _enc, cb) {
      if (over) return cb(); // anything arriving after the limit was hit is simply dropped
      seen += chunk.length;
      if (seen > max) {
        over = true;
        cb(new TooLarge());
      } else {
        cb(null, chunk);
      }
    },
  });
  // The failure reaches the caller through the pipeline; this keeps a late error from crashing the server.
  counter.on('error', () => {});
  source.on('error', (e) => counter.destroy(e));
  return source.pipe(counter);
}

function sniffImage(head: Buffer): string | null {
  if (head.length >= 3 && head[0] === 0xff && head[1] === 0xd8 && head[2] === 0xff) return 'image/jpeg';
  if (head.length >= 8 && head.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'image/png';
  if (head.length >= 12 && head.subarray(0, 4).toString('latin1') === 'RIFF' && head.subarray(8, 12).toString('latin1') === 'WEBP') return 'image/webp';
  return null;
}

async function firstBytes(ctx: Ctx, key: string, n: number): Promise<Buffer> {
  const { stream } = await ctx.storage.open(key, { start: 0, end: n - 1 });
  const chunks: Buffer[] = [];
  for await (const c of stream) chunks.push(c as Buffer);
  return Buffer.concat(chunks);
}

export function registerStudioRoutes(ctx: Ctx) {
  const { app, db, now, storage, invalid, requireUser } = ctx;

  const requireArtist = async (req: any, reply: any) => {
    const ok = (await db.query('select 1 from artist_profiles where user_id = $1', [req.userId])).rows.length > 0;
    if (!ok) return reply.code(403).send({ error: 'artist_only' });
  };
  const artistOnly = { preHandler: [requireUser, requireArtist] };

  const owned = async (id: string, artistId: string | null) =>
    (await db.query<any>('select id, status, audio_key, stream_key, cover_key from tracks where id = $1 and artist_id = $2', [id, artistId])).rows[0];

  const view = async (id: string) => ownerView((await db.query<any>(`select ${OWNER_COLUMNS} from tracks t where t.id = $1`, [id])).rows[0]);

  app.post('/v1/artists/me/tracks', artistOnly, async (req, reply) => {
    const parsed = trackBody.safeParse(req.body);
    if (!parsed.success) return invalid(reply, parsed.error);
    const b = parsed.data;
    const row = (
      await db.query<{ id: string }>(
        'insert into tracks (artist_id, title, genre, duration_ms, explicit, allow_mixing, allow_download, created_at) values ($1, $2, $3, $4, $5, $6, $7, $8::timestamptz) returning id',
        [req.userId, b.title, b.genre, b.durationMs ?? 1000, b.explicit, b.allowMixing, b.allowDownload, now().toISOString()],
      )
    ).rows[0]!;
    return reply.code(201).send(await view(row.id));
  });

  app.get('/v1/artists/me/tracks', artistOnly, async (req) => {
    const rows = (await db.query<any>(`select ${OWNER_COLUMNS} from tracks t where t.artist_id = $1 and t.status <> 'removed' order by t.created_at desc`, [req.userId])).rows;
    return { tracks: rows.map(ownerView) };
  });

  app.patch('/v1/artists/me/tracks/:id', artistOnly, async (req, reply) => {
    const p = idParam.safeParse(req.params);
    const b = trackPatch.safeParse(req.body);
    if (!p.success) return invalid(reply, p.error);
    if (!b.success) return invalid(reply, b.error);
    const t = await owned(p.data.id, req.userId);
    if (!t || t.status === 'removed') return reply.code(404).send({ error: 'not_found' });
    const v = b.data;
    await db.query(
      `update tracks set title = coalesce($2, title), genre = coalesce($3, genre), explicit = coalesce($4::boolean, explicit),
              allow_mixing = coalesce($5::boolean, allow_mixing), allow_download = coalesce($6::boolean, allow_download) where id = $1`,
      [t.id, v.title ?? null, v.genre ?? null, v.explicit ?? null, v.allowMixing ?? null, v.allowDownload ?? null],
    );
    return view(t.id);
  });

  // The song file goes in the request body (Content-Type: audio/...). It is checked, measured and, for lossless
  // uploads, turned into a smaller streaming copy.
  app.put('/v1/artists/me/tracks/:id/audio', artistOnly, async (req, reply) => {
    const p = idParam.safeParse(req.params);
    if (!p.success) return invalid(reply, p.error);
    const t = await owned(p.data.id, req.userId);
    if (!t || t.status === 'removed') return reply.code(404).send({ error: 'not_found' });
    if (!(req.body instanceof Readable)) return reply.code(415).send({ error: 'send_the_file_as_the_request_body' });

    const stamp = now().getTime();
    const masterKey = `tracks/${t.id}/master-${stamp}`;
    try {
      await storage.put(masterKey, limited(req.body, ctx.maxAudioBytes));
    } catch (e) {
      req.body.destroy();
      if (e instanceof TooLarge) return reply.header('connection', 'close').code(413).send({ error: 'file_too_large' });
      throw e;
    }

    const info = await inspectAudio(storage, masterKey);
    if (!info) {
      await storage.delete(masterKey);
      return reply.code(415).send({ error: 'unsupported_audio' });
    }
    const problem = qualityProblem(info);
    if (problem) {
      await storage.delete(masterKey);
      return reply.code(422).send({ error: problem });
    }

    let loudness: number | null = null;
    let stream: { key: string; mime: string; bytes: number } | null = null;
    if (ctx.transcoder) {
      loudness = await storage.withLocalFile(masterKey, (path) => ctx.transcoder!.loudness(path));
      if (info.lossless) {
        const streamKey = `tracks/${t.id}/stream-${stamp}.m4a`;
        const temp = join(tmpdir(), `vyro-${randomUUID()}.m4a`);
        try {
          await storage.withLocalFile(masterKey, (path) => ctx.transcoder!.toAac(path, temp));
          stream = { key: streamKey, mime: 'audio/mp4', bytes: await storage.put(streamKey, createReadStream(temp)) };
        } catch {
          stream = null; // keep going: the master can be streamed as it is
        } finally {
          await rm(temp, { force: true });
        }
      }
    }

    const masterBytes = (await storage.size(masterKey)) ?? 0;
    await db.query(
      `update tracks set audio_key = $2, audio_mime = $3, audio_bytes = $4, stream_key = $5, stream_mime = $6, stream_bytes = $7,
              codec = $8, bitrate_kbps = $9, sample_rate = $10, lossless = $11, loudness_lufs = $12, duration_ms = $13,
              status = case when status = 'published' then 'published' else 'ready' end where id = $1`,
      [t.id, masterKey, info.mime, masterBytes, stream?.key ?? null, stream?.mime ?? null, stream?.bytes ?? null, info.codec, info.bitrateKbps, info.sampleRate, info.lossless, loudness, info.durationMs],
    );
    for (const old of [t.audio_key, t.stream_key]) if (old) await storage.delete(old);
    return view(t.id);
  });

  app.put('/v1/artists/me/tracks/:id/cover', artistOnly, async (req, reply) => {
    const p = idParam.safeParse(req.params);
    if (!p.success) return invalid(reply, p.error);
    const t = await owned(p.data.id, req.userId);
    if (!t || t.status === 'removed') return reply.code(404).send({ error: 'not_found' });
    if (!(req.body instanceof Readable)) return reply.code(415).send({ error: 'send_the_file_as_the_request_body' });
    const key = `tracks/${t.id}/cover-${now().getTime()}`;
    try {
      await storage.put(key, limited(req.body, MAX_COVER_BYTES));
    } catch (e) {
      req.body.destroy();
      if (e instanceof TooLarge) return reply.header('connection', 'close').code(413).send({ error: 'file_too_large' });
      throw e;
    }
    const mime = sniffImage(await firstBytes(ctx, key, 16));
    if (!mime) {
      await storage.delete(key);
      return reply.code(415).send({ error: 'unsupported_image' });
    }
    await db.query('update tracks set cover_key = $2, cover_mime = $3 where id = $1', [t.id, key, mime]);
    if (t.cover_key) await storage.delete(t.cover_key);
    return view(t.id);
  });

  app.post('/v1/artists/me/tracks/:id/publish', artistOnly, async (req, reply) => {
    const p = idParam.safeParse(req.params);
    if (!p.success) return invalid(reply, p.error);
    const t = await owned(p.data.id, req.userId);
    if (!t || t.status === 'removed') return reply.code(404).send({ error: 'not_found' });
    if (!t.audio_key) return reply.code(409).send({ error: 'upload_audio_first' });
    await db.query("update tracks set status = 'published', published_at = coalesce(published_at, $2::timestamptz) where id = $1", [t.id, now().toISOString()]);
    return view(t.id);
  });

  app.post('/v1/artists/me/tracks/:id/unpublish', artistOnly, async (req, reply) => {
    const p = idParam.safeParse(req.params);
    if (!p.success) return invalid(reply, p.error);
    const t = await owned(p.data.id, req.userId);
    if (!t || t.status === 'removed') return reply.code(404).send({ error: 'not_found' });
    await db.query("update tracks set status = case when audio_key is null then 'draft' else 'ready' end where id = $1", [t.id]);
    return view(t.id);
  });

  // Removing a song deletes its files. The row stays so past plays keep adding up in the artist's statistics.
  app.delete('/v1/artists/me/tracks/:id', artistOnly, async (req, reply) => {
    const p = idParam.safeParse(req.params);
    if (!p.success) return invalid(reply, p.error);
    const t = await owned(p.data.id, req.userId);
    if (!t || t.status === 'removed') return reply.code(404).send({ error: 'not_found' });
    for (const key of [t.audio_key, t.stream_key, t.cover_key]) if (key) await storage.delete(key);
    await db.query(
      "update tracks set status = 'removed', audio_key = null, stream_key = null, cover_key = null, audio_mime = null, stream_mime = null, cover_mime = null where id = $1",
      [t.id],
    );
    return reply.code(204).send();
  });
}
