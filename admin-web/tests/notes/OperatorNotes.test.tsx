import {render, screen, waitFor} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import {describe, expect, it, vi} from 'vitest';
import {canonicalRequestId} from '../../src/features/core/pendingAttempt';
import type {AdminRequest} from '../../src/api/client';
import {OperatorNotes, parseOperatorNotes} from '../../src/features/notes/OperatorNotes';

const id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const note = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const actor = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const identity = {id: actor, sessionId: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd', email: 'fixture@example.test',
  role: 'admin' as const, permissions: ['collections.read', 'account.manage'], expiresAt: '2099-01-01T00:00:00.000Z'};
const access = {identity, actorId: actor, principalId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'};
const page = {contract_version: 1, entity_type: 'collection', entity_id: id, total: 1, limit: 25, offset: 0,
  rows: [{id: note, body: '<img src=x onerror=alert(1)>', created_by: actor, author_name: 'Team member', created_at: '2026-11-16T12:00:00.000Z'}]};

describe('support notes', () => {
  it('accepts only the requested entity, complete page and unique rows', () => {
    expect(parseOperatorNotes(page, 'groups', id, 0).rows).toHaveLength(1);
    expect(() => parseOperatorNotes({...page, entity_id: actor}, 'groups', id, 0)).toThrow();
    expect(() => parseOperatorNotes({...page, total: 2}, 'groups', id, 0)).toThrow();
    expect(() => parseOperatorNotes({...page, total: 2, rows: [page.rows[0], page.rows[0]]}, 'groups', id, 0)).toThrow();
    expect(() => parseOperatorNotes({...page, rows: [{...page.rows[0], body: 'private\u0000text'}]}, 'groups', id, 0)).toThrow();
  });
  it('renders private note text as text and issues no write', async () => {
    const request = vi.fn(async () => page);
    const {container} = render(<OperatorNotes {...access} request={request} permissions={['collections.read']} authorityKey="session-a" area="groups" id={id} />);
    expect(await screen.findByText(page.rows[0].body)).toBeInTheDocument();
    expect(container.querySelector('img')).toBeNull();
    expect(screen.getByText('Recording new notes is currently unavailable.')).toBeInTheDocument();
    expect(request).toHaveBeenCalledWith(`operations/groups/${id}/notes?limit=25&offset=0`, expect.objectContaining({authenticated: true}));
    expect(request.mock.calls).toHaveLength(1);
  });
  it('does not fetch or show old content after permission loss', async () => {
    const request = vi.fn(async () => page);
    const {rerender} = render(<OperatorNotes {...access} request={request} permissions={['collections.read']} authorityKey="session-a" area="groups" id={id} />);
    await screen.findByText(page.rows[0].body);
    rerender(<OperatorNotes {...access} request={request} permissions={[]} authorityKey="session-b" area="groups" id={id} />);
    await waitFor(() => expect(screen.queryByText(page.rows[0].body)).not.toBeInTheDocument());
    expect(request).toHaveBeenCalledTimes(1);
  });
  it('records a note only when the write gate is enabled and verifies the receipt', async () => {
    sessionStorage.clear(); localStorage.clear();
    const previous = Object.getOwnPropertyDescriptor(navigator, 'locks');
    Object.defineProperty(navigator, 'locks', {configurable: true, value: {request: async (_name: string, _options: unknown, action: (lock: object) => Promise<unknown>) => action({})}});
    const principal = access.principalId;
    const request: AdminRequest = vi.fn(async (_path, options) => options?.method === 'POST' ?
      {status: 'succeeded', request_id: await canonicalRequestId(principal, options.idempotencyKey!), resource_type: 'operator_notes', resource_id: note, version: 1} : page);
    try {
      render(<OperatorNotes {...access} request={request} permissions={['collections.read', 'account.manage']} authorityKey="session-a" area="groups" id={id} allowMutations />);
      const input = await screen.findByLabelText('Support note');
      await userEvent.type(input, 'A private note');
      await userEvent.click(screen.getByRole('button', {name: 'Record note'}));
      await screen.findByText('The note request was recorded.');
      expect(JSON.stringify(sessionStorage)).not.toContain('A private note');
      expect(JSON.stringify(localStorage)).not.toContain('A private note');
    } finally {
      if (previous) Object.defineProperty(navigator, 'locks', previous);
      else Reflect.deleteProperty(navigator, 'locks');
    }
  });
});
