import {beforeEach, describe, expect, it, vi} from 'vitest';
import {canonicalRequestId} from '../../src/features/core/pendingAttempt';
import {checkNote, readNoteAttempt, retryNote, submitNote, type NoteContext} from '../../src/features/notes/noteActions';

const id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const actor = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const principal = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const note = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const identity = {id: actor, sessionId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', email: 'fixture@example.test',
  role: 'admin' as const, permissions: ['collections.read', 'account.manage'], expiresAt: '2099-01-01T00:00:00.000Z'};
const marker = {contract_version: 2, model: 'canonical_evidence_ledger'};
const lock = async <T>(_name: string, work: () => Promise<T>) => work();
function context(request: NoteContext['request'], changes: Partial<NoteContext> = {}): NoteContext {
  return {identity, actorId: actor, principalId: principal, permissions: identity.permissions, area: 'groups', id,
    request, isCurrent: () => true, allowMutations: true, pendingStorage: sessionStorage, fenceStorage: localStorage, lock, ...changes};
}
async function success(key: string) {
  return {status: 'succeeded', request_id: await canonicalRequestId(principal, key), resource_type: 'operator_notes', resource_id: note, version: 1};
}
beforeEach(() => {sessionStorage.clear(); localStorage.clear();});

describe('original support note requests', () => {
  it('keeps writes gated and requires both note and recovery permissions', async () => {
    const request = vi.fn();
    await expect(submitNote(context(request, {allowMutations: false}), 'A private support note')).rejects.toThrow();
    await expect(submitNote(context(request, {permissions: ['collections.read']}), 'A private support note')).rejects.toThrow();
    expect(request).not.toHaveBeenCalled();
  });
  it('retains only a digest after an uncertain write and retries the same key only for the original text', async () => {
    let original = ''; let posts = 0;
    const request: NoteContext['request'] = vi.fn(async (_path, options) => {
      if (options?.method === 'POST') {
        posts += 1;
        if (!original) {original = options.idempotencyKey!; throw new Error('response lost');}
        expect(options.idempotencyKey).toBe(original);
        return success(original);
      }
      return {...marker, status: 'not_found'};
    });
    const ctx = context(request);
    await expect(submitNote(ctx, 'A private support note')).rejects.toThrow();
    const saved = await readNoteAttempt(ctx);
    expect(saved?.request_key).toBe(original);
    expect(JSON.stringify(sessionStorage)).not.toContain('A private support note');
    expect(JSON.stringify(localStorage)).not.toContain('A private support note');
    expect(await checkNote(ctx, saved!)).toBe('not_found');
    await expect(retryNote(ctx, saved!, 'A different note')).rejects.toThrow();
    expect(posts).toBe(1);
    expect(await retryNote(ctx, saved!, 'A private support note')).toBe('succeeded');
    expect(posts).toBe(2);
    expect(await readNoteAttempt(ctx)).toBeNull();
  });
  it('does not clear a request after authority changes during the response', async () => {
    let current = true;
    const request: NoteContext['request'] = async (_path, options) => {
      const value = await success(options!.idempotencyKey!); current = false; return value;
    };
    const ctx = context(request, {isCurrent: () => current});
    await expect(submitNote(ctx, 'A private support note')).rejects.toThrow();
    current = true;
    expect(await readNoteAttempt(ctx)).not.toBeNull();
  });
});
