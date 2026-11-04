import {ApiError} from './core.js';

// This ring is only for pseudonymous phone/email lookup. OTP-code authentication,
// JWTs and source/global spend budgets retain their separately scoped keys.
export const LEGACY_IDENTITY_KEY_ID = 'legacy-token-hash-v1';
const ID = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/;
const encoder = new TextEncoder();
const unavailable = () => new ApiError(503, 'auth_identity_configuration_invalid',
  'Sign-in is unavailable. Please try again later or contact support.');
const base64 = bytes => btoa(String.fromCharCode(...bytes));
function bytes(value) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9+/]{43}=$/.test(value)) throw unavailable();
  const decoded = Uint8Array.from(atob(value), character => character.charCodeAt(0));
  if (decoded.length !== 32 || base64(decoded) !== value) throw unavailable();
  return decoded;
}

export function identityKeyRing(env, legacySecret) {
  if (typeof legacySecret !== 'string' || encoder.encode(legacySecret).length < 32) throw unavailable();
  const legacy = encoder.encode(legacySecret);
  const configuredId = env.AUTH_IDENTITY_KEY_ID, configuredKey = env.AUTH_IDENTITY_HASH_KEY;
  const absent = value => value === undefined || value === '';
  const currentId = absent(configuredId) && absent(configuredKey)
    ? LEGACY_IDENTITY_KEY_ID : configuredId;
  if (typeof currentId !== 'string' || !ID.test(currentId) ||
      currentId === LEGACY_IDENTITY_KEY_ID && !absent(configuredKey)) throw unavailable();
  const currentKey = currentId === LEGACY_IDENTITY_KEY_ID ? legacy : bytes(configuredKey);
  const keys = new Map([[currentId, currentKey]]);
  const prohibited = new Set([base64(legacy)]);
  if (typeof env.AUTH_JWT_SECRET === 'string') prohibited.add(base64(encoder.encode(env.AUTH_JWT_SECRET)));
  if (typeof env.DATA_ENCRYPTION_KEY === 'string') prohibited.add(env.DATA_ENCRYPTION_KEY);
  const material = new Set([...prohibited, base64(currentKey)]);
  if (currentId !== LEGACY_IDENTITY_KEY_ID) {
    if (prohibited.has(base64(currentKey))) throw unavailable();
    keys.set(LEGACY_IDENTITY_KEY_ID, legacy);
  }
  const raw = env.AUTH_IDENTITY_PREVIOUS_KEYS_JSON;
  if (raw === undefined || raw === '') return {currentId, keys};
  if (typeof raw !== 'string' || encoder.encode(raw).length > 4096) throw unavailable();
  // Literal IDs and an explicit bounded parser preserve duplicate-role evidence;
  // JSON.parse would silently overwrite repeated or escaped authority keys.
  let cursor = 0, count = 0;
  const seen = new Set();
  const whitespace = () => { while (cursor < raw.length && /[ \t\r\n]/.test(raw[cursor])) cursor++; };
  const take = character => { whitespace(); if (raw[cursor++] !== character) throw unavailable(); };
  take('{'); whitespace();
  if (raw[cursor] === '}') cursor++;
  else while (true) {
    whitespace();
    const label = /^"([A-Za-z0-9][A-Za-z0-9._:-]{0,127})"/.exec(raw.slice(cursor));
    if (!label || seen.has(label[1]) || keys.has(label[1]) || ++count > 8) throw unavailable();
    const id = label[1]; seen.add(id); cursor += label[0].length; take(':'); whitespace();
    const entry = /^"([A-Za-z0-9+/]{43}=)"/.exec(raw.slice(cursor));
    if (!entry) throw unavailable();
    cursor += entry[0].length;
    const key = bytes(entry[1]);
    if (material.has(entry[1])) throw unavailable();
    material.add(entry[1]); keys.set(id, key);
    whitespace(); if (raw[cursor] === '}') { cursor++; break; } take(',');
  }
  whitespace(); if (cursor !== raw.length) throw unavailable();
  return {currentId, keys};
}

export async function identityHashes(ring, target) {
  if (!['phone', 'email'].includes(target?.type) || typeof target.value !== 'string' ||
      encoder.encode(target.value).length > 254) throw unavailable();
  const hashes = [];
  for (const [keyId, bytes] of ring.keys) {
    const key = await crypto.subtle.importKey('raw', bytes, {name:'HMAC', hash:'SHA-256'}, false, ['sign']);
    const domain = keyId === LEGACY_IDENTITY_KEY_ID ? 'collect-identity-v1'
      : `collect-identity-v2:${keyId}`;
    const signed = await crypto.subtle.sign('HMAC', key, encoder.encode(`${domain}:${target.type}:${target.value}`));
    const hash = [...new Uint8Array(signed)].map(byte => byte.toString(16).padStart(2, '0')).join('');
    hashes.push({key_id:keyId, identity_hash:hash});
  }
  return hashes.sort((left, right) => left.key_id < right.key_id ? -1 : left.key_id > right.key_id ? 1 : 0);
}
