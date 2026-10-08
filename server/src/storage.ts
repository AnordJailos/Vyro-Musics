import { createReadStream, createWriteStream } from 'node:fs';
import { mkdir, rename, rm, stat } from 'node:fs/promises';
import { dirname, join, resolve, sep } from 'node:path';
import { pipeline } from 'node:stream/promises';
import type { Readable } from 'node:stream';

/** Where uploaded files live. Local disk now; an S3-style store plugs in here later. */
export interface Storage {
  /** Saves a stream under a key and returns how many bytes were written. */
  put(key: string, source: Readable): Promise<number>;
  /** Opens a stream (optionally only a byte range, both ends included). */
  open(key: string, range?: { start: number; end: number }): Promise<{ stream: Readable; size: number }>;
  size(key: string): Promise<number | null>;
  delete(key: string): Promise<void>;
  /** Gives a real file path for tools such as ffmpeg. A remote store would download a temporary copy. */
  withLocalFile<T>(key: string, fn: (path: string) => Promise<T>): Promise<T>;
}

export class LocalDiskStorage implements Storage {
  private readonly root: string;

  constructor(root: string) {
    this.root = resolve(root);
  }

  private path(key: string): string {
    const full = resolve(join(this.root, key));
    if (full !== this.root && !full.startsWith(this.root + sep)) throw new Error('storage key escapes the storage folder');
    return full;
  }

  async put(key: string, source: Readable): Promise<number> {
    const target = this.path(key);
    await mkdir(dirname(target), { recursive: true });
    const temp = `${target}.part`;
    try {
      await pipeline(source, createWriteStream(temp));
      await rename(temp, target); // a half-written file never appears under the real name
    } catch (e) {
      await rm(temp, { force: true });
      throw e;
    }
    return (await stat(target)).size;
  }

  async open(key: string, range?: { start: number; end: number }) {
    const target = this.path(key);
    const size = (await stat(target)).size;
    return { stream: createReadStream(target, range ? { start: range.start, end: range.end } : undefined), size };
  }

  async size(key: string): Promise<number | null> {
    try {
      return (await stat(this.path(key))).size;
    } catch {
      return null;
    }
  }

  async delete(key: string): Promise<void> {
    await rm(this.path(key), { force: true });
  }

  async withLocalFile<T>(key: string, fn: (path: string) => Promise<T>): Promise<T> {
    return fn(this.path(key));
  }
}
