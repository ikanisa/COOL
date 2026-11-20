import {webcrypto} from 'node:crypto';
import {afterEach, describe, expect, it, vi} from 'vitest';
import {canonicalRequestId} from '../../src/features/core';
import {parseHistory, parseLookup, parseReceipt} from '../../src/features/requests/contracts';

const principal = '12345678-1234-4123-8123-123456789012';
const resource = '87654321-4321-4321-8321-210987654321';
const key = 'request-original-001';

afterEach(() => vi.unstubAllGlobals());

describe('request history contracts', () => {
  it('binds a canonical receipt to the original actor and key', async () => {
    vi.stubGlobal('crypto', webcrypto);
    const id = await canonicalRequestId(principal, key);
    const receipt = {request_id: id, status: 'succeeded', resource_type: 'groups', resource_id: resource, version: 2};
    const row = {id, idempotency_key: key, scope: 'groups.patch', status: 'succeeded', receipt, created_at: '2026-11-16T12:00:00.000Z'};
    const result = await parseHistory({contract_version: 2, model: 'canonical_evidence_ledger', rows: [row], total: 1}, 'canonical_evidence_ledger', principal, 0);
    expect(result.rows[0].receipt?.requestId).toBe(id);
    await expect(parseHistory({contract_version: 2, model: 'canonical_evidence_ledger', rows: [{...row, scope: 'users.patch'}], total: 1}, 'canonical_evidence_ledger', principal, 0)).rejects.toThrow(/could not be verified/);
    await expect(parseLookup({contract_version: 2, model: 'canonical_evidence_ledger', status: 'succeeded', request_id: resource, receipt}, 'canonical_evidence_ledger', principal, key)).rejects.toThrow(/could not be verified/);
  });

  it('accepts not-found without representing it as a failed mutation', async () => {
    const result = await parseLookup({contract_version: 2, model: 'canonical_evidence_ledger', status: 'not_found'}, 'canonical_evidence_ledger', principal, key);
    expect(result).toEqual({status: 'not_found', receipt: null});
  });

  it('recovers a retained text principal receipt only for its original actor and request key', async () => {
    vi.stubGlobal('crypto', webcrypto);
    const actor = 'Legacy-Principal-47', original = 'receipt-check-0001', id = 'c06c9f2f-eb12-4c12-8fbf-34353eb7f1e6';
    const receipt = {request_id: id, status: 'succeeded', resource_type: 'groups', resource_id: resource, version: 2};
    const lookup = {contract_version: 2, model: 'canonical_evidence_ledger', status: 'succeeded', request_id: id, receipt};
    expect((await parseLookup(lookup, 'canonical_evidence_ledger', actor, original)).receipt?.requestId).toBe(id);
    await expect(parseLookup(lookup, 'canonical_evidence_ledger', actor.toLowerCase(), original)).rejects.toThrow();
    await expect(parseLookup(lookup, 'canonical_evidence_ledger', actor, 'receipt-check-0002')).rejects.toThrow();
  });

  it('requires an internally consistent SMS receipt', () => {
    const receipt = {request_id: principal, status: 'succeeded', resource_type: 'sms_facts', resource_id: resource,
      source_kind: 'capture', source_id: resource, parser_version: 'collect-admin-source-facts-v1'};
    expect(parseReceipt(receipt).scope).toBe('sms.extract');
    expect(() => parseReceipt({...receipt, parser_version: 'unverified'})).toThrow(/could not be verified/);
  });
});
