import type { Db } from './db.js';

export const DAY = 86_400_000;
export const startOfUtcDay = (d: Date) => new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
const round4 = (n: number) => Math.round(n * 10_000) / 10_000;
const ratio = (a: number, b: number) => (b === 0 ? 0 : round4(a / b));

export const ARTIST_RANGES = { '7d': 7, '28d': 28, '90d': 90, '365d': 365 } as const;
export type ArtistRange = keyof typeof ARTIST_RANGES;

/** A listener with at least this many valid plays of an artist in the period is a "super listener". */
export const SUPER_LISTENER_PLAYS = 5;

/**
 * A play counts as a stream once it reaches 30 seconds, or half the track for very short tracks.
 * (The rule lives in SQL at ingest time; this constant documents it for the API consumer.)
 */
export const VALID_STREAM_MS = 30_000;

const delta = (value: number, previous: number) => ({ value, previous });

export async function artistStats(db: Db, artistId: string, range: ArtistRange, now: Date, minCohort: number) {
  const days = ARTIST_RANGES[range];
  const end = new Date(startOfUtcDay(now).getTime() + DAY);
  const start = new Date(end.getTime() - days * DAY);
  const prev = new Date(start.getTime() - days * DAY);
  const [S, E, P, N] = [start.toISOString(), end.toISOString(), prev.toISOString(), now.toISOString()];

  const summary = (
    await db.query<any>(
      `select
         count(*) filter (where valid and started_at >= $2::timestamptz and started_at < $3::timestamptz)::int as plays,
         count(distinct user_id) filter (where valid and started_at >= $2::timestamptz and started_at < $3::timestamptz)::int as listeners,
         count(*) filter (where valid and started_at >= $4::timestamptz and started_at < $2::timestamptz)::int as prev_plays,
         count(distinct user_id) filter (where valid and started_at >= $4::timestamptz and started_at < $2::timestamptz)::int as prev_listeners
       from listen_events
       where artist_id = $1 and started_at >= $4::timestamptz and started_at < $3::timestamptz`,
      [artistId, S, E, P],
    )
  ).rows[0];

  const follows = (
    await db.query<any>(
      `select
         count(*)::int as total,
         count(*) filter (where created_at >= $2::timestamptz and created_at < $3::timestamptz)::int as gained,
         count(*) filter (where created_at >= $4::timestamptz and created_at < $2::timestamptz)::int as prev_gained
       from follows where artist_id = $1`,
      [artistId, S, E, P],
    )
  ).rows[0];

  const saves = (
    await db.query<any>(
      `select
         count(*) filter (where s.created_at >= $2::timestamptz and s.created_at < $3::timestamptz)::int as saves,
         count(*) filter (where s.created_at >= $4::timestamptz and s.created_at < $2::timestamptz)::int as prev_saves
       from saves s join tracks t on t.id = s.track_id where t.artist_id = $1`,
      [artistId, S, E, P],
    )
  ).rows[0];

  const daily = (
    await db.query<any>(
      `select to_char(d at time zone 'UTC', 'YYYY-MM-DD') as day,
              count(e.id) filter (where e.valid)::int as plays,
              count(distinct e.user_id) filter (where e.valid)::int as listeners
       from generate_series($2::timestamptz, $3::timestamptz - interval '1 day', interval '1 day') as d
       left join listen_events e on e.artist_id = $1 and e.started_at >= d and e.started_at < d + interval '1 day'
       group by d order by d`,
      [artistId, S, E],
    )
  ).rows;

  // Last 48 hours, hour by hour ("right now" view).
  const realtime = (
    await db.query<any>(
      `select to_char(h at time zone 'UTC', 'YYYY-MM-DD"T"HH24":00:00Z') as hour,
              count(e.id) filter (where e.valid)::int as plays
       from generate_series(date_trunc('hour', $2::timestamptz) - interval '47 hours', date_trunc('hour', $2::timestamptz), interval '1 hour') as h
       left join listen_events e on e.artist_id = $1 and e.started_at >= h and e.started_at < h + interval '1 hour'
       group by h order by h`,
      [artistId, N],
    )
  ).rows;

  const audience = (
    await db.query<any>(
      `select
         count(*) filter (where first_seen >= $2::timestamptz)::int as new_listeners,
         count(*) filter (where first_seen < $2::timestamptz)::int as returning_listeners,
         count(*) filter (where plays >= ${SUPER_LISTENER_PLAYS})::int as super_listeners
       from (
         select user_id, min(started_at) as first_seen,
                count(*) filter (where valid and started_at >= $2::timestamptz and started_at < $3::timestamptz) as plays
         from listen_events where artist_id = $1 and user_id is not null
         group by user_id
         having count(*) filter (where valid and started_at >= $2::timestamptz and started_at < $3::timestamptz) > 0
       ) x`,
      [artistId, S, E],
    )
  ).rows[0];

  const sourceRows = (
    await db.query<any>(
      `select source, count(*)::int as plays from listen_events
       where artist_id = $1 and valid and started_at >= $2::timestamptz and started_at < $3::timestamptz
       group by source order by plays desc`,
      [artistId, S, E],
    )
  ).rows;

  const countryRows = (
    await db.query<any>(
      `select coalesce(country, 'ZZ') as country, count(*)::int as plays, count(distinct user_id)::int as listeners
       from listen_events
       where artist_id = $1 and valid and started_at >= $2::timestamptz and started_at < $3::timestamptz
       group by 1 order by plays desc`,
      [artistId, S, E],
    )
  ).rows;

  const songRows = (
    await db.query<any>(
      `select t.id, t.title,
         count(e.id) filter (where e.valid)::int as plays,
         count(distinct e.user_id) filter (where e.valid)::int as listeners,
         count(e.id)::int as starts,
         count(e.id) filter (where not e.valid)::int as skips,
         count(e.id) filter (where e.valid and e.listened_ms >= 0.9 * t.duration_ms)::int as completes,
         (select count(*) from saves s where s.track_id = t.id and s.created_at >= $2::timestamptz and s.created_at < $3::timestamptz)::int as saves
       from tracks t
       left join listen_events e on e.track_id = t.id and e.started_at >= $2::timestamptz and e.started_at < $3::timestamptz
       where t.artist_id = $1
       group by t.id, t.title order by plays desc, t.title`,
      [artistId, S, E],
    )
  ).rows;

  const mixedWith = (
    await db.query<any>(
      `select t.title as track, p.title as partner, count(*)::int as times
       from listen_events e
       join tracks t on t.id = e.track_id
       join tracks p on p.id = e.mixed_with_track_id
       where e.artist_id = $1 and e.started_at >= $2::timestamptz and e.started_at < $3::timestamptz
       group by t.title, p.title order by times desc, t.title limit 5`,
      [artistId, S, E],
    )
  ).rows;

  const totalPlays = summary.plays as number;

  // Privacy: a country with fewer than `minCohort` distinct listeners is folded into "OTHER".
  const countries: { country: string; plays: number; listeners: number; share: number }[] = [];
  let other = { plays: 0, listeners: 0 };
  for (const r of countryRows) {
    if (r.listeners < minCohort) {
      other = { plays: other.plays + r.plays, listeners: other.listeners + r.listeners };
    } else {
      countries.push({ country: r.country, plays: r.plays, listeners: r.listeners, share: ratio(r.plays, totalPlays) });
    }
  }
  if (other.plays > 0) countries.push({ country: 'OTHER', ...other, share: ratio(other.plays, totalPlays) });

  return {
    range,
    period: { start: S, end: E },
    summary: {
      plays: delta(summary.plays, summary.prev_plays),
      listeners: delta(summary.listeners, summary.prev_listeners),
      newFollowers: delta(follows.gained, follows.prev_gained),
      saves: delta(saves.saves, saves.prev_saves),
      followers: follows.total as number,
    },
    daily,
    realtime,
    audience: {
      newListeners: audience.new_listeners as number,
      returningListeners: audience.returning_listeners as number,
      superListeners: audience.super_listeners as number,
    },
    sources: sourceRows.map((r: any) => ({ source: r.source, plays: r.plays, share: ratio(r.plays, totalPlays) })),
    countries,
    songs: songRows.map((r: any) => ({
      trackId: r.id,
      title: r.title,
      plays: r.plays,
      listeners: r.listeners,
      completionRate: ratio(r.completes, r.plays),
      skipRate: ratio(r.skips, r.starts),
      saves: r.saves,
    })),
    mixedWith,
  };
}

/** How far into the song listeners get: share of plays still going at every 10% of the track. */
export async function trackRetention(db: Db, trackId: string, range: ArtistRange, now: Date) {
  const days = ARTIST_RANGES[range];
  const end = new Date(startOfUtcDay(now).getTime() + DAY);
  const start = new Date(end.getTime() - days * DAY);
  const rows = (
    await db.query<any>(
      `select g.i as step, count(*)::int as starts,
              count(*) filter (where e.listened_ms >= t.duration_ms * g.i / 10.0)::int as reached
       from listen_events e
       join tracks t on t.id = e.track_id
       cross join generate_series(0, 10) as g(i)
       where e.track_id = $1 and e.started_at >= $2::timestamptz and e.started_at < $3::timestamptz
       group by g.i order by g.i`,
      [trackId, start.toISOString(), end.toISOString()],
    )
  ).rows;
  return {
    plays: rows[0]?.starts ?? 0,
    points: rows.map((r: any) => ({ percent: r.step * 10, share: ratio(r.reached, r.starts) })),
  };
}

export async function publicArtist(db: Db, artistId: string, now: Date) {
  const profile = (
    await db.query<any>('select stage_name, bio, verified from artist_profiles where user_id = $1', [artistId])
  ).rows[0];
  if (!profile) return null;
  const end = new Date(startOfUtcDay(now).getTime() + DAY);
  const start = new Date(end.getTime() - 28 * DAY);
  const [S, E] = [start.toISOString(), end.toISOString()];
  const listeners = (
    await db.query<any>(
      `select count(distinct user_id)::int as n from listen_events
       where artist_id = $1 and valid and started_at >= $2::timestamptz and started_at < $3::timestamptz`,
      [artistId, S, E],
    )
  ).rows[0].n as number;
  const followers = (await db.query<any>('select count(*)::int as n from follows where artist_id = $1', [artistId])).rows[0].n as number;
  const topTracks = (
    await db.query<any>(
      `select t.id, t.title, count(e.id) filter (where e.valid)::int as plays
       from tracks t left join listen_events e on e.track_id = t.id and e.started_at >= $2::timestamptz and e.started_at < $3::timestamptz
       where t.artist_id = $1 group by t.id, t.title order by plays desc, t.title limit 5`,
      [artistId, S, E],
    )
  ).rows;
  return {
    id: artistId,
    stageName: profile.stage_name as string,
    bio: profile.bio as string,
    verified: profile.verified as boolean,
    monthlyListeners: listeners,
    followers,
    topTracks: topTracks.map((r: any) => ({ trackId: r.id, title: r.title, plays: r.plays })),
  };
}

export const LISTENER_RANGES = ['4w', '6m', 'year', 'all'] as const;
export type ListenerRange = (typeof LISTENER_RANGES)[number];
const LISTENER_DAYS: Record<ListenerRange, number | null> = { '4w': 28, '6m': 182, year: 365, all: null };

export type Persona = 'night_owl' | 'early_bird' | 'daytime' | 'all_day' | 'none';

export function personaFromClock(clock: number[]): Persona {
  const total = clock.reduce((a, b) => a + b, 0);
  if (total === 0) return 'none';
  const sum = (hours: number[]) => hours.reduce((a, h) => a + (clock[h] ?? 0), 0);
  const night = sum([22, 23, 0, 1, 2, 3, 4]) / total;
  const early = sum([4, 5, 6, 7, 8]) / total;
  const day = sum([9, 10, 11, 12, 13, 14, 15, 16, 17]) / total;
  if (night >= 0.4) return 'night_owl';
  if (early >= 0.4) return 'early_bird';
  if (day >= 0.6) return 'daytime';
  return 'all_day';
}

/** Consecutive days with listening, ending today or yesterday. `days` are local dates, newest first. */
export function streakFrom(days: string[], today: string): number {
  const dayMs = (s: string) => Date.parse(`${s}T00:00:00Z`);
  const first = days[0];
  if (!first) return 0;
  const gap = (dayMs(today) - dayMs(first)) / DAY;
  if (gap !== 0 && gap !== 1) return 0;
  let streak = 1;
  for (let i = 1; i < days.length; i++) {
    if ((dayMs(days[i - 1]!) - dayMs(days[i]!)) / DAY !== 1) break;
    streak++;
  }
  return streak;
}

export async function listenerStats(db: Db, userId: string, range: ListenerRange, now: Date, tzOffsetMinutes: number) {
  const span = LISTENER_DAYS[range];
  const end = new Date(startOfUtcDay(now).getTime() + DAY);
  const start = span === null ? new Date(0) : new Date(end.getTime() - span * DAY);
  const [S, E] = [start.toISOString(), end.toISOString()];
  const win = 'e.user_id = $1 and e.started_at >= $2::timestamptz and e.started_at < $3::timestamptz';

  const totals = (
    await db.query<any>(
      `select (coalesce(sum(e.listened_ms), 0) / 60000)::int as minutes,
              count(*) filter (where e.valid)::int as plays,
              count(*) filter (where e.mixed_with_track_id is not null)::int as blends,
              count(distinct e.artist_id) filter (where e.valid)::int as artists
       from listen_events e where ${win}`,
      [userId, S, E],
    )
  ).rows[0];

  const topArtists = (
    await db.query<any>(
      `select e.artist_id as id, ap.stage_name as name, count(*) filter (where e.valid)::int as plays, (sum(e.listened_ms) / 60000)::int as minutes
       from listen_events e join artist_profiles ap on ap.user_id = e.artist_id
       where ${win} group by e.artist_id, ap.stage_name order by minutes desc, plays desc limit 5`,
      [userId, S, E],
    )
  ).rows;

  const topTracks = (
    await db.query<any>(
      `select t.id, t.title, ap.stage_name as artist, count(*) filter (where e.valid)::int as plays, (sum(e.listened_ms) / 60000)::int as minutes
       from listen_events e join tracks t on t.id = e.track_id join artist_profiles ap on ap.user_id = e.artist_id
       where ${win} group by t.id, t.title, ap.stage_name order by plays desc, minutes desc limit 5`,
      [userId, S, E],
    )
  ).rows;

  const topGenres = (
    await db.query<any>(
      `select t.genre, (sum(e.listened_ms) / 60000)::int as minutes
       from listen_events e join tracks t on t.id = e.track_id
       where ${win} group by t.genre order by minutes desc limit 5`,
      [userId, S, E],
    )
  ).rows;

  const clockRows = (
    await db.query<any>(
      `select extract(hour from ((e.started_at at time zone 'UTC') + ($4::int * interval '1 minute')))::int as hour,
              (sum(e.listened_ms) / 60000)::int as minutes
       from listen_events e where ${win} group by 1`,
      [userId, S, E, tzOffsetMinutes],
    )
  ).rows;
  const clock = Array.from({ length: 24 }, () => 0);
  for (const r of clockRows) clock[r.hour] = r.minutes;

  const newArtists = (
    await db.query<any>(
      `select count(*)::int as n from (
         select artist_id, min(started_at) as first_seen from listen_events where user_id = $1 and valid group by artist_id
       ) x where first_seen >= $2::timestamptz and first_seen < $3::timestamptz`,
      [userId, S, E],
    )
  ).rows[0].n as number;

  const dayRows = (
    await db.query<any>(
      `select distinct to_char(((started_at at time zone 'UTC') + ($2::int * interval '1 minute'))::date, 'YYYY-MM-DD') as day
       from listen_events where user_id = $1 order by day desc limit 400`,
      [userId, tzOffsetMinutes],
    )
  ).rows;
  const localToday = new Date(now.getTime() + tzOffsetMinutes * 60_000).toISOString().slice(0, 10);

  return {
    range,
    minutes: totals.minutes as number,
    plays: totals.plays as number,
    songsBlended: totals.blends as number,
    artistsHeard: totals.artists as number,
    newArtists,
    streakDays: streakFrom(dayRows.map((r: any) => r.day as string), localToday),
    persona: personaFromClock(clock),
    clock,
    topArtists,
    topTracks: topTracks.map((r: any) => ({ trackId: r.id, title: r.title, artist: r.artist, plays: r.plays, minutes: r.minutes })),
    topGenres,
  };
}
