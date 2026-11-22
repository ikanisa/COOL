import { pbkdf2Async } from '@noble/hashes/pbkdf2.js';
import { sha256 } from '@noble/hashes/sha2.js';

export const OWNER_EMAIL = 'info@ikanisa.com';
export const PASSWORD_ITERATIONS = 600_000;
const encoder = new TextEncoder();
export const hex = bytes => Array.from(bytes, x => x.toString(16).padStart(2, '0')).join('');
export const unhex = text => Uint8Array.from(text.match(/../g) || [], x => parseInt(x, 16));
export const randomToken = () => hex(crypto.getRandomValues(new Uint8Array(32)));
export const digest = async text => hex(new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(text))));

export function normalizeEmail(value) {
  if (typeof value !== 'string') return null;
  const email = value.trim().toLowerCase();
  if (email.length > 254 || !/^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$/.test(email)) return null;
  return email;
}

export function validPassword(value) {
  return typeof value === 'string' && [...value].length >= 12 && [...value].length <= 128 && encoder.encode(value).length <= 512;
}

export async function passwordHash(password, salt = randomToken()) {
  // Workers' native PBKDF2 cap is lower than the OWASP work factor. Use the
  // pinned portable implementation, with no runtime downgrade in work factor.
  const result = await pbkdf2Async(sha256, encoder.encode(password), unhex(salt), {
    c: PASSWORD_ITERATIONS, dkLen: 32, asyncTick: 10,
  });
  return `pbkdf2-sha256$${PASSWORD_ITERATIONS}$${salt}$${hex(result)}`;
}

export async function passwordMatches(password, stored) {
  const parts = typeof stored === 'string' ? stored.split('$') : [];
  const valid = parts.length === 4 && parts[0] === 'pbkdf2-sha256' && parts[1] === String(PASSWORD_ITERATIONS) && /^[a-f0-9]{64}$/.test(parts[2]) && /^[a-f0-9]{64}$/.test(parts[3]);
  // Missing, revoked and malformed accounts consume the same password work.
  const salt = valid ? parts[2] : '0'.repeat(64);
  const actual = (await passwordHash(password, salt)).split('$')[3];
  const expected = valid ? parts[3] : '0'.repeat(64);
  let different = 0;
  for (let i = 0; i < 64; i++) different |= actual.charCodeAt(i) ^ expected.charCodeAt(i);
  return valid && different === 0;
}
