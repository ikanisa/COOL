import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { MembershipCreatePage } from '../../src/features/core/MembershipCreatePage';
import { MembershipEditPage } from '../../src/features/core/MembershipEditPage';
import { retainPending, type PendingIdentity } from '../../src/features/core/pendingAttempt';
import type { FeatureAccess } from '../../src/features/core/types';

const actor = '11111111-1111-4111-8111-111111111111', key = '22222222-2222-4222-8222-222222222222', requestId = '33333333-3333-4333-8333-333333333333', groupId = '44444444-4444-4444-8444-444444444444', userId = '55555555-5555-4555-8555-555555555555', otherGroup = '66666666-6666-4666-8666-666666666666';
const identity: PendingIdentity = {id: actor, sessionId: 'session-1', email: 'operator@example.test', role: 'admin', permissions: ['collections.read', 'users.read', 'users.manage', 'overview.read'], expiresAt: '2100-01-01T00:00:00.000Z'};
const access: Omit<FeatureAccess, 'request'> = {actorId: actor, principalId: null, role: 'admin', authorityKey: 'session-1', permissions: identity.permissions, financialModel: 'transaction_journals', navigate: vi.fn()};
const person = {id: userId, public_id: '123456', display_name: 'Recorded Person', member_type: 'app', momo_number: '0788123456', version: 4};
const detail = {resource_type: 'users', current_actor_id: actor, can_manage: true, resource: {...person, collect_user_id: userId, display_name_recorded: true, status: 'active'}};
const row = {group_id: groupId, user_id: userId, group_title: 'Test group', public_id: person.public_id, display_name: person.display_name, display_name_recorded: 1, member_type: person.member_type, momo_number: person.momo_number, role: 'member', status: 'active', version: 2};
function group(rows: unknown[]) {return {resource_type: 'groups', current_actor_id: actor, can_manage: true, resource: {id: groupId, title: 'Test group', country_code: 'RW', currency: 'RWF', status: 'active', version: 3}, related: {memberships: rows}, related_pages: {memberships: {total: rows.length, limit: 100, offset: 0, next_offset: null}}, related_truncated: false};}
const create = {group_id: groupId, user_id: userId, role: 'member', status: 'active', reason: 'Review membership creation'}, edit = {role: 'admin', status: 'active', expected_version: 2, reason: 'Review membership change'};
const receipt = {request_id: requestId, resource_type: 'memberships', resource_id: `${groupId}/${userId}`, version: 1, status: 'succeeded'}, originalLocks = Object.getOwnPropertyDescriptor(navigator, 'locks');
beforeEach(() => {sessionStorage.clear(); localStorage.clear(); Object.defineProperty(navigator, 'locks', {configurable: true, value: {request: async (name: string, _options: unknown, work: (lock: {name: string}) => Promise<unknown>) => work({name})}});});
afterEach(() => {if (originalLocks) Object.defineProperty(navigator, 'locks', originalLocks); else Reflect.deleteProperty(navigator, 'locks');});

describe('legacy membership pages', () => {
  it('routes both membership operations while keeping changes disabled by default', async () => {
    const request = vi.fn(), page = render(<MembershipCreatePage {...access} id={groupId} request={request} identity={identity} verifyFresh={async () => false} />);
    expect(await screen.findByText('Membership changes are not enabled for this workspace.')).toBeVisible(); expect(screen.queryByRole('button', {name: 'Review membership'})).not.toBeInTheDocument();
    page.unmount(); render(<MembershipEditPage {...access} groupId={groupId} userId={userId} request={request} identity={identity} verifyFresh={async () => false} />);
    expect(await screen.findByText('Membership changes are not enabled for this workspace.')).toBeVisible(); expect(request).not.toHaveBeenCalled();
  });
  it('reviews a searched person and sends the exact membership creation only after confirmation', async () => {
    const user = userEvent.setup(), request = vi.fn(async (path: string, options?: {method?: string; body?: unknown}) => {
      if (options?.method) {expect(options.body).toEqual(create); return receipt;}
      if (path.startsWith('operations/lookups?')) return {rows: [person]}; if (path.startsWith('operations/groups/')) return group([]); if (path.startsWith('operations/users/')) return detail; return {status: 'succeeded', request_id: requestId, receipt};
    });
    render(<MembershipCreatePage {...access} id={groupId} request={request} identity={identity} allowMutations verifyFresh={async () => true} />);
    await user.type(await screen.findByLabelText('Search people'), 'Recorded'); await user.click(screen.getByRole('button', {name: 'Search people'}));
    await user.selectOptions(await screen.findByLabelText('Person'), userId); await user.type(screen.getByLabelText('Reason'), create.reason); await user.click(screen.getByRole('button', {name: 'Review membership'}));
    expect(await screen.findByText(/Person: Recorded Person/)).toBeVisible(); expect(screen.getByRole('button', {name: 'Confirm membership'})).toBeDisabled();
    await user.click(screen.getByRole('checkbox', {name: 'I reviewed the group, person, membership and reason.'})); await user.click(screen.getByRole('button', {name: 'Confirm membership'}));
    const result = await screen.findByRole('status'); expect(within(result).getByText('The membership request was recorded.')).toBeVisible(); expect(request.mock.calls.filter(([, options]) => !!options?.method)).toHaveLength(1);
  });
  it('reviews current version and sends the exact membership edit after fresh verification', async () => {
    const user = userEvent.setup(), changed = {...receipt, version: 3}, verifyFresh = vi.fn().mockResolvedValue(true), request = vi.fn(async (path: string, options?: {method?: string; body?: unknown}) => {
      if (options?.method) {expect(options.body).toEqual(edit); return changed;} if (path.startsWith('operations/groups/')) return group([row]); if (path.startsWith('operations/users/')) return detail; return {status: 'succeeded', request_id: requestId, receipt: changed};
    });
    render(<MembershipEditPage {...access} groupId={groupId} userId={userId} request={request} identity={identity} allowMutations verifyFresh={verifyFresh} />);
    await user.selectOptions(await screen.findByLabelText('Role'), 'admin'); await user.type(screen.getByLabelText('Reason'), edit.reason); await user.click(screen.getByRole('button', {name: 'Review membership'}));
    expect(await screen.findByText(/Current membership: member \/ active · version 2/)).toBeVisible(); await user.click(screen.getByRole('checkbox', {name: 'I reviewed the group, person, membership and reason.'})); await user.click(screen.getByRole('button', {name: 'Confirm membership'}));
    expect(await screen.findByText('The membership request was recorded.')).toBeVisible(); expect(verifyFresh).toHaveBeenCalledOnce();
  });
  it('checks old unbound requests without offering retry and identifies the original group', async () => {
    await retainPending(identity, 'operating-createmembership', 'new', key, 'users.manage', {...create, group_id: otherGroup});
    const request = vi.fn(), user = userEvent.setup(); render(<MembershipCreatePage {...access} id={groupId} request={request} identity={identity} verifyFresh={async () => false} />);
    expect(await screen.findByText(new RegExp(`belongs to group ${otherGroup}`))).toBeVisible(); expect(screen.getByRole('button', {name: 'Check request'})).toBeDisabled(); expect(screen.queryByRole('button', {name: 'Review same request'})).not.toBeInTheDocument();
    await user.click(screen.getByRole('button', {name: 'Check request'})); expect(request).not.toHaveBeenCalled();
  });
  it('blocks a write when fresh account verification fails', async () => {
    const user = userEvent.setup(), request = vi.fn(async (path: string, options?: {method?: string}) => {if (options?.method) throw new Error('unexpected write'); if (path.startsWith('operations/groups/')) return group([row]); return detail;});
    render(<MembershipEditPage {...access} groupId={groupId} userId={userId} request={request} identity={identity} allowMutations verifyFresh={async () => false} />);
    await user.selectOptions(await screen.findByLabelText('Role'), 'admin'); await user.type(screen.getByLabelText('Reason'), edit.reason); await user.click(screen.getByRole('button', {name: 'Review membership'}));
    await user.click(await screen.findByRole('checkbox', {name: 'I reviewed the group, person, membership and reason.'})); await user.click(screen.getByRole('button', {name: 'Confirm membership'}));
    expect(await screen.findByText(/recovery data could not be verified/)).toBeVisible(); expect(request.mock.calls.every(([, options]) => !options?.method)).toBe(true);
  });
});
