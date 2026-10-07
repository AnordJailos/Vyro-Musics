import { createHash, randomBytes, scrypt, timingSafeEqual } from 'node:crypto';
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
      return new SignJWT({}).setProtectedHeader({ alg: 'HS256' }).setSubject(userId).setIssuedAt().setExpirationTime(ACCESS_TTL).sign(key);
    },
    async verifyAccess(token: string): Promise<string | null> {
      try {
        const { payload } = await jwtVerify(token, key, { algorithms: ['HS256'] });
        return payload.sub ?? null;
      } catch {
        return null;
      }
    },
  };
}
