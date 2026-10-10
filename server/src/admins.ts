import type { Db } from './db.js';

/** Makes people with these (confirmed) email addresses administrators. Returns how many were changed. */
export async function promoteAdmins(db: Db, emails: string[]): Promise<number> {
  let changed = 0;
  for (const email of emails.map((e) => e.trim().toLowerCase()).filter(Boolean)) {
    const res = await db.query("update users set role = 'admin' where email = $1 and email_verified_at is not null and role <> 'admin' returning id", [email]);
    changed += res.rows.length;
  }
  return changed;
}
