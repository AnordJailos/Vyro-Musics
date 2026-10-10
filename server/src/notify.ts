import type { Db } from './db.js';
import type { Messenger } from './messaging.js';

/** Sends a short message to a person by email, or by text when they have no email. Never throws. */
export async function notifyUser(db: Db, messenger: Messenger, userId: string, subject: string, body: string): Promise<void> {
  try {
    const u = (await db.query<{ email: string | null; phone: string | null }>('select email, phone from users where id = $1', [userId])).rows[0];
    if (u?.email) await messenger.email(u.email, subject, body);
    else if (u?.phone) await messenger.sms(u.phone, `${subject}: ${body}`.slice(0, 300));
  } catch {
    // A failed message must not undo the decision that triggered it.
  }
}

export async function audit(db: Db, now: Date, actorId: string | null, action: string, targetType: string, targetId: string | null, details: object = {}) {
  await db.query('insert into audit_log (actor_id, action, target_type, target_id, details, created_at) values ($1, $2, $3, $4, $5::jsonb, $6::timestamptz)', [
    actorId,
    action,
    targetType,
    targetId,
    JSON.stringify(details),
    now.toISOString(),
  ]);
}
