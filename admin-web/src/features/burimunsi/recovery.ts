/* eslint-disable no-control-regex -- Validate retained owner request metadata. */
import type { PendingAttempt } from '../core/pendingAttempt';
import {validOperatorCapabilities} from '../../../../supabase/functions/_shared/domain/burimunsi/operator-access.mjs';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/, GROUP = /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/;
type Row = Record<string, unknown>;
export const GUARDED_OPERATOR_FAMILY = 'burimunsi.operator.v2';
export interface BuriPending {kind: 'operator' | 'provisioning'; collectionId: string; principalId: string; requestId: string; intent: Row;}
export interface BuriOperatorReceipt {contractVersion: 1; requestId: string; principalId: string; version: number; active: boolean; applied: true;}
function invalid(): never {throw new Error('The original BuriMunsi request could not be verified.');}
function object(value: unknown): Row {return value !== null && typeof value === 'object' && !Array.isArray(value) ? value as Row : invalid();}
function exact(value: Row, keys: string[]) {if (Object.keys(value).length !== keys.length || keys.some(key => !Object.hasOwn(value, key))) invalid();}
function id(value: unknown): string {return typeof value === 'string' && UUID.test(value) ? value : invalid();}
function group(value: unknown): string {return typeof value === 'string' && GROUP.test(value) ? value : invalid();}
function integer(value: unknown, min = 1): number {return typeof value === 'number' && Number.isSafeInteger(value) && value >= min && value < Number.MAX_SAFE_INTEGER ? value : invalid();}
export function parseBuriPending(entry: PendingAttempt): BuriPending {
  if (entry.permission !== 'admin_users.manage' || !['burimunsi.operator', GUARDED_OPERATOR_FAMILY, 'burimunsi.provisioning'].includes(entry.family)) invalid();
  const value = object(entry.intent), collectionId = group(value.collectionId), principalId = id(value.principalId), requestId = id(value.requestId);
  if (entry.request_key !== requestId || entry.resource_id !== `${collectionId}:${principalId}`) invalid();
  if (entry.family === 'burimunsi.operator' || entry.family === GUARDED_OPERATOR_FAMILY) {
    exact(value, ['requestId', 'adminId', 'phone', 'role', 'capabilities', 'active', 'expectedVersion', 'collectionId', 'principalId', 'sharedRole']);
    id(value.adminId);
    const sharedRole = value.sharedRole;
    if ((sharedRole !== 'owner' && sharedRole !== 'admin' && sharedRole !== 'staff') || typeof value.phone !== 'string' || !/^\+2507[2389]\d{7}$/.test(value.phone) || typeof value.active !== 'boolean') invalid();
    if (!validOperatorCapabilities(value.role, value.capabilities)) invalid();
    const version = integer(value.expectedVersion, 0);
    if (version === 0 && value.active !== true || value.role === 'admin' && sharedRole === 'staff') invalid();
    return {kind: 'operator', collectionId, principalId, requestId, intent: value};
  }
  exact(value, ['collectionId', 'principalId', 'scopeVersion', 'approvalVersion', 'expectedAccountVersion', 'operation', 'reason', 'requestId', 'accountId', 'grantId', 'installationId', 'profile', 'expectedGrantVersion']);
  integer(value.scopeVersion); integer(value.approvalVersion); const accountVersion = integer(value.expectedAccountVersion, 0);
  if (value.operation !== 'set_pin' && value.operation !== 'grant_installation' && value.operation !== 'revoke_installation') invalid();
  if (typeof value.reason !== 'string' || value.reason !== value.reason.trim() || value.reason.length < 8 || value.reason.length > 300 || /[\x00-\x1f\x7f]|[a-f0-9]{64}/i.test(value.reason)) invalid();
  if (value.accountId !== null) id(value.accountId);
  if (value.operation === 'set_pin') {
    if ((value.accountId === null) !== (accountVersion === 0) || value.grantId !== null || value.installationId !== null || value.profile !== null || value.expectedGrantVersion !== null) invalid();
  } else {
    id(value.accountId); id(value.installationId); if (value.grantId !== null) id(value.grantId);
    const grantVersion = integer(value.expectedGrantVersion, 0);
    if (accountVersion < 1 || (value.profile !== 'staff' && value.profile !== 'internal_receiver') || (value.grantId === null) !== (grantVersion === 0) || value.operation === 'revoke_installation' && grantVersion === 0) invalid();
  }
  return {kind: 'provisioning', collectionId, principalId, requestId, intent: value};
}

export function parseBuriOperatorReceipt(input: unknown, requestId: string): BuriOperatorReceipt {
  const r = object(input); exact(r, ['contractVersion', 'requestId', 'principalId', 'version', 'active', 'applied']);
  if (r.contractVersion !== 1 || r.requestId !== id(requestId) || typeof r.active !== 'boolean' || r.applied !== true ||
      typeof r.version !== 'number' || !Number.isSafeInteger(r.version) || r.version < 1) return invalid();
  return {contractVersion: 1, requestId, principalId: id(r.principalId), version: r.version, active: r.active, applied: true};
}

export function parseBuriOperatorOutcome(input: unknown, collectionId: string, requestId: string): BuriOperatorReceipt | null {
  const body = object(input);
  if (body.contractVersion !== 1 || body.collectionId !== collectionId || typeof body.found !== 'boolean') return invalid();
  exact(body, ['contractVersion', 'collectionId', 'found', ...(body.found ? ['receipt'] : [])]);
  return body.found ? parseBuriOperatorReceipt(body.receipt, requestId) : null;
}

/** This only verifies a read-only original outcome. Recovery decides when it can release custody. */
export function parseBuriOutcome(input: unknown, pending: BuriPending): 'not_found' | 'recorded' | 'cancelled' {
  const original = pending.intent;
  if (pending.kind === 'operator') {
    const receipt = parseBuriOperatorOutcome(input, pending.collectionId, pending.requestId);
    if (!receipt) return 'not_found';
    if (receipt.principalId !== pending.principalId || receipt.version !== Number(original.expectedVersion) + 1 || receipt.active !== original.active) invalid();
    return 'recorded';
  }
  const body = object(input); if (body.contractVersion !== 1 || body.collectionId !== pending.collectionId || typeof body.found !== 'boolean') invalid();
  exact(body, ['contractVersion', 'collectionId', 'requestId', 'found', ...(body.found ? ['receipt'] : [])]);
  if (body.requestId !== pending.requestId) invalid(); if (!body.found) return 'not_found';
  const r = object(body.receipt);
  if (r.contractVersion !== 1 || r.collectionId !== pending.collectionId || r.requestId !== pending.requestId) invalid();
  if (r.operation === 'cancelled') {exact(r, ['contractVersion', 'collectionId', 'requestId', 'operation', 'applied']); if (r.applied !== false) invalid(); return 'cancelled';}
  const pin = original.operation === 'set_pin';
  exact(r, ['contractVersion', 'collectionId', 'requestId', 'operation', 'principalId', 'accountId', 'accountVersion', 'credentialVersion', 'approvalVersion', 'scopeVersion', 'applied', ...(pin ? [] : ['grantId', 'installationId', 'profile', 'grantVersion', 'active', 'deliveryExpiresAt'])]);
  id(r.accountId); integer(r.credentialVersion);
  if (r.operation !== original.operation || r.principalId !== pending.principalId || r.applied !== true || r.approvalVersion !== original.approvalVersion || r.scopeVersion !== original.scopeVersion ||
      r.accountVersion !== Number(original.expectedAccountVersion) + (pin ? 1 : 0) || original.accountId !== null && r.accountId !== original.accountId) invalid();
  if (!pin) {
    id(r.grantId); if (original.grantId !== null && r.grantId !== original.grantId || r.installationId !== original.installationId || r.profile !== original.profile || r.grantVersion !== Number(original.expectedGrantVersion) + 1 ||
      r.active !== (original.operation === 'grant_installation') || (original.operation === 'grant_installation' ? typeof r.deliveryExpiresAt !== 'number' || !Number.isSafeInteger(r.deliveryExpiresAt) || r.deliveryExpiresAt <= 0 : r.deliveryExpiresAt !== null)) invalid();
  }
  return 'recorded';
}
