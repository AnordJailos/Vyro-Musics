import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { parseStream } from 'music-metadata';
import type { Storage } from './storage.js';

const run = promisify(execFile);

export interface AudioInfo {
  codec: string;
  durationMs: number;
  bitrateKbps: number | null;
  sampleRate: number | null;
  lossless: boolean;
}

export const MIN_SECONDS = 10;
export const MAX_SECONDS = 6 * 3600;
export const MIN_LOSSY_KBPS = 128;
export const MIN_SAMPLE_RATE = 22_050;

const FORMATS: { match: RegExp; mime: string }[] = [
  { match: /mpeg/i, mime: 'audio/mpeg' },
  { match: /flac/i, mime: 'audio/flac' },
  { match: /wav/i, mime: 'audio/wav' },
  { match: /aiff|aifc/i, mime: 'audio/aiff' },
  { match: /m4a|mp4|isom|aac/i, mime: 'audio/mp4' },
  { match: /ogg|opus|vorbis/i, mime: 'audio/ogg' },
];

/** Reads an uploaded file and says what it is. Returns null for anything that is not supported audio. */
export async function inspectAudio(storage: Storage, key: string): Promise<(AudioInfo & { mime: string }) | null> {
  try {
    const { stream, size } = await storage.open(key);
    const meta = await parseStream(stream, { size }, { duration: true, skipCovers: true });
    const container = `${meta.format.container ?? ''} ${meta.format.codec ?? ''}`;
    const known = FORMATS.find((f) => f.match.test(container));
    const seconds = meta.format.duration;
    if (!known || !seconds || !Number.isFinite(seconds)) return null;
    const lossless = meta.format.lossless === true || /flac|wav|aiff|aifc/i.test(container);
    return {
      codec: (meta.format.codec ?? meta.format.container ?? 'unknown').toLowerCase(),
      durationMs: Math.round(seconds * 1000),
      bitrateKbps: meta.format.bitrate ? Math.round(meta.format.bitrate / 1000) : null,
      sampleRate: meta.format.sampleRate ?? null,
      lossless,
      mime: known.mime,
    };
  } catch {
    return null;
  }
}

export type QualityProblem = 'too_short' | 'too_long' | 'bitrate_too_low' | 'sample_rate_too_low';

/** Upload quality gate (STU-06): long enough, and not an obviously poor recording. */
export function qualityProblem(info: AudioInfo): QualityProblem | null {
  if (info.durationMs < MIN_SECONDS * 1000) return 'too_short';
  if (info.durationMs > MAX_SECONDS * 1000) return 'too_long';
  if (!info.lossless && info.bitrateKbps !== null && info.bitrateKbps < MIN_LOSSY_KBPS) return 'bitrate_too_low';
  if (info.lossless && info.sampleRate !== null && info.sampleRate < MIN_SAMPLE_RATE) return 'sample_rate_too_low';
  return null;
}

/** Heavy audio work done with ffmpeg. */
export interface Transcoder {
  /** Makes a streaming copy (AAC in an m4a file) of a lossless master. */
  toAac(inputPath: string, outputPath: string): Promise<void>;
  /** Integrated loudness in LUFS (EBU R128), or null when it cannot be measured. */
  loudness(inputPath: string): Promise<number | null>;
}

export class FfmpegTranscoder implements Transcoder {
  constructor(private readonly bin: string = 'ffmpeg') {}

  /** Returns a transcoder when ffmpeg can be run, otherwise null. */
  static async detect(bin = process.env.FFMPEG_PATH ?? 'ffmpeg'): Promise<FfmpegTranscoder | null> {
    try {
      await run(bin, ['-version'], { timeout: 10_000 });
      return new FfmpegTranscoder(bin);
    } catch {
      return null;
    }
  }

  async toAac(inputPath: string, outputPath: string): Promise<void> {
    await run(this.bin, ['-nostdin', '-y', '-i', inputPath, '-vn', '-c:a', 'aac', '-b:a', '256k', '-movflags', '+faststart', '-f', 'ipod', outputPath], {
      timeout: 15 * 60_000,
      maxBuffer: 16 * 1024 * 1024,
    });
  }

  async loudness(inputPath: string): Promise<number | null> {
    try {
      const { stderr } = await run(this.bin, ['-nostdin', '-i', inputPath, '-vn', '-af', 'ebur128=framelog=quiet', '-f', 'null', '-'], {
        timeout: 5 * 60_000,
        maxBuffer: 16 * 1024 * 1024,
      });
      const matches = [...stderr.matchAll(/\bI:\s+(-?\d+(?:\.\d+)?)\s+LUFS/g)];
      const last = matches.at(-1)?.[1];
      return last === undefined ? null : Number(last);
    } catch {
      return null;
    }
  }
}
