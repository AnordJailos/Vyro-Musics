import { createHash, createHmac, randomBytes, scrypt, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';
import { SignJWT, jwtVerify } from 'jose';

const scryptAsync = promisify(scrypt) as (pw: string, salt: Buffer, len: number) => Promise<Buffer>;

export async function hashPassword(password: string): Promise<string> {
  const salt = randomBytes(16);
  const key = await scryptAsync(password, salt, 64);
  return `scrypt$${salt.toString('base64')}$${key.toString('base64')}`;
}

export async function verifyPassword(password: string, stored: string): Promise<boolean> {
  const [scheme, saltB64, keyB64] = stored.split('$');
  if (scheme !== 'scrypt' || !saltB64 || !keyB64) return false;
  const expected = Buffer.from(keyB64, 'base64');
  const actual = await scryptAsync(password, Buffer.from(saltB64, 'base64'), expected.length);
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

export const sha256 = (s: string) => createHash('sha256').update(s).digest('hex');
export const newRefreshToken = () => randomBytes(32).toString('base64url');

const ACCESS_TTL = '15m';

export function tokenKit(secret: string) {
  const key = new TextEncoder().encode(secret);
  return {
    async signAccess(userId: string): Promise<string> {
      return new SignJWT({})
        .setProtectedHeader({ alg: 'HS256' })
        .setSubject(userId)
        .setAudience('vyro-access')
        .setIssuedAt()
        .setExpirationTime(ACCESS_TTL)
        .sign(key);
    },
    async verifyAccess(token: string): Promise<string | null> {
      try {
        const { payload } = await jwtVerify(token, key, { algorithms: ['HS256'], audience: 'vyro-access' });
        return payload.sub ?? null;
      } catch {
        return null;
      }
    },
    /** A short-lived pass given to someone who proved a phone number or social account but has no profile yet. */
    async signSignup(claims: Record<string, unknown>): Promise<string> {
      return new SignJWT(claims).setProtectedHeader({ alg: 'HS256' }).setAudience('vyro-signup').setIssuedAt().setExpirationTime('30m').sign(key);
    },
    async verifySignup(token: string): Promise<Record<string, unknown> | null> {
      try {
        const { payload } = await jwtVerify(token, key, { algorithms: ['HS256'], audience: 'vyro-signup' });
        return payload as Record<string, unknown>;
      } catch {
        return null;
      }
    },
  };
}

/** Short-lived, tamper-proof address for a song's audio: `trackId.expiry.signature`. */
export function signStreamToken(secret: string, trackId: string, expiresAtSeconds: number): string {
  const body = `${trackId}.${expiresAtSeconds}`;
  return `${body}.${createHmac('sha256', secret).update(`stream|${body}`).digest('base64url')}`;
}

export function verifyStreamToken(secret: string, token: string, nowSeconds: number): { trackId: string } | null {
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  const [trackId, exp, sig] = parts as [string, string, string];
  const expected = createHmac('sha256', secret).update(`stream|${trackId}.${exp}`).digest('base64url');
  const a = Buffer.from(sig);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !timingSafeEqual(a, b)) return null;
  if (!Number.isFinite(Number(exp)) || Number(exp) <= nowSeconds) return null;
  return { trackId };
}
