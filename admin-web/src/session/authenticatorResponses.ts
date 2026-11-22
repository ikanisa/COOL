/* eslint-disable no-control-regex -- Reject controls in server-supplied authenticator labels. */
import {AdminRequestError, isJsonObject, isVerificationUuid, type JsonObject} from '../api/contracts';
import type {AdminUser} from './sessionResponses';

export interface AuthenticatorFactor {id: string; name: string; verified: boolean}
export interface AuthenticatorSetup {factor: AuthenticatorFactor; secret: string}

export function parseFactor(value: unknown): AuthenticatorFactor {
  if (!isJsonObject(value) || !isVerificationUuid(value.id) || value.factor_type !== 'totp' || (value.status !== 'verified' && value.status !== 'unverified')) throw new Error('The authenticator response could not be verified.');
  const name = value.friendly_name ?? 'Authenticator';
  if (typeof name !== 'string' || !name.trim() || name.length > 64 || /[\x00-\x1f\x7f]/.test(name)) throw new Error('The authenticator response could not be verified.');
  return {id: value.id, name, verified: value.status === 'verified'};
}

export function parseSetup(value: JsonObject, user: AdminUser): AuthenticatorSetup {
  const factor = parseFactor(value), totp = value.totp;
  if (factor.verified || !isJsonObject(totp) || typeof totp.secret !== 'string' || !/^[A-Z2-7]{32}$/.test(totp.secret) || typeof totp.uri !== 'string') throw new Error('The authenticator setup could not be verified.');
  let uri: URL;
  try {uri = new URL(totp.uri);} catch {throw new Error('The authenticator setup could not be verified.');}
  let label: string;
  try {label = decodeURIComponent(uri.pathname.slice(1));} catch {throw new Error('The authenticator setup could not be verified.');}
  const expected: Record<string, string> = {secret: totp.secret, issuer: 'Collect', algorithm: 'SHA1', digits: '6', period: '30'};
  if (uri.protocol !== 'otpauth:' || uri.hostname !== 'totp' || uri.port || uri.username || uri.password || uri.hash || uri.pathname.slice(1).includes('/') || label !== `Collect:${user.email}` || [...uri.searchParams.keys()].length !== Object.keys(expected).length || Object.entries(expected).some(([key, val]) => uri.searchParams.getAll(key).length !== 1 || uri.searchParams.get(key) !== val)) throw new Error('The authenticator setup could not be verified.');
  return {factor, secret: totp.secret};
}

export function parseFactors(body: JsonObject, principalId: string): AuthenticatorFactor[] {
  if (body.id !== principalId || !Array.isArray(body.factors) || body.factors.length > 128) throw new Error('The authenticator response could not be verified.');
  const factors = body.factors.map(parseFactor);
  if (new Set(factors.map((item) => item.id.toLowerCase())).size !== factors.length) throw new Error('The authenticator response could not be verified.');
  return factors;
}

export function parseAuthenticatorChallenge(body: JsonObject, factorId: string, managed: boolean, now = Math.floor(Date.now() / 1000)): string {
  if (!isVerificationUuid(body.challenge_id) || body.id !== body.challenge_id ||
      (managed && body.factor_id !== factorId) || typeof body.expires_at !== 'number' ||
      !Number.isInteger(body.expires_at) || body.expires_at <= now || body.expires_at > now + 600) {
    throw new AdminRequestError('The authenticator challenge could not be verified.', {outcomeUnknown: true});
  }
  return body.challenge_id;
}
