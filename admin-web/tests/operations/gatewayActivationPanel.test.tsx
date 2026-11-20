import {render, screen} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import {afterEach, beforeAll, beforeEach, describe, expect, it, vi} from 'vitest';
import {retainPending} from '../../src/features/core';
import {parseGatewayPage, type GatewayDevice} from '../../src/features/operations/contracts';

const mock = vi.hoisted(() => ({request: vi.fn(), user: {id: '22222222-2222-4222-8222-222222222222', sessionId: 'session-1', email: 'admin@example.test', role: 'admin' as const, permissions: ['gateway.read', 'gateway.manage', 'overview.read'], expiresAt: new Date(Date.now() + 3600000).toISOString(), financialModel: 'transaction_journals' as const}}));
vi.mock('../../src/session/SessionProvider', () => ({useSession: () => ({user: mock.user, epoch: 1, status: 'authenticated', request: mock.request, isCurrentAuthority: () => true})}));
import {GatewayActivationPanel} from '../../src/features/operations/GatewayActivationPanel';

const installation = '33333333-3333-4333-8333-333333333333', key = '44444444-4444-4444-8444-444444444444', operation = '55555555-5555-4555-8555-555555555555', deviceId = '66666666-6666-4666-8666-666666666666';
const time = '2026-11-16T08:00:00.000Z', originalLocks = Object.getOwnPropertyDescriptor(navigator, 'locks');
const receipt = {request_id: operation, resource_type: 'gateway_devices', resource_id: deviceId, version: 2, status: 'succeeded'};
let device: GatewayDevice, current: Record<string, unknown>, active: Record<string, unknown>;
beforeAll(async () => {
  const pair = await crypto.subtle.generateKey({name: 'ECDSA', namedCurve: 'P-256'}, true, ['sign', 'verify']);
  const bytes = new Uint8Array(await crypto.subtle.exportKey('spki', pair.publicKey)), encoded = btoa(String.fromCharCode(...bytes));
  const fingerprint = [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))].map((value) => value.toString(16).padStart(2, '0')).join('');
  const base = {id: deviceId, label: 'Synthetic handset', app_id: 'app.collect.gateway', installation_id: installation, key_sha256: fingerprint, signing_certificate_sha256: 'b'.repeat(64), state: 'pending', version: 1, created_at: time, activated_at: null, revoked_at: null, last_heartbeat_at: null, carrier_proof: false, send_authority: false};
  device = parseGatewayPage({rows: [base], total: 1}, 0).rows[0];
  const detail = (resource: Record<string, unknown>) => ({resource_type: 'gateway_devices', resource: {...resource, public_key_spki_base64: encoded}, current_actor_id: mock.user.id, can_manage: true, related_truncated: false, related: {heartbeats: []}, enrollment: {contract_version: 1, device_id: deviceId, installation_id: installation, key_sha256: fingerprint, signing_certificate_sha256: 'b'.repeat(64)}});
  current = detail(base); active = detail({...base, state: 'active', version: 2, activated_at: time});
});
beforeEach(() => {sessionStorage.clear(); localStorage.clear(); Object.defineProperty(navigator, 'locks', {configurable: true, value: {request: async (name: string, _options: unknown, work: (lock: {name: string}) => Promise<unknown>) => work({name})}});});
afterEach(() => {mock.request.mockReset(); if (originalLocks) Object.defineProperty(navigator, 'locks', originalLocks); else Reflect.deleteProperty(navigator, 'locks');});

describe('Gateway activation panel', () => {
  it('does not offer activation by default', async () => {
    render(<GatewayActivationPanel device={device} canManage onUpdated={() => undefined} />);
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(screen.queryByRole('button', {name: 'Review device activation'})).not.toBeInTheDocument(); expect(mock.request).not.toHaveBeenCalled();
  });
  it('requires fingerprint comparison and explicit confirmation before activating', async () => {
    const user = userEvent.setup(), updated = vi.fn(); mock.request.mockResolvedValueOnce(receipt).mockResolvedValueOnce(active);
    render(<GatewayActivationPanel device={device} canManage enabled onUpdated={updated} />);
    await user.type(await screen.findByLabelText('Reason for activation'), 'Review device identity'); await user.click(screen.getByRole('button', {name: 'Review device activation'}));
    expect(screen.getByRole('button', {name: 'Confirm activation'})).toBeDisabled(); expect(screen.getByText(device.key_sha256)).toBeVisible(); expect(mock.request).not.toHaveBeenCalled();
    await user.click(screen.getByRole('checkbox', {name: 'I compared the installation and both fingerprints with the device.'}));
    await user.click(screen.getByRole('button', {name: 'Confirm activation'}));
    expect(await screen.findByText(`Device activation recorded. Request ${operation}.`)).toBeVisible(); expect(updated).toHaveBeenCalledOnce();
  });
  it('recovers a retained activation with writes off and retries only after the explicit gate opens', async () => {
    const user = userEvent.setup(), intent = {expected_version: 1, expected_key_sha256: device.key_sha256, expected_signing_certificate_sha256: device.signing_certificate_sha256, reason: 'Review device identity'};
    await retainPending(mock.user, 'gateway-device-activate', deviceId, key, 'gateway.manage', intent);
    mock.request.mockResolvedValueOnce({status: 'not_found'}).mockResolvedValueOnce({status: 'not_found'}).mockResolvedValueOnce(current).mockResolvedValueOnce(receipt).mockResolvedValueOnce(active);
    const view = render(<GatewayActivationPanel device={device} canManage onUpdated={() => undefined} />);
    await user.click(await screen.findByRole('button', {name: 'Check original request'}));
    expect(await screen.findByText('No receipt was found. Keep the original reference and check again before continuing.')).toBeVisible();
    expect(screen.queryByRole('button', {name: 'Review identical retry'})).not.toBeInTheDocument();
    view.rerender(<GatewayActivationPanel device={device} canManage enabled onUpdated={() => undefined} />);
    await user.click(await screen.findByRole('button', {name: 'Review identical retry'}));
    expect(screen.getByRole('button', {name: 'Confirm identical retry'})).toBeDisabled();
    await user.click(screen.getByRole('checkbox', {name: 'I compared the installation and both fingerprints with the device.'}));
    await user.click(screen.getByRole('button', {name: 'Confirm identical retry'}));
    expect(await screen.findByText(`Device activation recorded. Request ${operation}.`)).toBeVisible();
    expect(mock.request).toHaveBeenNthCalledWith(4, `gateway/devices/${deviceId}/activate`, {method: 'POST', body: intent, idempotencyKey: key});
  });
});
