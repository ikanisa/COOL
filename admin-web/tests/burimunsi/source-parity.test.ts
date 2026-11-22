import {describe, expect, it} from 'vitest';
import {parseBuriDirectory, parseBuriProvisioning, parseBuriScopes} from '../../src/features/burimunsi/contracts';
import {parseBuriPending} from '../../src/features/burimunsi/recovery';
import {prepareBuriApproval} from '../../src/features/burimunsi/operatorPreparation';
import {operatorIntent, requestId, staffPrincipal} from './fixture';
import captured from './source-parity.generated.json';

// Synthetic outputs produced by the pinned Cloud source SQL functions and
// validating adapters; regenerate/verify with source-parity.postgres.mjs.
const group = 'synthetic-savings';

describe('BuriMunsi server-source directory parity', () => {
  it('accepts empty unconfigured results from all three server directories', () => {
    expect(parseBuriScopes(captured.empty.setup)).toEqual([]);
    expect(parseBuriDirectory(captured.empty.operators, group)).toEqual({collectionId: group, configured: false, team: [], approvals: []});
    expect(parseBuriProvisioning(captured.empty.provisioning, group)).toEqual({collectionId: group, configured: false, scopeVersion: null, scopeEnabled: false, accounts: [], grants: []});
  });
  it('preserves scope identity and version for empty and long legacy titles', () => {
    const groups = parseBuriScopes(captured.populated.setup);
    expect(groups.find(item => item.id === 'untitled-other')).toMatchObject({title: 'Group untitled-other', version: 3});
    expect(groups.find(item => item.id === 'long-title')).toMatchObject({title: `${'L'.repeat(157)}… (long-title)`, version: 2});
    expect(groups.find(item => item.id === 'multiline')).toMatchObject({title: 'Synthetic line', version: 2});
    expect(groups.find(item => item.id === group)).toMatchObject({title: 'Synthetic savings', version: 7, enabled: false, paired: false});
  });
  it('retains exact legacy operator identifiers and approval versions without retargeting', () => {
    const directory = parseBuriDirectory(captured.populated.operators, group);
    expect(directory.team.find(person => person.adminId === 'legacy-staff-42')).toMatchObject({principalId: '55555555-5555-4555-8555-555555555555'});
    expect(directory.approvals.find(approval => approval.operator.adminId === 'legacy-staff-42')).toMatchObject({active: true, version: 5});
    const legacy = parseBuriDirectory(captured.opaquePrincipal, group);
    expect(legacy.team.find(person => person.adminId === 'legacy-admin-47')).toMatchObject({principalId: 'Legacy-Principal-47'});
    expect(parseBuriDirectory(captured.legacyApproval, group).approvals.find(approval => approval.operator.adminId === 'legacy-admin-47')).toMatchObject({version: 1, active: true});
    expect(captured.legacyProvisioningFailure).toEqual({status: 400, code: 'invalid_parameter'});
    expect(() => parseBuriDirectory(captured.mismatched, group)).toThrow();
    expect(() => parseBuriDirectory({...captured.populated.operators, collectionId: 'wrong-group'}, group)).toThrow();
  });
  it('preserves provisioning versions, a null native account and an uncustodied grant', () => {
    const native = parseBuriProvisioning(captured.populated.provisioning, group);
    expect(native).toMatchObject({configured: true, scopeVersion: 7, scopeEnabled: false});
    expect(native.accounts.find(account => account.principalId === 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')).toMatchObject({accountId: null, version: 0, credentialVersion: 0, approvalVersion: 3, approved: false});
    expect(native.accounts.find(account => account.accountId !== null)).toMatchObject({version: 6, credentialVersion: 2, approvalVersion: 5});
    expect(native.grants[0]).toMatchObject({accountId: null, version: 9, profile: 'internal_receiver'});
    expect(() => parseBuriProvisioning({...captured.populated.provisioning, collectionId: 'wrong-group'}, group)).toThrow();
    expect(() => parseBuriProvisioning({...captured.populated.provisioning, grants: [...captured.populated.provisioning.grants, ...captured.populated.provisioning.grants]}, group)).toThrow();
  });
  it('keeps legacy operator IDs read-only and retains strict recovery and provisioning identifiers', () => {
    const directory = parseBuriDirectory(captured.populated.operators, group);
    const draft = prepareBuriApproval(directory, staffPrincipal, {phone: '+250780000002', role: 'staff', capabilities: ['records.read'], active: true});
    expect(draft.operator.adminId).toBe('legacy-staff-42'); // A local preview, never a mutation.
    const attempt = {family: 'burimunsi.operator', permission: 'admin_users.manage', resource_id: `${group}:${staffPrincipal}`, request_key: requestId, created_at: 1, expires_at: 2,
      intent: {...operatorIntent, adminId: 'legacy-staff-42'}};
    expect(() => parseBuriPending(attempt)).toThrow();
    const legacyPrincipal = 'Legacy-Principal-47';
    expect(() => parseBuriPending({...attempt, resource_id: `${group}:${legacyPrincipal}`, intent: {...operatorIntent, principalId: legacyPrincipal}})).toThrow();
    expect(() => parseBuriProvisioning({...captured.populated.provisioning, accounts: [{...captured.populated.provisioning.accounts[0], principalId: legacyPrincipal}]}, group)).toThrow();
  });
});
