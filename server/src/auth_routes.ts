import { z } from 'zod';
import { agePolicy, ageOn, type AgePolicy } from './age.js';
import { checkCode, issueCode, type CodePurpose, type CodeResult } from './codes.js';
import type { Ctx } from './context.js';
import { isUniqueViolation } from './db.js';
import type { SocialProvider } from './idtokens.js';
import { codeText } from './messaging.js';
import { hashPassword, sha256, verifyPassword } from './security.js';

const password = z.string().min(8).max(128);
const username = z.string().regex(/^[a-z0-9_]{3,24}$/);
const phone = z
  .string()
  .max(30)
  .transform((s) => s.replace(/[\s().-]/g, ''))
  .refine((s) => /^\+[1-9]\d{6,14}$/.test(s), 'Use international format: a + followed by the country code and number.');
const profileFields = {
  displayName: z.string().trim().min(1).max(60),
  username,
  country: z.string().length(2).optional(),
  language: z.string().min(2).max(10).default('en'),
  birthDate: z.iso.date(),
  parentEmail: z.email().max(254).optional(),
  acceptedTermsVersion: z.string().min(1).max(32),
  deviceName: z.string().max(80).optional(),
};

const registerBody = z.object({ email: z.email().max(254), password, ...profileFields });
const loginBody = z.object({ email: z.email(), password: z.string().min(1).max(128), deviceName: z.string().max(80).optional() });
const refreshBody = z.object({ refreshToken: z.string().min(20).max(200) });
const codeBody = z.object({ code: z.string().regex(/^\d{6}$/) });
const phoneRequestBody = z.object({ phone });
const phoneVerifyBody = z.object({ phone, code: z.string().regex(/^\d{6}$/), deviceName: z.string().max(80).optional() });
const socialBody = z.object({ provider: z.enum(['google', 'apple']), idToken: z.string().min(20).max(4000), deviceName: z.string().max(80).optional() });
const completeBody = z.object({ signupToken: z.string().min(20).max(4000), ...profileFields });
const resetRequestBody = z.object({ email: z.email() });
const resetConfirmBody = z.object({ email: z.email(), code: z.string().regex(/^\d{6}$/), newPassword: password });

export function registerAuthRoutes(ctx: Ctx) {
  const { app, db, now, messenger, tokens, limit, invalid, issueTokens, loadMe, requireUser } = ctx;

  const codeFailure = (result: Exclude<CodeResult, 'ok'>) => ({
    error: result === 'expired' ? 'code_expired' : result === 'locked' ? 'too_many_attempts' : 'invalid_code',
  });

  async function sendCode(purpose: CodePurpose, target: string, userId: string | null, send: (code: string) => Promise<void>) {
    const issued = await issueCode(db, ctx.secret, now(), purpose, target, userId);
    if (issued.rateLimited) return false;
    await send(issued.code);
    return true;
  }

  /** Age gate: refuses children under the minimum age and asks for a parent's email below the age of consent. */
  type AgeResult = { ok: true; policy: AgePolicy } | { ok: false; status: number; body: { error: string } };
  function ageCheck(b: { birthDate: string; parentEmail?: string | undefined }, ownEmail: string | null): AgeResult {
    const age = ageOn(b.birthDate, now());
    if (age < 0 || age > 120) return { ok: false, status: 400, body: { error: 'invalid_birth_date' } };
    const policy = agePolicy(age);
    if (!policy.allowed) return { ok: false, status: 403, body: { error: 'too_young' } };
    if (policy.needsParent) {
      if (!b.parentEmail) return { ok: false, status: 400, body: { error: 'parent_email_required' } };
      if (ownEmail && b.parentEmail.toLowerCase() === ownEmail) return { ok: false, status: 400, body: { error: 'parent_email_must_differ' } };
    }
    return { ok: true, policy };
  }

  async function createUser(input: {
    email: string | null;
    passwordHash: string | null;
    phone: string | null;
    emailVerified: boolean;
    phoneVerified: boolean;
    b: { displayName: string; username: string; country?: string | undefined; language: string; birthDate: string; parentEmail?: string | undefined; acceptedTermsVersion: string };
    policy: AgePolicy;
  }): Promise<string> {
    const { b, policy } = input;
    const stamp = now().toISOString();
    const row = (
      await db.query<{ id: string }>(
        `insert into users (email, password_hash, phone, display_name, username, country, language, birth_date,
                            explicit_allowed, parent_consent, parent_email, email_verified_at, phone_verified_at)
         values ($1, $2, $3, $4, $5, $6, $7, $8::date, $9, $10, $11, $12::timestamptz, $13::timestamptz) returning id`,
        [
          input.email,
          input.passwordHash,
          input.phone,
          b.displayName,
          b.username,
          b.country?.toUpperCase() ?? null,
          b.language,
          b.birthDate,
          policy.explicitAllowed,
          policy.needsParent ? 'pending' : 'not_needed',
          policy.needsParent ? b.parentEmail!.toLowerCase() : null,
          input.emailVerified ? stamp : null,
          input.phoneVerified ? stamp : null,
        ],
      )
    ).rows[0]!;
    for (const doc of ['terms', 'privacy']) {
      await db.query('insert into consents (user_id, document, version) values ($1, $2, $3)', [row.id, doc, b.acceptedTermsVersion]);
    }
    return row.id;
  }

  async function sendEmailCode(userId: string, email: string) {
    return sendCode('email_verify', email, userId, (code) => messenger.email(email, 'Your Vyro verification code', codeText('to confirm your email', code)));
  }

  async function sendParentCode(userId: string, parentEmail: string) {
    return sendCode('parent_consent', parentEmail, userId, (code) =>
      messenger.email(parentEmail, 'A young person wants to join Vyro', `Someone under 16 used this email as their parent or guardian contact for Vyro, a music app. ${codeText('for parental permission', code)} Share it with them only if you agree.`),
    );
  }

  async function startSession(userId: string, deviceName: string | null | undefined) {
    return { user: await loadMe(userId), ...(await issueTokens(userId, deviceName ?? null)) };
  }

  // ---- email and password ------------------------------------------------

  app.post('/v1/auth/register', limit, async (req, reply) => {
    const parsed = registerBody.safeParse(req.body);
    if (!parsed.success) return invalid(reply, parsed.error);
    const b = parsed.data;
    const email = b.email.toLowerCase();
    const check = ageCheck(b, email);
    if (!check.ok) return reply.code(check.status).send(check.body);
    try {
      const id = await createUser({ email, passwordHash: await hashPassword(b.password), phone: null, emailVerified: false, phoneVerified: false, b, policy: check.policy });
      await sendEmailCode(id, email);
      if (check.policy.needsParent) await sendParentCode(id, b.parentEmail!.toLowerCase());
      return reply.code(201).send(await startSession(id, b.deviceName));
    } catch (e) {
      if (isUniqueViolation(e)) return reply.code(409).send({ error: 'email_or_username_taken' });
      throw e;
    }
  });

  app.post('/v1/auth/login', limit, async (req, reply) => {
    const parsed = loginBody.safeParse(req.body);
    if (!parsed.success) return invalid(reply, parsed.error);
    const row = (await db.query<{ id: string; password_hash: string | null }>('select id, password_hash from users where email = $1', [parsed.data.email.toLowerCase()])).rows[0];
    const ok = await verifyPassword(parsed.data.password, row?.password_hash ?? ctx.dummyHash);
    if (!row || !row.password_hash || !ok) return reply.code(401).send({ error: 'invalid_credentials' });
    return startSession(row.id, parsed.data.deviceName);
  });

  app.post('/v1/auth/refresh', limit, async (req, reply) => {
    const parsed = refreshBody.safeParse(req.body);
    if (!parsed.success) return invalid(reply, parsed.error);
    const row = (
      await db.query<{ user_id: string; device_name: string | null }>(
        'update refresh_tokens set revoked_at = now() where token_hash = $1 and revoked_at is null and expires_at > now() returning user_id, device_name',
        [sha256(parsed.data.refreshToken)],
      )
    ).rows[0];
    if (!row) return reply.code(401).send({ error: 'invalid_refresh_token' });
    return issueTokens(row.user_id, row.device_name);
  });

  app.post('/v1/auth/logout', async (req, reply) => {
    const parsed = refreshBody.safeParse(req.body);
    if (!parsed.success) return invalid(reply, parsed.error);
    await db.query('update refresh_tokens set revoked_at = now() where token_hash = $1 and revoked_at is null', [sha256(parsed.data.refreshToken)]);
    return reply.code(204).send();
  });

  // ---- email check ---------------------------------------------------------

  app.post('/v1/auth/email/verify', { preHandler: requireUser }, async (req, reply) => {
    const parsed = codeBody.safeParse(req.body);
    if (!parsed.success) return invalid(reply, parsed.error);
    const user = (await db.query<{ email: string | null }>('select email from users where id = $1', [req.userId])).rows[0];
    if (!user?.email) return reply.code(400).send({ error: 'no_email' });
    const result = await checkCode(db, ctx.secret, now(), 'email_verify', user.email, parsed.data.code);
    if (result !== 'ok') return reply.code(400).send(codeFailure(result));
    await db.query('update users set email_verified_at = $2::timestamptz where id = $1 and email_verified_at is null', [req.userId, now().toISOString()]);
    return loadMe(req.userId!);
  });

  app.post('/v1/auth/email/resend', { preHandler: requireUser, ...limit }, async (req, reply) => {
    const user = (await db.query<{ email: string | null; email_verified_at: unknown }>('select email, email_verified_at from users where id = $1', [req.userId])).rows[0];
    if (!user?.email) return reply.code(400).send({ error: 'no_email' });
    if (user.email_verified_at) return reply.code(409).send({ error: 'already_verified' });
    const sent = await sendEmailCode(req.userId!, user.email);
    return sent ? reply.code(202).send() : reply.code(429).send({ error: 'too_many_codes' });
  });

  // ---- phone number --------------------------------------------------------

  app.post('/v1/auth/phone/request', limit, async (req, reply) => {
    const parsed = phoneRequestBody.safeParse(req.body);
    if (!parsed.success) return invalid(reply, parsed.error);
    const number = parsed.data.phone;
    const sent = await sendCode('phone_login', number, null, (code) => messenger.sms(number, codeText('to sign in', code)));
    return sent ? reply.code(202).send() : reply.code(429).send({ error: 'too_many_codes' });
  });

  app.post('/v1/auth/phone/verify', limit, async (req, reply) => {
    const parsed = phoneVerifyBody.safeParse(req.body);
    if (!parsed.success) return invalid(reply, parsed.error);
    const { phone: number, code, deviceName } = parsed.data;
    const result = await checkCode(db, ctx.secret, now(), 'phone_login', number, code);
    if (result !== 'ok') return reply.code(400).send(codeFailure(result));
    const user = (await db.query<{ id: string }>('select id from users where phone = $1', [number])).rows[0];
    if (user) {
      await db.query('update users set phone_verified_at = coalesce(phone_verified_at, $2::timestamptz) where id = $1', [user.id, now().toISOString()]);
      return startSession(user.id, deviceName);
    }
    return { needsProfile: true, signupToken: await tokens.signSignup({ kind: 'phone', phone: number }) };
  });

  // ---- Google and Apple ------------------------------------------------------

  app.post('/v1/auth/social', limit, async (req, reply) => {
    const parsed = socialBody.safeParse(req.body);
    if (!parsed.success) return invalid(reply, parsed.error);
    const { provider, idToken, deviceName } = parsed.data;
    if (!ctx.social.configured(provider)) return reply.code(501).send({ error: 'social_not_configured' });
    const identity = await ctx.social.verify(provider, idToken);
    if (!identity) return reply.code(401).send({ error: 'invalid_token' });

    const linked = (await db.query<{ user_id: string }>('select user_id from identities where provider = $1 and subject = $2', [provider, identity.subject])).rows[0];
    if (linked) return startSession(linked.user_id, deviceName);

    // A new identity must come with an email the provider has checked. Without that we cannot tell
    // whose account it is, and an unchecked address could be used to take over someone else's.
    if (!identity.email || !identity.emailVerified) return reply.code(403).send({ error: 'provider_email_unverified' });

    // Same email as an existing account: the provider vouches for it, so link the two.
    const existing = (await db.query<{ id: string }>('select id from users where email = $1', [identity.email])).rows[0];
    if (existing) {
      await db.query('insert into identities (provider, subject, user_id, email) values ($1, $2, $3, $4)', [provider, identity.subject, existing.id, identity.email]);
      await db.query('update users set email_verified_at = coalesce(email_verified_at, $2::timestamptz) where id = $1', [existing.id, now().toISOString()]);
      return startSession(existing.id, deviceName);
    }
    return {
      needsProfile: true,
      signupToken: await tokens.signSignup({ kind: 'social', provider, subject: identity.subject, email: identity.email }),
      suggestedEmail: identity.email,
    };
  });

  // Finishes sign-up for someone who proved a phone number or a social account.
  app.post('/v1/auth/complete-profile', limit, async (req, reply) => {
    const parsed = completeBody.safeParse(req.body);
    if (!parsed.success) return invalid(reply, parsed.error);
    const { signupToken, ...b } = parsed.data;
    const claims = await tokens.verifySignup(signupToken);
    if (!claims) return reply.code(401).send({ error: 'invalid_signup_token' });

    const isPhone = claims.kind === 'phone';
    const email = isPhone ? null : typeof claims.email === 'string' ? claims.email : null;
    const check = ageCheck(b, email);
    if (!check.ok) return reply.code(check.status).send(check.body);
    try {
      const id = await createUser({
        email,
        passwordHash: null,
        phone: isPhone ? String(claims.phone) : null,
        emailVerified: !isPhone, // social tokens are only issued for emails the provider has checked
        phoneVerified: isPhone,
        b,
        policy: check.policy,
      });
      if (!isPhone) {
        await db.query('insert into identities (provider, subject, user_id, email) values ($1, $2, $3, $4)', [claims.provider as SocialProvider, String(claims.subject), id, email]);
      }
      if (check.policy.needsParent) await sendParentCode(id, b.parentEmail!.toLowerCase());
      return reply.code(201).send(await startSession(id, b.deviceName));
    } catch (e) {
      if (isUniqueViolation(e)) return reply.code(409).send({ error: 'email_or_username_taken' });
      throw e;
    }
  });

  // ---- password reset --------------------------------------------------------

  // Always answers 202, so nobody can use this to find out who has an account.
  app.post('/v1/auth/password-reset/request', limit, async (req, reply) => {
    const parsed = resetRequestBody.safeParse(req.body);
    if (!parsed.success) return invalid(reply, parsed.error);
    const email = parsed.data.email.toLowerCase();
    const user = (await db.query<{ id: string }>('select id from users where email = $1', [email])).rows[0];
    if (user) {
      await sendCode('password_reset', email, user.id, (code) => messenger.email(email, 'Reset your Vyro password', codeText('to reset your password', code)));
    }
    return reply.code(202).send();
  });

  app.post('/v1/auth/password-reset/confirm', limit, async (req, reply) => {
    const parsed = resetConfirmBody.safeParse(req.body);
    if (!parsed.success) return invalid(reply, parsed.error);
    const { code, newPassword } = parsed.data;
    const email = parsed.data.email.toLowerCase();
    const result = await checkCode(db, ctx.secret, now(), 'password_reset', email, code);
    if (result !== 'ok') return reply.code(400).send(codeFailure(result));
    const user = (await db.query<{ id: string }>('select id from users where email = $1', [email])).rows[0];
    if (!user) return reply.code(400).send({ error: 'invalid_code' });
    await db.query('update users set password_hash = $2, email_verified_at = coalesce(email_verified_at, $3::timestamptz) where id = $1', [user.id, await hashPassword(newPassword), now().toISOString()]);
    await db.query('update refresh_tokens set revoked_at = now() where user_id = $1 and revoked_at is null', [user.id]); // sign out everywhere
    return reply.code(204).send();
  });

  // ---- parent permission (under 16) -----------------------------------------

  app.post('/v1/me/parent-consent/confirm', { preHandler: requireUser }, async (req, reply) => {
    const parsed = codeBody.safeParse(req.body);
    if (!parsed.success) return invalid(reply, parsed.error);
    const user = (await db.query<{ parent_email: string | null; parent_consent: string }>('select parent_email, parent_consent from users where id = $1', [req.userId])).rows[0];
    if (!user || user.parent_consent !== 'pending' || !user.parent_email) return reply.code(409).send({ error: 'nothing_to_confirm' });
    const result = await checkCode(db, ctx.secret, now(), 'parent_consent', user.parent_email, parsed.data.code);
    if (result !== 'ok') return reply.code(400).send(codeFailure(result));
    await db.query("update users set parent_consent = 'granted' where id = $1", [req.userId]);
    return loadMe(req.userId!);
  });

  app.post('/v1/me/parent-consent/resend', { preHandler: requireUser, ...limit }, async (req, reply) => {
    const user = (await db.query<{ parent_email: string | null; parent_consent: string }>('select parent_email, parent_consent from users where id = $1', [req.userId])).rows[0];
    if (!user || user.parent_consent !== 'pending' || !user.parent_email) return reply.code(409).send({ error: 'nothing_to_confirm' });
    const sent = await sendParentCode(req.userId!, user.parent_email);
    return sent ? reply.code(202).send() : reply.code(429).send({ error: 'too_many_codes' });
  });
}
