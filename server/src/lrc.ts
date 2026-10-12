export interface LyricLine {
  /** When the line starts, in milliseconds. Null for plain (unsynced) lyrics. */
  timeMs: number | null;
  text: string;
}

export interface ParsedLyrics {
  synced: boolean;
  lines: LyricLine[];
}

export const MAX_LYRICS_CHARS = 100_000;
export const MAX_LYRICS_LINES = 3000;

const STAMP = /\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]/g;
const LEADING_STAMPS = /^(?:\s*\[\d{1,3}:\d{2}(?:[.:]\d{1,3})?\])+/;
const TAG_LINE = /^\[([A-Za-z#]+):(.*)\]$/;
const WORD_STAMP = /<\d{1,3}:\d{2}(?:[.:]\d{1,3})?>/g;

/**
 * Reads lyrics in the LRC format ("[01:23.45] a line"), including several time stamps on one line, the
 * [offset:+500] tag (a positive value makes lyrics appear sooner), and word-by-word stamps (which are ignored).
 * Text without time stamps is returned as plain lyrics.
 */
export function parseLyrics(raw: string): ParsedLyrics {
  const text = raw.replace(/^\uFEFF/, '').replace(/\r\n?/g, '\n');
  let offset = 0;
  const stamped: { timeMs: number; text: string; order: number }[] = [];
  const plain: string[] = [];
  let order = 0;

  for (const original of text.split('\n')) {
    const line = original.trim();
    const tag = line.match(TAG_LINE);
    if (tag && !/^\d/.test(tag[1]!)) {
      if (tag[1]!.toLowerCase() === 'offset') {
        const n = Number(tag[2]!.trim());
        if (Number.isFinite(n)) offset = n;
      }
      continue; // title, artist, album and other tags are not lyrics
    }
    const lead = line.match(LEADING_STAMPS);
    if (!lead) {
      plain.push(original.replace(/\s+$/, ''));
      continue;
    }
    const content = line.slice(lead[0].length).replace(WORD_STAMP, '').trim();
    for (const m of lead[0].matchAll(STAMP)) {
      const minutes = Number(m[1]);
      const seconds = Number(m[2]);
      const ms = m[3] ? Number(m[3].padEnd(3, '0')) : 0;
      stamped.push({ timeMs: Math.max(0, (minutes * 60 + seconds) * 1000 + ms - offset), text: content, order: order++ });
    }
  }

  if (stamped.length > 0) {
    stamped.sort((a, b) => a.timeMs - b.timeMs || a.order - b.order);
    const lines: LyricLine[] = [];
    for (const s of stamped) {
      const previous = lines[lines.length - 1];
      if (s.text === '' && (!previous || previous.text === '')) continue; // no leading or doubled gaps
      lines.push({ timeMs: s.timeMs, text: s.text });
    }
    return { synced: true, lines: lines.slice(0, MAX_LYRICS_LINES) };
  }

  const lines: LyricLine[] = [];
  for (const p of plain) {
    if (p === '' && (lines.length === 0 || lines[lines.length - 1]!.text === '')) continue;
    lines.push({ timeMs: null, text: p });
  }
  while (lines.length > 0 && lines[lines.length - 1]!.text === '') lines.pop();
  return { synced: false, lines: lines.slice(0, MAX_LYRICS_LINES) };
}
