/** Lower case, no accents, no punctuation, single spaces: so "Beyoncé!" and "beyonce" compare equal. */
export function normalize(text: string): string {
  return text
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/** Number of single-letter changes (including swapping two neighbours) between two words, or max + 1 when it is more than max. */
export function editDistance(a: string, b: string, max: number): number {
  if (Math.abs(a.length - b.length) > max) return max + 1;
  let prev2: number[] = [];
  let prev = Array.from({ length: b.length + 1 }, (_, j) => j);
  for (let i = 1; i <= a.length; i++) {
    const row = [i];
    let best = row[0]!;
    for (let j = 1; j <= b.length; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      let v = Math.min(prev[j]! + 1, row[j - 1]! + 1, prev[j - 1]! + cost);
      if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) v = Math.min(v, prev2[j - 2]! + 1);
      row.push(v);
      best = Math.min(best, v);
    }
    if (best > max) return max + 1;
    prev2 = prev;
    prev = row;
  }
  return Math.min(prev[b.length]!, max + 1);
}

/**
 * How many mistakes a typed word may have: none for one or two letters, one for ordinary words, two for long ones. A
 * three-letter word gets one slip only if the first letter is right, so short words do not match everything.
 */
function allowedMistakes(word: string, other: string): number {
  if (word.length >= 8) return 2;
  if (word.length >= 4) return 1;
  return word.length === 3 && other[0] === word[0] ? 1 : 0;
}

function wordScore(q: string, t: string): number {
  if (t === q) return 100;
  if (t.startsWith(q)) return 85;
  if (t.includes(q) && q.length >= 3) return 65;
  const allowed = allowedMistakes(q, t);
  if (allowed === 0) return 0;
  const whole = editDistance(q, t, allowed);
  if (whole <= allowed) return 50 - whole * 8;
  // someone typing the start of a longer word with a slip ("beyonse" for "beyoncee"); not for short words, which would match too much
  if (q.length < 5) return 0;
  const head = editDistance(q, t.slice(0, q.length), allowed);
  return head <= allowed ? 40 - head * 8 : 0;
}

/**
 * How well a text matches what someone typed, from 0 (no match) to 100 (the same). Every typed word has to match some word
 * of the text, exactly, as a start, or with a slip of the keys.
 */
export function matchScore(query: string, text: string): number {
  const q = normalize(query);
  const t = normalize(text);
  if (!q || !t) return 0;
  if (t === q) return 100;
  if (t.startsWith(q)) return 92;
  if (t.includes(q)) return 75;
  const words = t.split(' ');
  let total = 0;
  for (const qw of q.split(' ')) {
    const best = Math.max(...words.map((w) => wordScore(qw, w)));
    if (best === 0) return 0;
    total += best;
  }
  return Math.round(total / q.split(' ').length);
}
