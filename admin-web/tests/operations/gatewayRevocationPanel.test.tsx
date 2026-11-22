import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { retainPending } from '../../src/features/core/pendingAttempt';
import { parseGatewayPage, type GatewayDevice } from '../../src/features/operations/contracts';

const mock = vi.hoisted(() => ({request: vi.fn(), user: {id: '22222222-2222-4222-8222-222222222222', sessionId: 'session-1', email: 'admin@example.com', role: 'admin' as const, permissions: ['gateway.read', 'gateway.manage', 'overview.read'], expiresAt: new Date(Date.now() + 3600000).toISOString(), financialModel: 'transaction_journals' as const}}));
vi.mock('../../src/session/SessionProvider', () => ({useSession: () => ({user: mock.user, epoch: 1, status: 'authenticated', request: mock.request})}));
import { GatewayTrustPanel } from '../../src/features/operations/GatewayTrustPanel';

const actor = mock.user.id, installation = '33333333-3333-4333-8333-333333333333', key = '44444444-4444-4444-8444-444444444444', operation = '55555555-5555-4555-8555-555555555555', deviceId = '66666666-6666-4666-8666-666666666666';
const time = '2026-11-16T08:00:00.000Z', originalLocks = Object.getOwnPropertyDescriptor(navigator, 'locks');
let device: GatewayDevice, current: Record<string, unknown>, revoked: Record<string, unknown>;
const receipt = {request_id: operation, resource_type: 'gateway_devices', resource_id: deviceId, version: 2, status: 'succeeded'};
beforeAll(async () => {
  const pair = await crypto.subtle.generateKey({name: 'ECDSA', namedCurve: 'P-256'}, true, ['sign', 'verify']);
  const bytes = new Uint8Array(await crypto.subtle.exportKey('spki', pair.publicKey));
  const publicKey = btoa(String.fromCharCode(...bytes));
  const fingerprint = [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))].map((value) => value.toString(16).padStart(2, '0')).join('');
  const base = {id: deviceId, label: 'Receiver handset', app_id: 'app.collect.gateway', installation_id: installation, key_sha256: fingerprint, signing_certificate_sha256: 'b'.repeat(64), state: 'pending', version: 1, created_at: time, activated_at: null, revoked_at: null, last_heartbeat_at: null, carrier_proof: false, send_authority: false};
  device = parseGatewayPage({rows: [base], total: 1}, 0).rows[0];
  const detail = (resource: Record<string, unknown>) => ({resource_type: 'gateway_devices', resource: {...resource, public_key_spki_base64: publicKey}, current_actor_id: actor, can_manage: true, related_truncated: false, related: {heartbeats: []}, enrollment: {contract_version: 1, device_id: deviceId, installation_id: installation, key_sha256: fingerprint, signing_certificate_sha256: 'b'.repeat(64)}});
  current = detail(base); revoked = detail({...base, state: 'revoked', version: 2, revoked_at: time});
});
beforeEach(() => {sessionStorage.clear(); localStorage.clear(); Object.defineProperty(navigator, 'locks', {configurable: true, value: {request: async (name: string, _options: unknown, work: (lock: {name: string}) => Promise<unknown>) => work({name})}});});
afterEach(() => {mock.request.mockReset(); if (originalLocks) Object.defineProperty(navigator, 'locks', originalLocks); else Reflect.deleteProperty(navigator, 'locks');});

describe('Gateway revocation panel', () => {
  it('does not offer revocation while disabled', async () => {
    render(<GatewayTrustPanel mode="revoke" device={device} canManage onUpdated={() => {}} />);
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(screen.queryByRole('button', {name: 'Review device revocation'})).not.toBeInTheDocument();
    expect(mock.request).not.toHaveBeenCalled();
  });
  it('requires a reason and fingerprint comparison before revocation', async () => {
    const user = userEvent.setup(), updated = vi.fn();
    mock.request.mockResolvedValueOnce(receipt).mockResolvedValueOnce(revoked);
    render(<GatewayTrustPanel mode="revoke" device={device} canManage enabled onUpdated={updated} />);
    await user.type(await screen.findByLabelText('Reason for device change'), 'Review device identity');
    await user.click(screen.getByRole('button', {name: 'Review device revocation'}));
    expect(screen.getByRole('button', {name: 'Confirm device revocation'})).toBeDisabled();
    expect(screen.getByText(device.key_sha256)).toBeVisible();
    expect(mock.request).not.toHaveBeenCalled();
    await user.click(screen.getByRole('checkbox', {name: 'I compared the installation and both fingerprints with the device.'}));
    await user.click(screen.getByRole('button', {name: 'Confirm device revocation'}));
    expect(await screen.findByText(`Device revocation recorded. Request ${operation}.`)).toBeVisible();
    expect(mock.request).toHaveBeenCalledTimes(2);
    expect(updated).toHaveBeenCalledTimes(1);
    expect(screen.queryByRole('button', {name: 'Review device revocation'})).not.toBeInTheDocument();
  });
  it('recovers the original reference with writes disabled', async () => {
    const user = userEvent.setup();
    await retainPending(mock.user, 'gateway-device-revoke', deviceId, key, 'gateway.manage', {expected_version: 1, expected_key_sha256: device.key_sha256, expected_signing_certificate_sha256: device.signing_certificate_sha256, reason: 'Review device identity'});
    mock.request.mockResolvedValueOnce({status: 'not_found'});
    render(<GatewayTrustPanel mode="revoke" device={device} canManage onUpdated={() => {}} />);
    await user.click(await screen.findByRole('button', {name: 'Check original request'}));
    expect(await screen.findByText('No receipt was found. Keep the original reference and check again before continuing.')).toBeVisible();
    expect(screen.queryByRole('button', {name: 'Review identical retry'})).not.toBeInTheDocument();
    expect(mock.request).toHaveBeenCalledWith(`operations/requests/${key}`);
  });
  it('requires a fresh review before retrying the same request', async () => {
    const user = userEvent.setup();
    const intent = {expected_version: 1, expected_key_sha256: device.key_sha256, expected_signing_certificate_sha256: device.signing_certificate_sha256, reason: 'Review device identity'};
    await retainPending(mock.user, 'gateway-device-revoke', deviceId, key, 'gateway.manage', intent);
    mock.request.mockResolvedValueOnce({status: 'not_found'}).mockResolvedValueOnce({status: 'not_found'}).mockResolvedValueOnce(current).mockResolvedValueOnce(receipt).mockResolvedValueOnce(revoked);
    render(<GatewayTrustPanel mode="revoke" device={device} canManage enabled onUpdated={() => {}} />);
    await user.click(await screen.findByRole('button', {name: 'Check original request'}));
    await user.click(await screen.findByRole('button', {name: 'Review identical retry'}));
    expect(screen.getByRole('button', {name: 'Confirm identical retry'})).toBeDisabled();
    expect(mock.request).toHaveBeenCalledTimes(1);
    await user.click(screen.getByRole('checkbox', {name: 'I compared the installation and both fingerprints with the device.'}));
    await user.click(screen.getByRole('button', {name: 'Confirm identical retry'}));
    expect(await screen.findByText(`Device revocation recorded. Request ${operation}.`)).toBeVisible();
    expect(mock.request).toHaveBeenNthCalledWith(4, `gateway/devices/${deviceId}/revoke`, {method: 'POST', body: intent, idempotencyKey: key});
  });
});
