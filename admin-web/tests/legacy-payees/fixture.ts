import { vi } from 'vitest';
import type { PendingIdentity } from '../../src/features/core/pendingAttempt';
import type { FeatureAccess } from '../../src/features/core/types';
import type { LegacyPayeeContext } from '../../src/features/legacy-payees/actions';

export const actor = '11111111-1111-4111-8111-111111111111', payeeId = '22222222-2222-4222-8222-222222222222', groupId = '33333333-3333-4333-8333-333333333333', requestId = '44444444-4444-4444-8444-444444444444', key = '55555555-5555-4555-8555-555555555555', otherPayee = '66666666-6666-4666-8666-666666666666';
export const permissions = ['receivers.read', 'receivers.manage', 'collections.read', 'overview.read'];
export const identity: PendingIdentity = {id: actor, sessionId: 'synthetic-session', email: 'operator@example.test', role: 'admin', permissions, expiresAt: '2100-01-01T00:00:00.000Z'};
export const payeeRow = {id: payeeId, group_id: groupId, label: 'Recorded receiver', network: 'mtn_momo', momo_number_or_code: '0041258', rail: 'rwanda_momo', currency: 'RWF', status: 'active', version: 2};
export const groupRow = {id: groupId, title: 'Savings group', status: 'active', country_code: 'RW', currency: 'RWF', version: 3};
export const payeeDetail = {resource_type: 'payees', current_actor_id: actor, can_manage: true, resource: payeeRow};
export function groupDetail(rows: unknown[] = [payeeRow], group: Record<string, unknown> = groupRow, total = rows.length, offset = 0) {return {resource_type: 'groups', current_actor_id: actor, can_manage: true, resource: group, related: {payees: rows}, related_pages: {payees: {total, limit: 100, offset, next_offset: offset + rows.length < total ? offset + rows.length : null}}, related_truncated: total > rows.length};}
export const intent = {label: 'Updated receiver', status: 'active' as const, expected_version: 2, expected_group_version: 3, reason: 'Review receiver change'};
export const receipt = {request_id: requestId, resource_type: 'payees', resource_id: payeeId, version: 3, status: 'succeeded'};
export const found = (value: Record<string, unknown> = receipt) => ({status: 'succeeded', request_id: requestId, receipt: value});
export function mockApi(options: {payee?: Record<string, unknown>; group?: Record<string, unknown>; rows?: unknown[]; write?: (path: string, args?: {method?: string; body?: unknown; idempotencyKey?: string}) => Promise<Record<string, unknown>>} = {}) {
  return vi.fn(async (path: string, args?: {method?: string; body?: unknown; idempotencyKey?: string}) => {
    if (args?.method || path.startsWith('operations/requests/')) return options.write ? options.write(path, args) : found();
    if (path.startsWith('operations/groups/')) return groupDetail(options.rows ?? [options.payee ?? payeeRow], options.group ?? groupRow);
    if (path.startsWith('operations/payees/')) return {...payeeDetail, resource: options.payee ?? payeeRow};
    throw new Error(`Unexpected ${path}`);
  });
}
export function context(request: LegacyPayeeContext['request']): LegacyPayeeContext {return {id: payeeId, request, identity, actorId: actor, permissions, financialModel: 'transaction_journals', enabled: true, isCurrent: () => true, verifyFresh: async () => true, storage: sessionStorage, sharedStorage: localStorage, lock: async (_name, work) => work(), createKey: () => key};}
export function access(request: FeatureAccess['request']): FeatureAccess {return {request, actorId: actor, principalId: null, role: 'admin', authorityKey: 'synthetic-session', permissions, financialModel: 'transaction_journals', navigate: vi.fn()};}
