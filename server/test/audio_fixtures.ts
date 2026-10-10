import { execFile } from 'node:child_process';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { promisify } from 'node:util';

const run = promisify(execFile);

/** A small deterministic random-number generator, so "recording number 7" is always the same sound. */
function mulberry32(seed: number) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/**
 * A mono 16-bit WAV file. Without a seed it is a plain sine tone. With a seed it is noise that is different for
 * every seed, so two songs with different seeds do not sound alike to a fingerprint (and the same seed always does).
 */
export function makeWav(seconds: number, sampleRate = 22_050, seed?: number): Buffer {
  const samples = Math.round(seconds * sampleRate);
  const data = Buffer.alloc(samples * 2);
  const rand = seed === undefined ? null : mulberry32(seed);
  for (let i = 0; i < samples; i++) {
    const v = rand ? (rand() * 2 - 1) * 9_000 : Math.sin((2 * Math.PI * 440 * i) / sampleRate) * 12_000;
    data.writeInt16LE(Math.round(v), i * 2);
  }
  const header = Buffer.alloc(44);
  header.write('RIFF', 0);
  header.writeUInt32LE(36 + data.length, 4);
  header.write('WAVEfmt ', 8);
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20); // PCM
  header.writeUInt16LE(1, 22); // mono
  header.writeUInt32LE(sampleRate, 24);
  header.writeUInt32LE(sampleRate * 2, 28);
  header.writeUInt16LE(2, 32);
  header.writeUInt16LE(16, 34);
  header.write('data', 36);
  header.writeUInt32LE(data.length, 40);
  return Buffer.concat([header, data]);
}

/** A real MP3 made with ffmpeg (tests that need it are skipped when ffmpeg is not installed). */
export async function makeMp3(kbps: number, seconds = 15): Promise<Buffer> {
  const dir = await mkdtemp(join(tmpdir(), 'vyro-mp3-'));
  const out = join(dir, 'tone.mp3');
  try {
    await run('ffmpeg', ['-v', 'error', '-f', 'lavfi', '-i', `sine=frequency=440:duration=${seconds}`, '-b:a', `${kbps}k`, '-ar', '44100', '-y', out]);
    return await readFile(out);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

/** Not a real picture, but it starts with the PNG signature, which is all the upload check looks at. */
export const fakePng = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.alloc(200, 1)]);

/** The same recording as an MP3, or with the first seconds cut off: what someone re-uploading a song would do. */
export async function reencode(wav: Buffer, how: 'mp3' | 'trimmed'): Promise<{ data: Buffer; type: string }> {
  const dir = await mkdtemp(join(tmpdir(), 'vyro-re-'));
  try {
    await writeFile(join(dir, 'in.wav'), wav);
    if (how === 'mp3') {
      await run('ffmpeg', ['-v', 'error', '-i', join(dir, 'in.wav'), '-b:a', '128k', '-y', join(dir, 'out.mp3')]);
      return { data: await readFile(join(dir, 'out.mp3')), type: 'audio/mpeg' };
    }
    await run('ffmpeg', ['-v', 'error', '-ss', '2', '-i', join(dir, 'in.wav'), '-y', join(dir, 'out.wav')]);
    return { data: await readFile(join(dir, 'out.wav')), type: 'audio/wav' };
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}
