/** A recording that a lookup service says this audio matches. */
export interface CopyrightMatch {
  source: string;
  title: string;
  artists: string[];
  score: number;
}

/**
 * Checks audio against a database of released music. Returns the matches (an empty list
 * means nothing was found), or null when the check could not be done.
 */
export interface CopyrightChecker {
  check(input: { compressed: string; durationSec: number }): Promise<CopyrightMatch[] | null>;
}

/**
 * AcoustID / MusicBrainz lookup. Note that AcoustID's free service is for
 * non-commercial use; a commercial app needs an agreement with them, or a paid service
 * such as ACRCloud or Audible Magic behind this same interface.
 */
export class AcoustIdChecker implements CopyrightChecker {
  constructor(
    private readonly apiKey: string,
    private readonly fetchImpl: typeof fetch = fetch,
    private readonly url = 'https://api.acoustid.org/v2/lookup',
  ) {}

  async check({ compressed, durationSec }: { compressed: string; durationSec: number }): Promise<CopyrightMatch[] | null> {
    try {
      const res = await this.fetchImpl(this.url, {
        method: 'POST',
        headers: { 'content-type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ client: this.apiKey, duration: String(Math.max(1, Math.round(durationSec))), fingerprint: compressed, meta: 'recordings', format: 'json' }),
        signal: AbortSignal.timeout(15_000),
      });
      if (!res.ok) return null;
      const json = (await res.json()) as { status?: string; results?: { score?: number; recordings?: { title?: string; artists?: { name?: string }[] }[] }[] };
      if (json.status !== 'ok') return null;
      const matches: CopyrightMatch[] = [];
      for (const r of json.results ?? []) {
        if ((r.score ?? 0) < 0.85) continue;
        for (const rec of r.recordings ?? []) {
          matches.push({ source: 'acoustid', title: rec.title ?? 'Unknown title', artists: (rec.artists ?? []).map((a) => a.name ?? '').filter(Boolean), score: r.score ?? 0 });
        }
      }
      return matches;
    } catch {
      return null;
    }
  }
}
