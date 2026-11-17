import {requireThat} from './errors.js';
export const MAX_RWF = 9007199254740991;
/** Accept formatting, not arbitrary text that happens to contain digits. */
export function normalizePhone(input) {
  requireThat(typeof input === 'string' && input.length <= 40 && /^[+0-9 ()-]+$/.test(input), 'invalid_phone');
  let p = input.trim().replace(/[ ()-]/g, '');
  if (p.startsWith('00')) p = '+' + p.slice(2);
  if (/^0\d{9}$/.test(p)) p = '+250' + p.slice(1);
  else if (/^\d{9}$/.test(p)) p = '+250' + p;
  else if (/^250\d{9}$/.test(p)) p = '+' + p;
  requireThat(/^\+2507[2389]\d{7}$/.test(p), 'invalid_phone');
  return p;
}
export function requirePin(pin) {
  requireThat(typeof pin === 'string' && /^[0-9]{4}$/.test(pin), 'invalid_passcode');
  return pin;
}
export function requireId(id) {
  requireThat(typeof id === 'string' && /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(id), 'invalid_id');
  return id;
}
export function wholeRwf(raw, {positive = true} = {}) {
  requireThat(typeof raw === 'string' && raw.length <= 24 && /^(0|[1-9]\d*|[1-9]\d{0,2}(,\d{3})+)$/.test(raw), 'invalid_amount');
  const n = BigInt(raw.replaceAll(',', ''));
  requireThat(n >= (positive ? 1n : 0n) && n <= BigInt(MAX_RWF), 'invalid_amount');
  return Number(n);
}
export function requireAmount(n) {
  requireThat(Number.isSafeInteger(n) && n > 0 && n <= MAX_RWF, 'invalid_amount');
  return n;
}
export function providerTime(raw, offsetMinutes) {
  requireThat(typeof raw === 'string' && /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(raw), 'invalid_timestamp');
  requireThat(Number.isInteger(offsetMinutes) && Math.abs(offsetMinutes) <= 840, 'provider_timezone_required');
  const iso = raw.replace(' ', 'T'), ms = Date.parse(iso + 'Z');
  requireThat(Number.isFinite(ms) && new Date(ms).toISOString().slice(0,19) === iso, 'invalid_timestamp');
  return new Date(ms - offsetMinutes * 60000).toISOString();
}
// The strict wire parser deliberately uses null-prototype JSON objects to
// prevent inherited keys and prototype pollution. They are plain JSON data.
const jsonObject=value=>value!==null&&typeof value==='object'&&!Array.isArray(value)&&
  (Object.getPrototypeOf(value)===Object.prototype||Object.getPrototypeOf(value)===null);
export function canonicalJson(v) {
  if (v === null || typeof v === 'string' || typeof v === 'boolean') return JSON.stringify(v);
  if (typeof v === 'number') { requireThat(Number.isFinite(v), 'invalid_json'); return JSON.stringify(v); }
  if (Array.isArray(v)) return '[' + v.map(canonicalJson).join(',') + ']';
  requireThat(jsonObject(v), 'invalid_json');
  return '{' + Object.keys(v).sort().map(k => JSON.stringify(k) + ':' + canonicalJson(v[k])).join(',') + '}';
}
export async function sha256(value) {
  const bytes = new TextEncoder().encode(value);
  return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), x => x.toString(16).padStart(2,'0')).join('');
}
export function exactKeys(body, allowed, required = allowed) {
  requireThat(jsonObject(body) && Object.keys(body).every(k => allowed.includes(k)) && required.every(k => Object.hasOwn(body,k)), 'invalid_request');
  return body;
}

export function requireRequestId(value) {
  requireThat(typeof value==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value),'invalid_request_id');
  return value.toLowerCase();
}
