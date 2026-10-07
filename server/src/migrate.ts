import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import type { Db } from './db.js';

export async function migrate(db: Db, dir = join(process.cwd(), 'migrations')): Promise<void> {
  await db.exec(
    'create table if not exists schema_migrations (name text primary key, applied_at timestamptz not null default now())',
  );
  const done = new Set(
    (await db.query<{ name: string }>('select name from schema_migrations')).rows.map((r) => r.name),
  );
  const files = (await readdir(dir)).filter((f) => f.endsWith('.sql')).sort();
  for (const f of files) {
    if (done.has(f)) continue;
    await db.exec(await readFile(join(dir, f), 'utf8'));
    await db.query('insert into schema_migrations (name) values ($1)', [f]);
  }
}
