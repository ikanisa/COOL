import {webcrypto} from 'node:crypto';
import {act, render, screen, waitFor} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import {beforeEach, describe, expect, it, vi} from 'vitest';
import type {AdminRequest} from '../../src/api/client';
import {parseBuriProvisioning} from '../../src/features/burimunsi/contracts';
import {NativeProvisioningPanel} from '../../src/features/burimunsi/NativeProvisioningPanel';
import type {NativeProvisionContext} from '../../src/features/burimunsi/nativeProvisioning';
import {accountId, collectionId, grantId, installationId, owner, provisioning, requestId, sessionId, staffPrincipal} from './fixture';

function storage(): Storage {
  const values = new Map<string, string>();
  return {get length() {return values.size;}, clear() {values.clear();}, getItem(key) {return values.get(key) ?? null;}, key(index) {return [...values.keys()][index] ?? null;}, removeItem(key) {values.delete(key);}, setItem(key, value) {values.set(key, String(value));}};
}
function fixture() {
  const tab = storage(), shared = storage(), pin = String(1000 + webcrypto.getRandomValues(new Uint16Array(1))[0] % 9000);
  const token = Array.from(webcrypto.getRandomValues(new Uint8Array(32)), byte => byte.toString(16).padStart(2, '0')).join('');
  let receipt: Record<string, unknown> | null = null, requestCount = 0, pinMatched = false, retainedSecret = false, delayDelivery = false;
  let completeDelivery: ((value: Record<string, unknown>) => void) | null = null, deliverySignal: AbortSignal | undefined, lastDelivery: Record<string, unknown> | null = null;
  const request: AdminRequest = async (path, options = {}) => {
    if (path.startsWith('burimunsi/provisioning?') && options.method !== 'POST') return {...provisioning, provisioningContract: 2};
    if (path === 'burimunsi/provisioning?provisioningContract=2' && options.method === 'POST') {
      requestCount++; const body = options.body!, isPin = body.operation === 'set_pin';
      pinMatched = !isPin || body.pin === pin;
      const saved = [...Array(tab.length)].map((_, i) => JSON.parse(tab.getItem(tab.key(i)!)!)).concat([...Array(shared.length)].map((_, i) => JSON.parse(shared.getItem(shared.key(i)!)!)));
      const contains = (value: unknown): boolean => value === pin || value === token || !!value && typeof value === 'object' && Object.values(value).some(contains);
      retainedSecret = saved.some(contains);
      receipt = {contractVersion: 1, collectionId, requestId, operation: body.operation, principalId: body.principalId, accountId, accountVersion: Number(body.expectedAccountVersion) + (isPin ? 1 : 0),
        credentialVersion: 1, approvalVersion: body.approvalVersion, scopeVersion: body.scopeVersion, applied: true,
        ...(isPin ? {} : {grantId, installationId, profile: 'staff', grantVersion: 2, active: true, deliveryExpiresAt: Date.now() + 120_000})};
      return {...receipt};
    }
    if (path.includes(`/requests/${requestId}/delivery`) && options.method === 'POST') {
      deliverySignal = options.signal; const output = {contractVersion: 1, collectionId, requestId, installationId, profile: 'staff', grantVersion: 2, expiresAt: receipt!.deliveryExpiresAt, installationToken: token};
      lastDelivery = output; if (delayDelivery) return new Promise(resolve => {completeDelivery = resolve;}); return output;
    }
    if (path.startsWith(`burimunsi/provisioning/requests/${requestId}?`)) return receipt ? {contractVersion: 1, collectionId, requestId, found: true, receipt: {...receipt}} : {contractVersion: 1, collectionId, requestId, found: false};
    throw new Error('Unexpected synthetic request.');
  };
  const identity = {id: owner.id, sessionId, email: owner.email, role: owner.role, permissions: owner.permissions, expiresAt: owner.expiresAt};
  const context: NativeProvisionContext = {request, user: {...owner}, identity, collectionId, enabled: true, isCurrent: () => true, isVisible: () => true,
    verifyFresh: async () => true, storage: tab, sharedStorage: shared, lock: async (_name, fn) => fn(), createKey: () => requestId};
  return {context, pin, token, onResolved: vi.fn(), setDelay(value: boolean) {delayDelivery = value;},
    releaseDelivery() {if (completeDelivery && lastDelivery) completeDelivery(lastDelivery);},
    state: () => ({requestCount, pinMatched, retainedSecret, deliveryStarted: !!deliverySignal, deliveryAborted: deliverySignal?.aborted ?? false, secretCleared: !lastDelivery || !Object.hasOwn(lastDelivery, 'installationToken')})};
}
beforeEach(() => {Object.defineProperty(globalThis, 'crypto', {value: webcrypto, configurable: true});});

describe('native setup secret lifecycle', () => {
  it('clears entered PIN fields when the window loses focus, without submitting', async () => {
    const f = fixture(), user = userEvent.setup(); render(<NativeProvisioningPanel pinContext={f.context} grantContext={{...f.context, enabled: false}} directory={parseBuriProvisioning(provisioning, collectionId)} onResolved={f.onResolved} />);
    await user.selectOptions(screen.getByRole('combobox', {name: 'Approved native account'}), staffPrincipal); await user.click(screen.getByRole('button', {name: 'Review PIN setup'}));
    const first = await screen.findByLabelText('Four-digit PIN') as HTMLInputElement, second = screen.getByLabelText('Confirm PIN') as HTMLInputElement;
    await user.type(first, f.pin); await user.type(second, f.pin); expect(first.value.length).toBe(4);
    act(() => window.dispatchEvent(new Event('blur'))); expect(first.value).toBe(''); expect(second.value).toBe('');
    expect(screen.queryByLabelText('Four-digit PIN')).not.toBeInTheDocument(); expect(f.state().requestCount).toBe(0);
  });
  it('submits a matching PIN from uncontrolled fields without retaining it', async () => {
    const f = fixture(), user = userEvent.setup(); render(<NativeProvisioningPanel pinContext={f.context} grantContext={{...f.context, enabled: false}} directory={parseBuriProvisioning(provisioning, collectionId)} onResolved={f.onResolved} />);
    await user.selectOptions(screen.getByRole('combobox', {name: 'Approved native account'}), staffPrincipal); await user.click(screen.getByRole('button', {name: 'Review PIN setup'}));
    const first = await screen.findByLabelText('Four-digit PIN') as HTMLInputElement, second = screen.getByLabelText('Confirm PIN') as HTMLInputElement;
    await user.type(first, f.pin); await user.type(second, f.pin); await user.click(screen.getByRole('button', {name: 'Confirm PIN setup'}));
    await waitFor(() => expect(f.onResolved).toHaveBeenCalledWith('recorded'));
    expect(first.value).toBe(''); expect(second.value).toBe(''); expect(f.state().pinMatched).toBe(true); expect(f.state().retainedSecret).toBe(false);
  });
  it('does not expose grant creation or token delivery even when the optional gate is on', () => {
    const f = fixture(); render(<NativeProvisioningPanel pinContext={{...f.context, enabled: false}} grantContext={f.context} directory={parseBuriProvisioning(provisioning, collectionId)} onResolved={f.onResolved} />);
    expect(screen.getByText(/Protected installation delivery is unavailable/)).toBeVisible();
    expect(screen.queryByRole('button', {name: 'Review installation grant'})).not.toBeInTheDocument();
    expect(screen.queryByRole('button', {name: 'Open protected delivery'})).not.toBeInTheDocument(); expect(f.state().requestCount).toBe(0);
  });
});
