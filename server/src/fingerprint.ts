import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import type { Db } from './db.js';

const run = promisify(execFile);

/** Two recordings count as the same when their fingerprints are at least this alike (random audio scores about 0.5 to 0.75). */
export const MATCH_SIMILARITY = 0.88;
/** How many identical sub-fingerprints, at one consistent time offset, make a candidate worth comparing. */
const MIN_INDEX_HITS = 8;
const MAX_SHIFT = 60; // about 7 seconds of trimming or lead-in either way
const MIN_OVERLAP = 40; // about 5 seconds

/** Makes Chromaprint fingerprints: one 32-bit number per ~0.12 s of audio. */
export interface FingerprintTool {
  readonly name: string;
  /** The raw fingerprint (signed 32-bit numbers), from the first two minutes. */
  raw(path: string): Promise<number[] | null>;
  /** The compact text form that online lookup services expect. */
  compressed(path: string, durationSec: number): Promise<{ durationSec: number; fingerprint: string } | null>;
}

export class FpcalcTool implements FingerprintTool {
  readonly name = 'fpcalc';
  constructor(private readonly bin = 'fpcalc') {}

  async raw(path: string) {
    const { stdout } = await run(this.bin, ['-raw', '-json', '-length', '120', path], { timeout: 120_000, maxBuffer: 16 * 1024 * 1024 });
    const parsed = JSON.parse(stdout) as { fingerprint?: number[] };
    return Array.isArray(parsed.fingerprint) ? parsed.fingerprint.map((v) => v | 0) : null;
  }

  async compressed(path: string) {
    const { stdout } = await run(this.bin, ['-json', '-length', '120', path], { timeout: 120_000, maxBuffer: 16 * 1024 * 1024 });
    const parsed = JSON.parse(stdout) as { duration?: number; fingerprint?: string };
    return typeof parsed.fingerprint === 'string' ? { durationSec: Math.round(parsed.duration ?? 0), fingerprint: parsed.fingerprint } : null;
  }
}

/** Same fingerprints (identical numbers), made with ffmpeg's Chromaprint output when fpcalc is not installed. */
export class FfmpegChromaprintTool implements FingerprintTool {
  readonly name = 'ffmpeg';
  constructor(private readonly bin = 'ffmpeg') {}

  async raw(path: string) {
    const { stdout } = (await run(this.bin, ['-nostdin', '-v', 'error', '-i', path, '-t', '120', '-f', 'chromaprint', '-fp_format', 'raw', '-'], {
      timeout: 120_000,
      maxBuffer: 16 * 1024 * 1024,
      encoding: 'buffer',
    })) as unknown as { stdout: Buffer };
    const n = Math.floor(stdout.length / 4);
    return n === 0 ? null : Array.from({ length: n }, (_, i) => stdout.readInt32LE(i * 4));
  }

  async compressed(path: string, durationSec: number) {
    const { stdout } = await run(this.bin, ['-nostdin', '-v', 'error', '-i', path, '-t', '120', '-f', 'chromaprint', '-fp_format', 'base64', '-'], {
      timeout: 120_000,
      maxBuffer: 16 * 1024 * 1024,
    });
    const text = stdout.trim();
    return text ? { durationSec: Math.round(durationSec), fingerprint: text } : null;
  }
}

/** Finds a fingerprint tool: fpcalc first, then ffmpeg when it was built with Chromaprint. */
export async function detectFingerprintTool(): Promise<FingerprintTool | null> {
  const fpcalc = process.env.FPCALC_PATH ?? 'fpcalc';
  try {
    await run(fpcalc, ['-version'], { timeout: 10_000 });
    return new FpcalcTool(fpcalc);
  } catch {
    // fall through to ffmpeg
  }
  const ffmpeg = process.env.FFMPEG_PATH ?? 'ffmpeg';
  try {
    const { stdout } = await run(ffmpeg, ['-hide_banner', '-muxers'], { timeout: 10_000 });
    if (/chromaprint/i.test(stdout)) return new FfmpegChromaprintTool(ffmpeg);
  } catch {
    // no ffmpeg either
  }
  return null;
}

function popcount(x: number): number {
  x = x - ((x >>> 1) & 0x55555555);
  x = (x & 0x33333333) + ((x >>> 2) & 0x33333333);
  x = (x + (x >>> 4)) & 0x0f0f0f0f;
  return Math.imul(x, 0x01010101) >>> 24;
}

/** How alike two fingerprints are (0 to 1), trying small time shifts so trimmed copies still match. */
export function bitSimilarity(a: number[], b: number[]): { similarity: number; shift: number } {
  let best = { similarity: 0, shift: 0 };
  for (let s = -MAX_SHIFT; s <= MAX_SHIFT; s++) {
    const i0 = Math.max(0, s);
    const j0 = Math.max(0, -s);
    const len = Math.min(a.length - i0, b.length - j0);
    if (len < MIN_OVERLAP) continue;
    let bits = 0;
    for (let k = 0; k < len; k++) bits += popcount((a[i0 + k]! ^ b[j0 + k]!) | 0);
    const similarity = 1 - bits / (32 * len);
    if (similarity > best.similarity) best = { similarity, shift: s };
  }
  return best;
}

export async function storeFingerprint(db: Db, trackId: string, raw: number[], durationSec: number, now: Date) {
  await deleteFingerprint(db, trackId);
  await db.query('insert into track_fingerprints (track_id, duration_s, raw, created_at) values ($1, $2, $3::int[], $4::timestamptz)', [trackId, durationSec, raw, now.toISOString()]);
  const positions = raw.map((_, i) => i);
  await db.query('insert into fingerprint_hashes (track_id, hash, pos) select $1, h, p from unnest($2::int[], $3::int[]) as t(h, p)', [trackId, raw, positions]);
}

export async function deleteFingerprint(db: Db, trackId: string) {
  await db.query('delete from fingerprint_hashes where track_id = $1', [trackId]);
  await db.query('delete from track_fingerprints where track_id = $1', [trackId]);
}

export interface FingerprintMatch {
  trackId: string;
  similarity: number;
}

/** Other recordings in the catalog that sound the same as [raw]. */
export async function findMatches(db: Db, raw: number[], excludeTrackId: string | null): Promise<FingerprintMatch[]> {
  if (raw.length < MIN_OVERLAP) return [];
  const candidates = (
    await db.query<{ track_id: string }>(
      `select h.track_id, count(*)::int as hits
       from unnest($1::int[], $2::int[]) as q(hash, pos)
       join fingerprint_hashes h on h.hash = q.hash
       join tracks ht on ht.id = h.track_id and ht.status in ('published', 'in_review', 'taken_down')
       where ($3::uuid is null or h.track_id <> $3::uuid)
       group by h.track_id, (h.pos - q.pos)
       having count(*) >= $4
       order by hits desc limit 25`,
      [raw, raw.map((_, i) => i), excludeTrackId, MIN_INDEX_HITS],
    )
  ).rows;
  const seen = new Set<string>();
  const matches: FingerprintMatch[] = [];
  for (const c of candidates) {
    if (seen.has(c.track_id)) continue;
    seen.add(c.track_id);
    const stored = (await db.query<{ raw: number[] }>('select raw from track_fingerprints where track_id = $1', [c.track_id])).rows[0];
    if (!stored) continue;
    const { similarity } = bitSimilarity(raw, stored.raw);
    if (similarity >= MATCH_SIMILARITY) matches.push({ trackId: c.track_id, similarity: Math.round(similarity * 1000) / 1000 });
  }
  return matches.sort((x, y) => y.similarity - x.similarity);
}
