import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from 'jose';

export type SocialProvider = 'google' | 'apple';

export interface SocialIdentity {
  provider: SocialProvider;
  subject: string;
  email: string | null;
  emailVerified: boolean;
}

export interface SocialVerifier {
  /** Which providers have client IDs configured. */
  configured(provider: SocialProvider): boolean;
  /** The identity inside a provider's ID token, or null when the token is not valid. */
  verify(provider: SocialProvider, idToken: string): Promise<SocialIdentity | null>;
}

export interface SocialConfig {
  googleClientIds: string[];
  appleClientIds: string[];
  /** Replaces the providers' public keys (used in tests). */
  keys?: Partial<Record<SocialProvider, JWTVerifyGetKey>>;
}

export function makeSocialVerifier(config: SocialConfig): SocialVerifier {
  const keys: Record<SocialProvider, JWTVerifyGetKey> = {
    google: config.keys?.google ?? createRemoteJWKSet(new URL('https://www.googleapis.com/oauth2/v3/certs')),
    apple: config.keys?.apple ?? createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys')),
  };
  const audiences: Record<SocialProvider, string[]> = { google: config.googleClientIds, apple: config.appleClientIds };
  const issuers: Record<SocialProvider, string[]> = {
    google: ['https://accounts.google.com', 'accounts.google.com'],
    apple: ['https://appleid.apple.com'],
  };

  return {
    configured: (provider) => audiences[provider].length > 0,
    async verify(provider, idToken) {
      if (audiences[provider].length === 0) return null;
      try {
        const { payload } = await jwtVerify(idToken, keys[provider], { issuer: issuers[provider], audience: audiences[provider] });
        if (!payload.sub) return null;
        const verified = payload.email_verified;
        return {
          provider,
          subject: payload.sub,
          email: typeof payload.email === 'string' ? payload.email.toLowerCase() : null,
          emailVerified: verified === true || verified === 'true',
        };
      } catch {
        return null;
      }
    },
  };
}
