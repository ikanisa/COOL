import { describe, expect, it } from 'vitest';
import type { PendingAttempt } from '../../src/features/core/pendingAttempt';
import { parseBuriDirectory, parseBuriProvisioning, parseBuriScopes } from '../../src/features/burimunsi/contracts';
import { parseBuriOutcome, parseBuriPending } from '../../src/features/burimunsi/recovery';
import { account, approval, collectionId, directory, grant, nativeIntent, nativeReceipt, operator, operatorIntent, operatorReceipt, provisioning, requestId, scopes, staffPrincipal } from './fixture';
function entry(family: string, intent: Record<string, unknown>): PendingAttempt {return {family, resource_id: `${collectionId}:${staffPrincipal}`, request_key: requestId, permission: 'admin_users.manage', intent, created_at: 1, expires_at: 2};}

describe('BuriMunsi scoped read contracts', () => {
  it('maps only prepared existing groups and rejects ambiguous or malformed source state', () => {
    expect(parseBuriScopes(scopes)).toEqual([{id: collectionId, title: 'Synthetic savings', version: 2, enabled: true, paired: true, receivingAccountId: 'synthetic-receiver', receiverKeyId: 'synthetic-key', receiverInstallationId: grant.installationId, replacementPending: false}]);
    expect(() => parseBuriScopes({...scopes, scopes: [scopes.scopes[0], scopes.scopes[0]]})).toThrow();
    expect(parseBuriScopes({...scopes, collections: [{...scopes.collections[0], title: ''}]})).toMatchObject([{id: collectionId, title: `Group ${collectionId}`}]);
    expect(() => parseBuriScopes({...scopes, scopes: [{...scopes.scopes[0], pendingReplacement: {phase: 'prepared'}}]})).toThrow();
    expect(() => parseBuriScopes({...scopes, installations: [{installationId: grant.installationId}]})).toThrow();
  });
  it('validates operator identity, capabilities, unique phone and scope binding', () => {
    expect(parseBuriDirectory(directory, collectionId).approvals[0]).toMatchObject({phone: approval.phone, active: true, operator});
    expect(() => parseBuriDirectory(directory, 'other-scope')).toThrow();
    expect(() => parseBuriDirectory({...directory, team: [operator, operator]}, collectionId)).toThrow();
    expect(() => parseBuriDirectory({...directory, approvals: [{...approval, capabilities: ['records.read', 'gateway.manage']}]}, collectionId)).toThrow();
    expect(() => parseBuriDirectory({...directory, approvals: [{...approval, sharedRole: 'admin'}]}, collectionId)).toThrow();
    expect(() => parseBuriDirectory({...directory, approvals: [{...approval, phone: '0780000002'}]}, collectionId)).toThrow();
  });
  it('validates native accounts and installation grants without treating recorded access as device possession', () => {
    const parsed = parseBuriProvisioning(provisioning, collectionId); expect(parsed.accounts[0]).toMatchObject(account); expect(parsed.grants[0]).toMatchObject(grant);
    expect(() => parseBuriProvisioning({...provisioning, grants: [grant, grant]}, collectionId)).toThrow();
    expect(() => parseBuriProvisioning({...provisioning, accounts: [{...account, credentialVersion: 0}]}, collectionId)).toThrow();
    expect(() => parseBuriProvisioning({...provisioning, scopeVersion: null}, collectionId)).toThrow();
    expect(() => parseBuriProvisioning({...provisioning, collectionId: 'other'}, collectionId)).toThrow();
  });
  it('validates retained Flutter approvals and only accepts a matching read-only original receipt', () => {
    const pending = parseBuriPending(entry('burimunsi.operator', operatorIntent));
    expect(parseBuriOutcome({contractVersion: 1, collectionId, found: false}, pending)).toBe('not_found');
    expect(parseBuriOutcome({contractVersion: 1, collectionId, found: true, receipt: operatorReceipt}, pending)).toBe('recorded');
    expect(() => parseBuriOutcome({contractVersion: 1, collectionId, found: true, receipt: {...operatorReceipt, version: 2}}, pending)).toThrow();
    expect(() => parseBuriPending({...entry('burimunsi.operator', operatorIntent), request_key: grant.id})).toThrow();
    expect(() => parseBuriPending(entry('burimunsi.operator', {...operatorIntent, capabilities: ['records.read', 'sms.read']}))).toThrow();
  });
  it('checks native outcomes without retaining a PIN, replaying, clearing or opening protected delivery', () => {
    const pending = parseBuriPending(entry('burimunsi.provisioning', nativeIntent));
    expect(parseBuriOutcome({contractVersion: 1, collectionId, requestId, found: true, receipt: nativeReceipt}, pending)).toBe('recorded');
    expect(parseBuriOutcome({contractVersion: 1, collectionId, requestId, found: false}, pending)).toBe('not_found');
    expect(parseBuriOutcome({contractVersion: 1, collectionId, requestId, found: true, receipt: {contractVersion: 1, collectionId, requestId, operation: 'cancelled', applied: false}}, pending)).toBe('cancelled');
    expect(() => parseBuriPending(entry('burimunsi.provisioning', {...nativeIntent, pin: '1234'}))).toThrow();
    expect(() => parseBuriOutcome({contractVersion: 1, collectionId, requestId, found: true, receipt: {...nativeReceipt, scopeVersion: 3}}, pending)).toThrow();
  });
});
