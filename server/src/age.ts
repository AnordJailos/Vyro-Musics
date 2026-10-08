/**
 * Age rules. The numbers are a starting point and need legal review for every
 * launch market (requirement SAF-01): the minimum age and the age of digital
 * consent differ from country to country.
 */
export const MIN_AGE = 13;
export const PARENT_CONSENT_BELOW = 16;
export const ADULT_AGE = 18;
export const ARTIST_MIN_AGE = 18;

/** Whole years on a date, from a YYYY-MM-DD birth date. */
export function ageOn(birthDate: string, now: Date): number {
  const [y, m, d] = birthDate.split('-').map(Number) as [number, number, number];
  let age = now.getUTCFullYear() - y;
  const hadBirthday = now.getUTCMonth() + 1 > m || (now.getUTCMonth() + 1 === m && now.getUTCDate() >= d);
  if (!hadBirthday) age -= 1;
  return age;
}

export interface AgePolicy {
  allowed: boolean;
  needsParent: boolean;
  minor: boolean;
  explicitAllowed: boolean;
}

export function agePolicy(age: number): AgePolicy {
  return {
    allowed: age >= MIN_AGE,
    needsParent: age >= MIN_AGE && age < PARENT_CONSENT_BELOW,
    minor: age < ADULT_AGE,
    explicitAllowed: age >= ADULT_AGE,
  };
}
