import { webcrypto } from 'node:crypto';
import { act, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { SessionContextValue } from '../../src/session/SessionProvider';
import { PENDING_KEY, readPending, retainPending } from '../../src/features/core/pendingAttempt';
import { GUARDED_OPERATOR_FAMILY } from '../../src/features/burimunsi/recovery';
import { BuriMunsiPage } from '../../src/features/burimunsi';
import { accountId, collectionId, directory, grantId, installationId, nativeIntent, nativeReceipt, operatorIntent, operatorReceipt, owner, provisioning, requestId, scopes, staffPrincipal } from './fixture';

const hook = vi.hoisted(() => ({value: null as unknown as SessionContextValue}));
vi.mock('../../src/session/SessionProvider', async importOriginal => ({...await importOriginal<typeof import('../../src/session/SessionProvider')>(), useSession: () => hook.value}));
let current = true, fresh = true, verificationAllowed = true;
const identity = {id: owner.id, sessionId: owner.sessionId, email: owner.email, role: owner.role, permissions: owner.permissions, expiresAt: owner.expiresAt};
function setup(options: {user?: typeof owner; request?: SessionContextValue['request']; verificationMode?: 'email' | 'authenticator';} = {}) {
  const request = options.request ?? vi.fn(async (path: string) => {
    if (path === 'momo/native-setup') return scopes;
    if (path.startsWith('burimunsi/operators?')) return directory;
    if (path.startsWith('burimunsi/provisioning?')) return provisioning;
    throw new Error(`Unexpected ${path}`);
  });
  const session = {status: 'authenticated', user: options.user ?? {...owner}, epoch: 7, verificationMode: options.verificationMode ?? 'email', request,
    isCurrentAuthority: () => current, isRecentSensitiveVerification: () => fresh, sensitiveEmailRecovery: () => null,
    recheckSensitiveEmailVerification: vi.fn(async () => {if (!verificationAllowed) return false; fresh = true; return true;})} as unknown as SessionContextValue;
  hook.value = session; return session;
}
beforeEach(() => {sessionStorage.clear(); localStorage.clear(); current = true; fresh = true; verificationAllowed = true; Object.defineProperty(globalThis, 'crypto', {value: webcrypto, configurable: true});});

describe('BuriMunsi read-only access', () => {
  it('fails closed without server-attested owner identity and performs no request', () => {
    const session = setup({user: {...owner, ownerIdentity: null}}); render(<BuriMunsiPage operatorPreparationEnabled />);
    expect(screen.getByText(/protected owner identity bound to this session/)).toBeVisible(); expect(session.request).not.toHaveBeenCalled(); expect(session.recheckSensitiveEmailVerification).not.toHaveBeenCalled();
    expect(screen.queryByRole('heading', {name: 'Prepare operator access'})).not.toBeInTheDocument();
  });
  it('rejects a mismatched owner, missing permissions or a non-managed verification mode', () => {
    const session = setup({user: {...owner, ownerIdentity: {...owner.ownerIdentity!, principalId: staffPrincipal}}}), page = render(<BuriMunsiPage />);
    expect(screen.getByText(/protected owner identity bound to this session/)).toBeVisible();
    hook.value = {...session, user: {...owner, permissions: ['admin_users.manage']}}; page.rerender(<BuriMunsiPage />); expect(screen.getByText(/needs current team and receiving-phone permissions/)).toBeVisible();
    hook.value = {...session, verificationMode: 'authenticator', user: owner}; page.rerender(<BuriMunsiPage />); expect(screen.getByText(/protected owner identity bound to this session/)).toBeVisible(); expect(session.request).not.toHaveBeenCalled();
  });
  it('requires fresh email proof before any BuriMunsi read', async () => {
    fresh = false; verificationAllowed = false; const session = setup(), user = userEvent.setup(); render(<BuriMunsiPage />);
    await user.click(screen.getByRole('button', {name: 'Check verification and load groups'}));
    expect(await screen.findByText(/Owner verification, prepared groups or retained requests could not be confirmed/)).toBeVisible(); expect(session.request).not.toHaveBeenCalled();
  });
  it('reads the selected group, approved operators and recorded native grants without any mutation', async () => {
    const session = setup(), user = userEvent.setup(); render(<BuriMunsiPage />);
    await user.click(screen.getByRole('button', {name: 'Check verification and load groups'})); expect(await screen.findByRole('option', {name: 'Synthetic savings'})).toBeInTheDocument();
    await user.click(screen.getByRole('button', {name: 'Load group access'})); expect(await screen.findByRole('heading', {name: 'Collect operators'})).toBeVisible();
    expect(screen.getByRole('row', {name: /staff@example.test/})).toBeVisible(); expect(screen.getByText(/does not confirm physical device possession/)).toBeVisible();
    expect(session.request).toHaveBeenCalledWith(`burimunsi/operators?collectionId=${collectionId}`); expect(session.request).toHaveBeenCalledWith(`burimunsi/provisioning?collectionId=${collectionId}`);
    expect(vi.mocked(session.request).mock.calls.every(([, options]) => !options?.method || options.method === 'GET')).toBe(true);
    expect(screen.queryByRole('button', {name: /approve|grant|set pin|save access/i})).not.toBeInTheDocument();
    expect(screen.queryByRole('heading', {name: 'Prepare operator access'})).not.toBeInTheDocument();
  });
  it('keeps the hosted review read-only even if action flags are supplied and a checkpoint exists', async () => {
    await retainPending(identity, 'burimunsi.provisioning', `${collectionId}:${staffPrincipal}`, requestId, 'admin_users.manage', nativeIntent);
    const session = setup(), user = userEvent.setup();
    render(<BuriMunsiPage readOnlyReview operatorPreparationEnabled nativeRevocationEnabled nativePinEnabled nativeGrantEnabled />);
    await user.click(screen.getByRole('button', {name: 'Check verification and load groups'}));
    await user.click(await screen.findByRole('button', {name: 'Load group access'}));
    expect(await screen.findByRole('heading', {name: 'Native app access'})).toBeVisible();
    expect(screen.queryByText(requestId)).not.toBeInTheDocument();
    expect(screen.queryByRole('button', {name: /original request|revocation|set pin|grant|approve/i})).not.toBeInTheDocument();
    expect(screen.queryByRole('heading', {name: 'Prepare operator access'})).not.toBeInTheDocument();
    expect((await readPending(identity, 'burimunsi.provisioning', `${collectionId}:${staffPrincipal}`))?.request_key).toBe(requestId);
    expect(vi.mocked(session.request).mock.calls.every(([, options]) => !options?.method || options.method === 'GET')).toBe(true);
  });
  it('optionally previews a versioned operator change but cannot submit it', async () => {
    const session = setup(), user = userEvent.setup(); render(<BuriMunsiPage operatorPreparationEnabled />);
    await user.click(screen.getByRole('button', {name: 'Check verification and load groups'})); await user.click(await screen.findByRole('button', {name: 'Load group access'}));
    await user.selectOptions(await screen.findByRole('combobox', {name: 'Collect account'}), staffPrincipal);
    await user.selectOptions(screen.getByRole('combobox', {name: 'Access status'}), 'disabled');
    await user.click(screen.getByRole('button', {name: 'Review access'}));
    expect(await screen.findByRole('region', {name: 'Access preview'})).toHaveTextContent('Nothing has been sent or changed.');
    expect(screen.getByRole('region', {name: 'Access preview'})).toHaveTextContent('Disabled');
    expect(screen.getByRole('region', {name: 'Access preview'})).toHaveTextContent(staffPrincipal);
    expect(screen.queryByRole('button', {name: /apply|confirm|submit|save access/i})).not.toBeInTheDocument();
    expect(vi.mocked(session.request).mock.calls.every(([, options]) => !options?.method || options.method === 'GET')).toBe(true);
    await user.clear(screen.getByRole('textbox', {name: 'Login phone'}));
    expect(screen.queryByRole('region', {name: 'Access preview'})).not.toBeInTheDocument();
  });
  it('submits a negotiated principal-bound approval once and recovers a lost response by its original key', async () => {
    Object.defineProperty(navigator, 'locks', {configurable: true, value: {request: async (_name: string, _options: unknown, work: (lock: object) => Promise<unknown>) => work({})}});
    let receipt: Record<string, unknown> | null = null;
    const request = vi.fn<SessionContextValue['request']>(async (path, options = {}) => {
      if (path === 'momo/native-setup') return scopes;
      if (path.startsWith('burimunsi/operators?')) {
        expect(new URLSearchParams(path.split('?')[1]).get('approvalContract')).toBe('2');
        return {...directory, approvalContract: 2};
      }
      if (path.startsWith('burimunsi/provisioning?')) return provisioning;
      if (path === 'burimunsi/operators' && options.method === 'POST') {
        const command = options.body!;
        expect(command).toMatchObject({principalId: staffPrincipal, collectionId, expectedVersion: 1, active: false});
        expect(options.idempotencyKey).toBe(command.requestId);
        expect(command).not.toHaveProperty('sharedRole');
        receipt = {...operatorReceipt, requestId: command.requestId, active: false, version: 2};
        throw new Error('Synthetic lost acknowledgement');
      }
      if (path.startsWith('burimunsi/operators/requests/')) {
        expect(path.split('?')[0].split('/').at(-1)).toBe(receipt?.requestId);
        return {contractVersion: 1, collectionId, found: true, receipt};
      }
      throw new Error(`Unexpected ${path}`);
    });
    try {
      setup({request});
      const user = userEvent.setup();
      render(<BuriMunsiPage operatorApprovalEnabled />);
      await user.click(screen.getByRole('button', {name: 'Check verification and load groups'}));
      await user.click(await screen.findByRole('button', {name: 'Load group access'}));
      await user.selectOptions(await screen.findByRole('combobox', {name: 'Collect account'}), staffPrincipal);
      await user.selectOptions(screen.getByRole('combobox', {name: 'Access status'}), 'disabled');
      await user.click(screen.getByRole('button', {name: 'Review access'}));
      expect(request.mock.calls.filter(([, options]) => options?.method === 'POST')).toHaveLength(0);
      await user.click(screen.getByRole('button', {name: 'Confirm operator approval'}));
      expect(await screen.findByText(/The approval is unconfirmed/)).toBeVisible();
      const originalTab = sessionStorage.getItem(PENDING_KEY)!;
      expect(originalTab).toContain(String(receipt!.requestId));
      sessionStorage.removeItem(PENDING_KEY);
      await user.click(screen.getByRole('button', {name: 'Check saved approval'}));
      expect(await screen.findByText(/Operator access was recorded/)).toBeVisible();
      sessionStorage.setItem(PENDING_KEY, originalTab);
      await user.click(screen.getByRole('button', {name: 'Refresh prepared groups'}));
      expect(await screen.findByRole('heading', {name: 'Original approval request'})).toBeVisible();
      await user.click(screen.getByRole('button', {name: 'Load group access'}));
      const savedVersion = receipt!.version;
      receipt!.version = 3;
      await user.click(await screen.findByRole('button', {name: 'Check saved approval'}));
      expect(await screen.findByText(/The approval is unconfirmed/)).toBeVisible();
      expect((await readPending(identity, GUARDED_OPERATOR_FAMILY, `${collectionId}:${staffPrincipal}`))?.request_key).toBe(receipt!.requestId);
      receipt!.version = savedVersion;
      await user.click(screen.getByRole('button', {name: 'Check saved approval'}));
      expect(await screen.findByText(/Operator access was recorded/)).toBeVisible();
      expect(screen.queryByRole('heading', {name: 'Original approval request'})).not.toBeInTheDocument();
      expect(await readPending(identity, GUARDED_OPERATOR_FAMILY, `${collectionId}:${staffPrincipal}`)).toBeNull();
      expect(request.mock.calls.filter(([, options]) => options?.method === 'POST')).toHaveLength(1);
    } finally {Reflect.deleteProperty(navigator, 'locks');}
  });
  it('exposes PIN setup and revocation only when the scoped backend negotiates the guarded contract', async () => {
    let guarded = false;
    const request = vi.fn<SessionContextValue['request']>(async path => {
      if (path === 'momo/native-setup') return scopes;
      if (path.startsWith('burimunsi/operators?')) return directory;
      if (path.startsWith('burimunsi/provisioning?')) {
        expect(new URLSearchParams(path.split('?')[1]).get('provisioningContract')).toBe('2');
        return guarded ? {...provisioning, provisioningContract: 2} : provisioning;
      }
      throw new Error(`Unexpected ${path}`);
    });
    setup({request});
    const user = userEvent.setup();
    render(<BuriMunsiPage nativeAdministrationEnabled />);
    await user.click(screen.getByRole('button', {name: 'Check verification and load groups'}));
    await user.click(await screen.findByRole('button', {name: 'Load group access'}));
    await screen.findByRole('heading', {name: 'Native app access'});
    expect(screen.queryByRole('button', {name: 'Review PIN setup'})).not.toBeInTheDocument();
    guarded = true;
    await user.click(screen.getByRole('button', {name: 'Load group access'}));
    expect(await screen.findByRole('button', {name: 'Review PIN setup'})).toBeVisible();
    expect(screen.getByRole('button', {name: 'Review installation revocation'})).toBeVisible();
    expect(screen.queryByRole('button', {name: 'Open protected delivery'})).not.toBeInTheDocument();
  });
  it('keeps native revocation off by default and submits only after an explicit gated review', async () => {
    Object.defineProperty(navigator, 'locks', {configurable: true, value: {request: async (_name: string, _options: unknown, work: (lock: object) => Promise<unknown>) => work({})}});
    let receipt: Record<string, unknown> | null = null, guarded = true;
    const request = vi.fn<SessionContextValue['request']>(async (path, options = {}) => {
      if (path === 'momo/native-setup') return scopes;
      if (path.startsWith('burimunsi/operators?')) return directory;
      if (path.startsWith('burimunsi/provisioning?') && options.method !== 'POST') {
        return guarded && new URLSearchParams(path.split('?')[1]).get('provisioningContract') === '2' ? {...provisioning, provisioningContract: 2} : provisioning;
      }
      if (path === 'burimunsi/provisioning?provisioningContract=2' && options.method === 'POST') {
        const body = options.body!; expect(options.idempotencyKey).toBe(body.requestId); expect(body.operation).toBe('revoke_installation');
        receipt = {contractVersion: 1, collectionId, requestId: body.requestId, operation: body.operation, principalId: body.principalId, accountId: body.accountId, accountVersion: body.expectedAccountVersion,
          credentialVersion: 1, approvalVersion: body.approvalVersion, scopeVersion: body.scopeVersion, applied: true, grantId: body.grantId, installationId: body.installationId, profile: body.profile,
          grantVersion: Number(body.expectedGrantVersion) + 1, active: false, deliveryExpiresAt: null}; return receipt;
      }
      if (path.startsWith('burimunsi/provisioning/requests/')) return {contractVersion: 1, collectionId, requestId: receipt?.requestId, found: true, receipt};
      throw new Error(`Unexpected ${path}`);
    });
    setup({request}); const user = userEvent.setup(), page = render(<BuriMunsiPage />);
    await user.click(screen.getByRole('button', {name: 'Check verification and load groups'})); await user.click(await screen.findByRole('button', {name: 'Load group access'}));
    expect(await screen.findByRole('button', {name: 'Check native revocation request'})).toBeVisible();
    expect(screen.queryByRole('button', {name: 'Review installation revocation'})).not.toBeInTheDocument();
    page.rerender(<BuriMunsiPage nativeRevocationEnabled />);
    expect(screen.queryByRole('button', {name: 'Review installation revocation'})).not.toBeInTheDocument();
    await user.click(screen.getByRole('button', {name: 'Load group access'}));
    await user.selectOptions(await screen.findByRole('combobox', {name: 'Active installation'}), grantId);
    await user.click(screen.getByRole('button', {name: 'Review installation revocation'}));
    expect(await screen.findByRole('region', {name: 'Revocation review'})).toBeVisible();
    expect(request.mock.calls.filter(([, options]) => options?.method === 'POST')).toHaveLength(0);
    guarded = false;
    await user.click(screen.getByRole('button', {name: 'Confirm installation revocation'}));
    expect(await screen.findByText(/Guarded native access is unavailable/)).toBeVisible();
    expect(request.mock.calls.filter(([, options]) => options?.method === 'POST')).toHaveLength(0);
    guarded = true;
    await user.click(screen.getByRole('button', {name: 'Review installation revocation'}));
    await screen.findByRole('region', {name: 'Revocation review'});
    await user.click(screen.getByRole('button', {name: 'Confirm installation revocation'}));
    expect(await screen.findByText(/original installation revocation was recorded/)).toBeVisible();
    expect(request.mock.calls.filter(([, options]) => options?.method === 'POST')).toHaveLength(1);
    const body = request.mock.calls.find(([, options]) => options?.method === 'POST')?.[1]?.body;
    expect(Object.keys(body!)).not.toContain('pin'); expect(Object.keys(body!)).not.toContain('installationToken');
    Reflect.deleteProperty(navigator, 'locks');
  });
  it('hides previously loaded sensitive records when fresh proof expires', async () => {
    const session = setup(), user = userEvent.setup(), page = render(<BuriMunsiPage />);
    await user.click(screen.getByRole('button', {name: 'Check verification and load groups'})); await user.click(await screen.findByRole('button', {name: 'Load group access'}));
    expect(await screen.findByRole('row', {name: /staff@example.test/})).toBeVisible(); fresh = false; hook.value = {...session}; page.rerender(<BuriMunsiPage />);
    expect(screen.queryByRole('row', {name: /staff@example.test/})).not.toBeInTheDocument(); expect(screen.getByText(/Verify your current owner email/)).toBeVisible();
  });
  it('does not redisplay earlier group records after a new email verification', async () => {
    const session = setup(), user = userEvent.setup(), page = render(<BuriMunsiPage />);
    await user.click(screen.getByRole('button', {name: 'Check verification and load groups'})); await user.click(await screen.findByRole('button', {name: 'Load group access'}));
    expect(await screen.findByRole('row', {name: /staff@example.test/})).toBeVisible();
    fresh = false; hook.value = {...session}; page.rerender(<BuriMunsiPage />);
    fresh = true; hook.value = {...session, user: {...owner, emailVerifiedAt: new Date(Date.parse(owner.emailVerifiedAt!) + 1000).toISOString()}}; page.rerender(<BuriMunsiPage />);
    expect(screen.queryByRole('row', {name: /staff@example.test/})).not.toBeInTheDocument(); expect(screen.getByRole('button', {name: 'Check verification and load groups'})).toBeVisible();
  });
  it.each([
    ['session expiry', 45_000, 100_000, 45_001],
    ['authenticator proof expiry', 200_000, 100_000, 100_001],
  ])('schedules masking at the earlier %s', (_label, expiry, mfaRemaining, expectedDelay) => {
    const now = Date.now(), clock = vi.spyOn(Date, 'now').mockReturnValue(now), spy = vi.spyOn(window, 'setTimeout');
    try {
      setup({user: {...owner, expiresAt: new Date(now + expiry).toISOString(), emailVerifiedAt: new Date(now - 1000).toISOString(), assuranceLevel: 2, mfaRequired: true, mfaAt: new Date(now - 300_000 + mfaRemaining).toISOString()}});
      const page = render(<BuriMunsiPage />);
      expect(spy.mock.calls.some(([, delay]) => delay === expectedDelay)).toBe(true); page.unmount();
    } finally {spy.mockRestore(); clock.mockRestore();}
  });
  it('discards a response if the owner session changes during the read', async () => {
    let resolve: ((value: typeof scopes) => void) | undefined;
    const request = vi.fn(async () => new Promise<typeof scopes>(done => {resolve = done;})), session = setup({request}), user = userEvent.setup(), page = render(<BuriMunsiPage />);
    await user.click(screen.getByRole('button', {name: 'Check verification and load groups'})); expect(resolve).toBeDefined(); current = false;
    hook.value = {...session, epoch: 8, user: {...owner, ownerIdentity: null}}; page.rerender(<BuriMunsiPage />);
    await act(async () => {resolve!(scopes);}); expect(screen.queryByText('Synthetic savings')).not.toBeInTheDocument(); expect(screen.getByText(/protected owner identity bound to this session/)).toBeVisible();
  });
  it('settles only the same-realm predecessor approval confirmed by its original request', async () => {
    await retainPending(identity, 'burimunsi.operator', `${collectionId}:${staffPrincipal}`, requestId, 'admin_users.manage', operatorIntent);
    const other = 'another-group';
    await retainPending(identity, 'burimunsi.operator', `${other}:${staffPrincipal}`, grantId, 'admin_users.manage', {...operatorIntent, collectionId: other, requestId: grantId});
    const request = vi.fn<SessionContextValue['request']>(async (path: string) => {
      if (path === 'momo/native-setup') return scopes;
      if (path.startsWith('burimunsi/operators/requests/')) return {contractVersion: 1, collectionId, found: true, receipt: operatorReceipt};
      if (path.startsWith('burimunsi/operators?')) return directory;
      if (path.startsWith('burimunsi/provisioning?')) return provisioning;
      throw new Error(`Unexpected ${path}`);
    });
    setup({request}); const user = userEvent.setup(); render(<BuriMunsiPage operatorPreparationEnabled />);
    await user.click(screen.getByRole('button', {name: 'Check verification and load groups'})); expect(await screen.findByText(requestId)).toBeVisible();
    await user.click(screen.getByRole('button', {name: 'Load group access'}));
    expect(await screen.findByRole('combobox', {name: 'Collect account'})).toBeDisabled();
    await user.click(screen.getByRole('button', {name: 'Check original request'})); expect(await screen.findByText(/original operator approval was recorded/i)).toBeVisible();
    expect(await readPending(identity, 'burimunsi.operator', `${collectionId}:${staffPrincipal}`)).toBeNull();
    expect((await readPending(identity, 'burimunsi.operator', `${other}:${staffPrincipal}`))?.request_key).toBe(grantId);
    expect(screen.getByRole('combobox', {name: 'Collect account'})).toBeEnabled();
    expect(request.mock.calls.filter(([path]) => path.includes('/requests/')).map(([path]) => path))
      .toEqual([`burimunsi/operators/requests/${requestId}?collectionId=${collectionId}`]);
    expect(request.mock.calls.every(([, options]) => !options?.method)).toBe(true);
  });
  it.each(['missing', 'principal', 'revision', 'collection', 'request', 'changed tab', 'changed actor'])('preserves the original approval when verification fails: %s', async (mismatch) => {
    const resource = `${collectionId}:${staffPrincipal}`;
    await retainPending(identity, 'burimunsi.operator', resource, requestId, 'admin_users.manage', operatorIntent);
    const original = sessionStorage.getItem(PENDING_KEY)!;
    const updated = original.replace(operatorIntent.phone, '+250780000003');
    const request = vi.fn<SessionContextValue['request']>(async path => {
      if (path === 'momo/native-setup') return scopes;
      if (path !== `burimunsi/operators/requests/${requestId}?collectionId=${collectionId}`) throw Error('Unexpected request');
      if (mismatch === 'changed tab') sessionStorage.setItem(PENDING_KEY, updated);
      if (mismatch === 'changed actor') current = false;
      if (mismatch === 'missing') return {contractVersion: 1, collectionId, found: false};
      return {contractVersion: 1, collectionId: mismatch === 'collection' ? 'another-group' : collectionId, found: true,
        receipt: {...operatorReceipt, principalId: mismatch === 'principal' ? owner.principalId : staffPrincipal, requestId: mismatch === 'request' ? grantId : requestId, version: mismatch === 'revision' ? 2 : 1}};
    });
    setup({request}); const user = userEvent.setup(); render(<BuriMunsiPage />);
    await user.click(screen.getByRole('button', {name: 'Check verification and load groups'}));
    await user.click(await screen.findByRole('button', {name: 'Check original request'}));
    expect(sessionStorage.getItem(PENDING_KEY)).toBe(mismatch === 'changed tab' ? updated : original);
    expect(request.mock.calls).toHaveLength(2);
    expect(request.mock.calls.every(([, options]) => !options?.method)).toBe(true);
  });
  it('blocks preparation while the group has a retained Flutter request', async () => {
    await retainPending(identity, 'burimunsi.operator', `${collectionId}:${staffPrincipal}`, requestId, 'admin_users.manage', operatorIntent);
    setup(); const user = userEvent.setup(); render(<BuriMunsiPage operatorPreparationEnabled />);
    await user.click(screen.getByRole('button', {name: 'Check verification and load groups'})); await user.click(await screen.findByRole('button', {name: 'Load group access'}));
    expect(await screen.findByText(/Check the original group request before preparing another change/)).toBeVisible();
    expect(screen.getByRole('combobox', {name: 'Collect account'})).toBeDisabled();
    expect((await readPending(identity, 'burimunsi.operator', `${collectionId}:${staffPrincipal}`))?.request_key).toBe(requestId);
  });
  it('retains the original reference visibly when its group is unavailable', async () => {
    const unavailable = 'unavailable-group', intent = {...operatorIntent, collectionId: unavailable};
    await retainPending(identity, 'burimunsi.operator', `${unavailable}:${staffPrincipal}`, requestId, 'admin_users.manage', intent);
    setup(); const user = userEvent.setup(); render(<BuriMunsiPage />);
    await user.click(screen.getByRole('button', {name: 'Check verification and load groups'}));
    expect(await screen.findByText(requestId)).toBeVisible(); expect(screen.getByText(unavailable)).toBeVisible();
    expect(screen.queryByRole('button', {name: 'Check original request'})).not.toBeInTheDocument();
    expect((await readPending(identity, 'burimunsi.operator', `${unavailable}:${staffPrincipal}`))?.request_key).toBe(requestId);
  });
  it('clears a confirmed PIN setup checkpoint without reading a PIN or opening protected delivery', async () => {
    await retainPending(identity, 'burimunsi.provisioning', `${collectionId}:${staffPrincipal}`, requestId, 'admin_users.manage', nativeIntent);
    const request = vi.fn(async (path: string) => {
      if (path === 'momo/native-setup') return scopes;
      if (path.startsWith('burimunsi/provisioning/requests/')) return {contractVersion: 1, collectionId, requestId, found: true, receipt: nativeReceipt};
      throw new Error(`Unexpected ${path}`);
    });
    setup({request}); const user = userEvent.setup(); render(<BuriMunsiPage />);
    await user.click(screen.getByRole('button', {name: 'Check verification and load groups'})); await user.click(await screen.findByRole('button', {name: 'Check original request'}));
    expect(await screen.findByText(/original PIN setup was recorded/)).toBeVisible(); expect(request.mock.calls.every(([path]) => !path.includes('/delivery'))).toBe(true);
    expect(await readPending(identity, 'burimunsi.provisioning', `${collectionId}:${staffPrincipal}`)).toBeNull();
  });
  it('closes the local record for a reviewed grant while protected token delivery is unavailable', async () => {
    Object.defineProperty(navigator, 'locks', {configurable: true, value: {request: async (_name: string, _options: unknown, work: (lock: object) => Promise<unknown>) => work({})}});
    const intent = {...nativeIntent, operation: 'grant_installation', reason: 'Owner approved managed installation', expectedAccountVersion: 1, accountId, grantId, installationId, profile: 'staff', expectedGrantVersion: 1};
    const receipt = {...nativeReceipt, operation: 'grant_installation', accountVersion: 1, grantId, installationId, profile: 'staff', grantVersion: 2, active: true, deliveryExpiresAt: Date.now() + 120_000};
    await retainPending(identity, 'burimunsi.provisioning', `${collectionId}:${staffPrincipal}`, requestId, 'admin_users.manage', intent);
    const request = vi.fn<SessionContextValue['request']>(async path => {
      if (path === 'momo/native-setup') return scopes;
      if (path.startsWith('burimunsi/operators?')) return directory;
      if (path.startsWith('burimunsi/provisioning?')) return {...provisioning, provisioningContract: 2};
      if (path.startsWith(`burimunsi/provisioning/requests/${requestId}?`)) return {contractVersion: 1, collectionId, requestId, found: true, receipt};
      throw new Error(`Unexpected ${path}`);
    });
    try {
      setup({request});
      const user = userEvent.setup(); render(<BuriMunsiPage nativeAdministrationEnabled />);
      await user.click(screen.getByRole('button', {name: 'Check verification and load groups'}));
      await user.click(await screen.findByRole('button', {name: 'Load group access'}));
      await user.click(await screen.findByRole('button', {name: 'Check native setup request'}));
      const close = await screen.findByRole('button', {name: 'Close local delivery record'});
      expect(screen.queryByRole('button', {name: 'Open protected delivery'})).not.toBeInTheDocument();
      await user.click(close);
      expect(await screen.findByText(/The local delivery record was closed/)).toBeVisible();
      expect(await readPending(identity, 'burimunsi.provisioning', `${collectionId}:${staffPrincipal}`)).toBeNull();
      expect(request.mock.calls.every(([path, options]) => !path.endsWith('/delivery') && (!options?.method || options.method === 'GET'))).toBe(true);
    } finally {Reflect.deleteProperty(navigator, 'locks');}
  });
  it('releases only a same-tab revocation checkpoint after its exact terminal receipt', async () => {
    const intent = {...nativeIntent, operation: 'revoke_installation', expectedAccountVersion: 1, accountId, grantId, installationId, profile: 'staff', expectedGrantVersion: 1};
    const receipt = {...nativeReceipt, operation: 'revoke_installation', accountVersion: 1, grantId, installationId, profile: 'staff', grantVersion: 2, active: false, deliveryExpiresAt: null};
    await retainPending(identity, 'burimunsi.provisioning', `${collectionId}:${staffPrincipal}`, requestId, 'admin_users.manage', intent);
    const request = vi.fn<SessionContextValue['request']>(async path => {
      if (path === 'momo/native-setup') return scopes;
      if (path.startsWith('burimunsi/provisioning/requests/')) return {contractVersion: 1, collectionId, requestId, found: true, receipt};
      throw new Error(`Unexpected ${path}`);
    });
    setup({request}); const user = userEvent.setup(); render(<BuriMunsiPage />);
    await user.click(screen.getByRole('button', {name: 'Check verification and load groups'})); await user.click(await screen.findByRole('button', {name: 'Check original request'}));
    expect(await screen.findByText(/original installation revocation was recorded/)).toBeVisible();
    expect(await readPending(identity, 'burimunsi.provisioning', `${collectionId}:${staffPrincipal}`)).toBeNull();
    expect(request.mock.calls.every(([, options]) => !options?.method || options.method === 'GET')).toBe(true);
  });
});
