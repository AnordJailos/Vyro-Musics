import { randomInt, timingSafeEqual } from 'node:crypto';
import type { Db } from './db.js';
import { sha256 } from './security.js';

export type CodePurpose = 'email_verify' | 'phone_login' | 'password_reset' | 'parent_consent';
export type CodeResult = 'ok' | 'invalid' | 'expired' | 'locked';

export const CODE_MINUTES = 10;
export const MAX_ATTEMPTS = 5;
export const MAX_CODES_PER_HOUR = 5;

const hashOf = (secret: string, purpose: string, target: string, code: string) => sha256(`${secret}|${purpose}|${target}|${code}`);

/** Makes a new six-digit code for an address or number. Older codes for it stop working. */
export async function issueCode(db: Db, secret: string, now: Date, purpose: CodePurpose, target: string, userId: string | null = null) {
  const hourAgo = new Date(now.getTime() - 3_600_000).toISOString();
  const recent = (
    await db.query<{ n: number }>(
      'select count(*)::int as n from verification_codes where purpose = $1 and target = $2 and created_at >= $3::timestamptz',
      [purpose, target, hourAgo],
    )
  ).rows[0]!.n;
  if (recent >= MAX_CODES_PER_HOUR) return { rateLimited: true as const };

  await db.query('update verification_codes set consumed_at = $3::timestamptz where purpose = $1 and target = $2 and consumed_at is null', [purpose, target, now.toISOString()]);
  const code = String(randomInt(0, 1_000_000)).padStart(6, '0');
  await db.query(
    'insert into verification_codes (purpose, target, code_hash, user_id, expires_at, created_at) values ($1, $2, $3, $4, $5::timestamptz, $6::timestamptz)',
    [purpose, target, hashOf(secret, purpose, target, code), userId, new Date(now.getTime() + CODE_MINUTES * 60_000).toISOString(), now.toISOString()],
  );
  return { rateLimited: false as const, code };
}

/** Checks a code. A right code is used up; a wrong one counts as an attempt (5 and it is locked). */
export async function checkCode(db: Db, secret: string, now: Date, purpose: CodePurpose, target: string, code: string): Promise<CodeResult> {
  const row = (
    await db.query<any>(
      `select id, code_hash, attempts, expires_at from verification_codes
       where purpose = $1 and target = $2 and consumed_at is null order by created_at desc limit 1`,
      [purpose, target],
    )
  ).rows[0];
  if (!row) return 'invalid';
  if (new Date(row.expires_at).getTime() <= now.getTime()) return 'expired';
  if (row.attempts >= MAX_ATTEMPTS) return 'locked';

  const expected = Buffer.from(row.code_hash as string, 'hex');
  const actual = Buffer.from(hashOf(secret, purpose, target, code), 'hex');
  const matches = expected.length === actual.length && timingSafeEqual(expected, actual);
  if (!matches) {
    await db.query('update verification_codes set attempts = attempts + 1 where id = $1', [row.id]);
    return 'invalid';
  }
  await db.query('update verification_codes set consumed_at = $2::timestamptz where id = $1', [row.id, now.toISOString()]);
  return 'ok';
}
