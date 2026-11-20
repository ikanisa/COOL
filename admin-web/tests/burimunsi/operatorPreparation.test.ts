import {describe, expect, it} from 'vitest';
import {parseBuriDirectory} from '../../src/features/burimunsi/contracts';
import {prepareBuriApproval} from '../../src/features/burimunsi/operatorPreparation';
import {approval, collectionId, directory, staffPrincipal} from './fixture';

const input = {phone: '078 000 0002', role: 'staff', capabilities: ['records.read', 'members.enroll'], active: false};
describe('BuriMunsi operator approval preview', () => {
  it('prepares an existing approval using its recorded group, person and version', () => {
    const source = parseBuriDirectory(directory, collectionId), draft = prepareBuriApproval(source, staffPrincipal, input);
    expect(draft).toMatchObject({collectionId, operator: {principalId: staffPrincipal}, phone: '+250780000002', role: 'staff', active: false, expectedVersion: 1});
    expect(draft.capabilities).toEqual(['members.enroll', 'records.read']);
    expect(draft).not.toHaveProperty('requestId');
  });
  it('requires a current eligible account and a valid creation or approval state', () => {
    const source = parseBuriDirectory(directory, collectionId), noApproval = {...source, approvals: []};
    expect(() => prepareBuriApproval(source, 'not-the-person', input)).toThrow(/current Collect account/);
    expect(() => prepareBuriApproval({...source, configured: false}, staffPrincipal, input)).toThrow(/group needs to be prepared/);
    expect(() => prepareBuriApproval(noApproval, staffPrincipal, input)).toThrow(/new approval must be enabled/);
    expect(prepareBuriApproval(noApproval, staffPrincipal, {...input, active: true}).expectedVersion).toBe(0);
    expect(() => prepareBuriApproval({...source, team: []}, staffPrincipal, {...input, active: true})).toThrow(/active Collect account/);
    expect(() => prepareBuriApproval({...source, team: []}, staffPrincipal, input)).not.toThrow();
  });
  it('enforces source role and capability restrictions and rejects malformed phones', () => {
    const source = parseBuriDirectory(directory, collectionId), newApproval = {...source, approvals: []};
    expect(() => prepareBuriApproval(source, staffPrincipal, {...input, role: 'admin'})).toThrow(/role of an existing approval/);
    expect(() => prepareBuriApproval(newApproval, staffPrincipal, {...input, active: true, role: 'admin'})).toThrow(/administrator Collect account/);
    expect(() => prepareBuriApproval(source, staffPrincipal, {...input, capabilities: ['records.read', 'gateway.manage']})).toThrow(/permitted access/);
    expect(() => prepareBuriApproval(source, staffPrincipal, {...input, capabilities: ['members.enroll']})).toThrow(/permitted access/);
    expect(() => prepareBuriApproval(source, staffPrincipal, {...input, capabilities: ['records.read', 'records.read']})).toThrow(/permitted access/);
    expect(() => prepareBuriApproval(source, staffPrincipal, {...input, phone: 'call me 0780000002'})).toThrow(/Rwanda login phone/);
    expect(() => prepareBuriApproval({...source, approvals: [{...source.approvals[0], version: Number.MAX_SAFE_INTEGER}]}, staffPrincipal, input)).toThrow(/version/);
    expect(approval.active).toBe(true);
  });
});
