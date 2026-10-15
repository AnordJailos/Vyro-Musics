import { randomUUID } from 'node:crypto';
import type { FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { LIVE } from './catalog_routes.js';
import type { Ctx } from './context.js';
import { audit } from './notify.js';
import { PUBLIC_COLUMNS, publicView } from './track_views.js';

const DAY = 86_400_000;
const POPULAR_DAYS = 28;
const MIN_REGIONAL_TRACKS = 5; // below this, a country has too little listening to say what is popular there
const MAX_PER_ARTIST = 3;

const homeQuery = z.object({ country: z.string().trim().length(2).optional() });
const dislikeBody = z.object({ kind: z.enum(['track', 'artist']), id: z.uuid() });
const idParam = z.object({ id: z.uuid() });
const editorialBody = z.object({
  title: z.string().trim().min(1).max(80),
  description: z.string().trim().max(200).default(''),
  trackIds: z.array(z.uuid()).max(100).default([]),
  published: z.boolean().default(false),
  position: z.number().int().min(0).max(1000).default(0),
});

// $1 explicit songs allowed, $2 songs the person is not interested in, $3 artists they are not interested in.
const OK = `${LIVE} and ($1::boolean or not t.explicit)
  and t.id not in (select jsonb_array_elements_text($2::jsonb)::uuid)
  and t.artist_id not in (select jsonb_array_elements_text($3::jsonb)::uuid)`;

function countryName(code: string): string {
  try {
    return new Intl.DisplayNames(['en'], { type: 'region' }).of(code.toUpperCase()) ?? code.toUpperCase();
  } catch {
    return code.toUpperCase();
  }
}

/** What to show a person who has little or no listening history yet (REC-01): their taste picks, what is popular where they are, and lists chosen by staff. */
export function registerRecommendationRoutes(ctx: Ctx) {
  const { app, db, now, invalid, requireUser } = ctx;
  const optional = { preHandler: ctx.optionalUser };

  const needsStaff = async (req: FastifyRequest, reply: FastifyReply) => {
    const row = (await db.query<{ role: string }>('select role from users where id = $1', [req.userId])).rows[0];
    if (!row || (row.role !== 'moderator' && row.role !== 'admin')) return reply.code(403).send({ error: 'staff_only' });
  };
  const staff = { preHandler: [requireUser, needsStaff] };

  app.get('/v1/recommendations/home', optional, async (req, reply) => {
    const q = homeQuery.safeParse(req.query);
    if (!q.success) return invalid(reply, q.error);
    const me = req.userId
      ? (await db.query<{ country: string | null; personalization: boolean; explicit_allowed: boolean }>('select country, personalization, explicit_allowed from users where id = $1', [req.userId])).rows[0]
      : undefined;
    const explicit = me?.explicit_allowed ?? false;
    const country = (me?.country ?? q.data.country ?? null)?.toUpperCase() ?? null;

    const out = { tracks: [] as string[], artists: [] as string[] };
    if (req.userId) {
      for (const d of (await db.query<{ kind: 'track' | 'artist'; target_id: string }>('select kind, target_id from rec_dislikes where user_id = $1', [req.userId])).rows) {
        (d.kind === 'track' ? out.tracks : out.artists).push(d.target_id);
      }
    }
    const base = [explicit, JSON.stringify(out.tracks), JSON.stringify(out.artists)];
    const since = new Date(now().getTime() - POPULAR_DAYS * DAY).toISOString();
    const sections: { id: string; kind: string; title: string; reason: string; tracks: ReturnType<typeof publicView>[] }[] = [];

    // 1. From the taste picker. Switched off when the person paused personalization.
    if (req.userId && me?.personalization) {
      const taste = (await db.query<{ genres: string[]; artist_ids: string[] }>('select genres, artist_ids from taste_profiles where user_id = $1', [req.userId])).rows[0];
      const genres = taste?.genres ?? [];
      const artists = taste?.artist_ids ?? [];
      if (genres.length > 0 || artists.length > 0) {
        const rows = (
          await db.query<any>(
            `select ${PUBLIC_COLUMNS},
               (case when t.artist_id in (select jsonb_array_elements_text($4::jsonb)::uuid) then 2 else 0 end
                + case when lower(t.genre) in (select jsonb_array_elements_text($5::jsonb)) then 1 else 0 end) as score,
               (select count(*)::int from listen_events e where e.track_id = t.id and e.valid and e.started_at >= $6::timestamptz) as plays
             from tracks t join artist_profiles ap on ap.user_id = t.artist_id
             where ${OK} and (t.artist_id in (select jsonb_array_elements_text($4::jsonb)::uuid) or lower(t.genre) in (select jsonb_array_elements_text($5::jsonb)))
             order by score desc, plays desc, t.published_at desc limit 100`,
            [...base, JSON.stringify(artists), JSON.stringify(genres), since],
          )
        ).rows;
        // No artist takes over the whole list.
        const perArtist = new Map<string, number>();
        const picked = rows.filter((r) => {
          const n = (perArtist.get(r.artist_id) ?? 0) + 1;
          perArtist.set(r.artist_id, n);
          return n <= MAX_PER_ARTIST;
        });
        if (picked.length > 0) sections.push({ id: 'for_you', kind: 'for_you', title: 'Picked for you', reason: 'Based on the genres and artists you chose', tracks: picked.slice(0, 20).map(publicView) });
      }
    }

    // 2. What is popular where the person is, or everywhere when there is too little listening in their country.
    const popular = (where: string | null) =>
      db.query<any>(
        `select ${PUBLIC_COLUMNS}, count(e.id)::int as plays
         from tracks t join artist_profiles ap on ap.user_id = t.artist_id
         join listen_events e on e.track_id = t.id and e.valid and e.started_at >= $5::timestamptz and ($4::text is null or e.country = $4)
         where ${OK} group by t.id, ap.user_id, ap.stage_name order by plays desc, t.published_at desc limit 20`,
        [...base, where, since],
      );
    let rows = country ? (await popular(country)).rows : [];
    let regional = rows.length >= MIN_REGIONAL_TRACKS;
    if (!regional) rows = (await popular(null)).rows;
    if (rows.length > 0) {
      sections.push({
        id: 'popular',
        kind: 'popular',
        title: regional ? `Popular in ${countryName(country!)}` : 'Popular on Vyro',
        reason: regional ? `What listeners in ${countryName(country!)} played most in the last ${POPULAR_DAYS} days` : `What listeners played most in the last ${POPULAR_DAYS} days`,
        tracks: rows.map(publicView),
      });
    }

    // 3. Lists chosen by staff.
    const lists = (await db.query<{ id: string; title: string; description: string }>('select id, title, description from editorial_lists where published order by position, created_at')).rows;
    for (const list of lists) {
      const items = (
        await db.query<any>(
          `select ${PUBLIC_COLUMNS} from editorial_items i join tracks t on t.id = i.track_id join artist_profiles ap on ap.user_id = t.artist_id
           where i.list_id = $4 and ${OK} order by i.position`,
          [...base, list.id],
        )
      ).rows;
      if (items.length > 0) sections.push({ id: `editorial:${list.id}`, kind: 'editorial', title: list.title, reason: list.description, tracks: items.map(publicView) });
    }
    return { sections };
  });

  // "Not interested": the song or the artist is left out of every list from now on.
  app.post('/v1/recommendations/not-interested', { preHandler: requireUser }, async (req, reply) => {
    const b = dislikeBody.safeParse(req.body);
    if (!b.success) return invalid(reply, b.error);
    const exists = b.data.kind === 'track' ? 'select 1 from tracks where id = $1' : 'select 1 from artist_profiles where user_id = $1';
    if ((await db.query(exists, [b.data.id])).rows.length === 0) return reply.code(404).send({ error: 'not_found' });
    await db.query('insert into rec_dislikes (user_id, kind, target_id, created_at) values ($1, $2, $3, $4::timestamptz) on conflict do nothing', [req.userId, b.data.kind, b.data.id, now().toISOString()]);
    return reply.code(204).send();
  });

  // Start over: forget the "not interested" choices and the taste picks.
  app.delete('/v1/recommendations', { preHandler: requireUser }, async (req, reply) => {
    await db.query('delete from rec_dislikes where user_id = $1', [req.userId]);
    await db.query('delete from taste_profiles where user_id = $1', [req.userId]);
    return reply.code(204).send();
  });

  // ---- lists chosen by staff ------------------------------------------------

  app.get('/v1/admin/editorial', staff, async () => {
    const rows = (
      await db.query<any>(
        `select l.id, l.title, l.description, l.position, l.published, l.updated_at, (select count(*)::int from editorial_items i where i.list_id = l.id) as track_count
         from editorial_lists l order by l.position, l.created_at`,
      )
    ).rows;
    return { lists: rows.map((r) => ({ id: r.id, title: r.title, description: r.description, position: r.position, published: r.published, trackCount: r.track_count, updatedAt: r.updated_at })) };
  });

  async function saveList(id: string, body: z.infer<typeof editorialBody>, create: boolean, actor: string) {
    const unique = [...new Set(body.trackIds)];
    if (unique.length > 0) {
      const found = (await db.query<{ id: string }>('select id from tracks where id in (select jsonb_array_elements_text($1::jsonb)::uuid)', [JSON.stringify(unique)])).rows.length;
      if (found !== unique.length) return 'unknown_track' as const;
    }
    const at = now().toISOString();
    if (create) {
      await db.query('insert into editorial_lists (id, title, description, position, published, created_at, updated_at) values ($1, $2, $3, $4, $5, $6::timestamptz, $6::timestamptz)', [id, body.title, body.description, body.position, body.published, at]);
    } else {
      await db.query('update editorial_lists set title = $2, description = $3, position = $4, published = $5, updated_at = $6::timestamptz where id = $1', [id, body.title, body.description, body.position, body.published, at]);
      await db.query('delete from editorial_items where list_id = $1', [id]);
    }
    for (const [i, trackId] of unique.entries()) await db.query('insert into editorial_items (list_id, track_id, position) values ($1, $2, $3)', [id, trackId, i]);
    await audit(db, now(), actor, create ? 'editorial.create' : 'editorial.update', 'editorial', id, { title: body.title, published: body.published, tracks: unique.length });
    return 'ok' as const;
  }

  app.post('/v1/admin/editorial', staff, async (req, reply) => {
    const b = editorialBody.safeParse(req.body);
    if (!b.success) return invalid(reply, b.error);
    const id = randomUUID();
    if ((await saveList(id, b.data, true, req.userId!)) === 'unknown_track') return reply.code(400).send({ error: 'unknown_track' });
    return reply.code(201).send({ id });
  });

  app.put('/v1/admin/editorial/:id', staff, async (req, reply) => {
    const p = idParam.safeParse(req.params);
    const b = editorialBody.safeParse(req.body);
    if (!p.success) return invalid(reply, p.error);
    if (!b.success) return invalid(reply, b.error);
    if ((await db.query('select 1 from editorial_lists where id = $1', [p.data.id])).rows.length === 0) return reply.code(404).send({ error: 'not_found' });
    if ((await saveList(p.data.id, b.data, false, req.userId!)) === 'unknown_track') return reply.code(400).send({ error: 'unknown_track' });
    return { id: p.data.id };
  });

  app.delete('/v1/admin/editorial/:id', staff, async (req, reply) => {
    const p = idParam.safeParse(req.params);
    if (!p.success) return invalid(reply, p.error);
    const res = await db.query('delete from editorial_lists where id = $1 returning id', [p.data.id]);
    if (res.rows.length === 0) return reply.code(404).send({ error: 'not_found' });
    await audit(db, now(), req.userId!, 'editorial.delete', 'editorial', p.data.id, {});
    return reply.code(204).send();
  });
}
