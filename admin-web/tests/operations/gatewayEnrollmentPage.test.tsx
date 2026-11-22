import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router';
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { retainPending } from '../../src/features/core/pendingAttempt';
import type { GatewayEnrollmentIntent } from '../../src/features/operations/gatewayEnrollment';
import { withPendingFence } from '../../src/features/operations/pendingFence';

const mock = vi.hoisted(() => ({request: vi.fn(), user: {id: '22222222-2222-4222-8222-222222222222', sessionId: 'session-1', email: 'admin@example.com', role: 'admin' as const, permissions: ['gateway.read', 'gateway.manage', 'overview.read'], expiresAt: new Date(Date.now() + 3600000).toISOString(), financialModel: 'transaction_journals' as const}}));
vi.mock('../../src/session/SessionProvider', () => ({useSession: () => ({user: mock.user, epoch: 1, status: 'authenticated', request: mock.request})}));
import { GatewayEnrollmentPage } from '../../src/features/operations/GatewayEnrollmentPage';

const actor = mock.user.id, installation = '33333333-3333-4333-8333-333333333333', key = '44444444-4444-4444-8444-444444444444', operation = '55555555-5555-4555-8555-555555555555', device = '66666666-6666-4666-8666-666666666666';
const time = '2026-11-16T08:00:00.000Z', originalLocks = Object.getOwnPropertyDescriptor(navigator, 'locks');
let intent: GatewayEnrollmentIntent, publicIdentity: Record<string, unknown>, detail: Record<string, unknown>;
const receipt = {request_id: operation, resource_type: 'gateway_devices', resource_id: device, version: 1, status: 'succeeded'};
beforeAll(async () => {
  const pair = await crypto.subtle.generateKey({name: 'ECDSA', namedCurve: 'P-256'}, true, ['sign', 'verify']);
  const bytes = new Uint8Array(await crypto.subtle.exportKey('spki', pair.publicKey));
  const publicKey = btoa(String.fromCharCode(...bytes));
  const fingerprint = [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))].map((value) => value.toString(16).padStart(2, '0')).join('');
  publicIdentity = {contract_version: 1, installation_id: installation, public_key_spki_base64: publicKey, key_sha256: fingerprint, signing_certificate_sha256: 'b'.repeat(64)};
  intent = {label: 'Receiver handset', app_id: 'app.collect.gateway', installation_id: installation, public_key_spki_base64: publicKey, key_sha256: fingerprint, signing_certificate_sha256: 'b'.repeat(64), reason: 'Review device identity'};
  const resource = {id: device, label: intent.label, app_id: intent.app_id, installation_id: installation, public_key_spki_base64: publicKey, key_sha256: fingerprint, signing_certificate_sha256: intent.signing_certificate_sha256, state: 'pending', version: 1, created_at: time, activated_at: null, revoked_at: null, last_heartbeat_at: null, carrier_proof: false, send_authority: false};
  detail = {resource_type: 'gateway_devices', resource, current_actor_id: actor, can_manage: true, related_truncated: false, related: {heartbeats: []}, enrollment: {contract_version: 1, device_id: device, installation_id: installation, key_sha256: fingerprint, signing_certificate_sha256: intent.signing_certificate_sha256}};
});
beforeEach(() => {sessionStorage.clear(); localStorage.clear(); Object.defineProperty(navigator, 'locks', {configurable: true, value: {request: async (name: string, _options: unknown, work: (lock: {name: string}) => Promise<unknown>) => work({name})}});});
afterEach(() => {mock.request.mockReset(); if (originalLocks) Object.defineProperty(navigator, 'locks', originalLocks); else Reflect.deleteProperty(navigator, 'locks');});

describe('Gateway enrollment page', () => {
  it('does not expose enrollment when the qualification gate is closed', async () => {
    render(<MemoryRouter><GatewayEnrollmentPage /></MemoryRouter>);
    expect(await screen.findByText('Device enrollment is unavailable in this workspace.')).toBeVisible();
    expect(screen.queryByRole('button', {name: 'Review device enrollment'})).not.toBeInTheDocument();
    expect(mock.request).not.toHaveBeenCalled();
  });
  it('reviews the public handset identity and requires explicit confirmation', async () => {
    const user = userEvent.setup();
    mock.request.mockResolvedValueOnce(receipt).mockResolvedValueOnce(detail);
    render(<MemoryRouter><GatewayEnrollmentPage allowActions /></MemoryRouter>);
    await user.type(await screen.findByLabelText('Device label'), intent.label);
    await user.type(screen.getByLabelText('Android app ID'), intent.app_id);
    await user.click(screen.getByLabelText('Handset public identity JSON'));
    await user.paste(JSON.stringify(publicIdentity));
    await user.type(screen.getByLabelText('Reason for device change'), intent.reason);
    await user.click(screen.getByRole('button', {name: 'Review device enrollment'}));
    expect(await screen.findByRole('dialog', {name: 'Review device enrollment'})).toBeVisible();
    expect(screen.getByText(intent.key_sha256)).toBeVisible();
    expect(screen.getByRole('button', {name: 'Confirm enrollment'})).toBeDisabled();
    expect(mock.request).not.toHaveBeenCalled();
    await user.click(screen.getByRole('checkbox', {name: 'I compared the installation and fingerprints with the handset.'}));
    await user.click(screen.getByRole('button', {name: 'Confirm enrollment'}));
    expect(await screen.findByText(`Device enrollment recorded. Request ${operation}.`)).toBeVisible();
    expect(screen.getByRole('link', {name: 'Open enrolled device'})).toHaveAttribute('href', `/admin/gateway/${device}`);
    expect(mock.request).toHaveBeenCalledTimes(2);
  });
  it('rejects a stale reviewed identity after another tab completed an enrollment', async () => {
    const user = userEvent.setup();
    render(<MemoryRouter><GatewayEnrollmentPage allowActions /></MemoryRouter>);
    await user.type(await screen.findByLabelText('Device label'), intent.label);
    await user.type(screen.getByLabelText('Android app ID'), intent.app_id);
    await user.click(screen.getByLabelText('Handset public identity JSON')); await user.paste(JSON.stringify(publicIdentity));
    await user.type(screen.getByLabelText('Reason for device change'), intent.reason);
    await user.click(screen.getByRole('button', {name: 'Review device enrollment'}));
    await screen.findByRole('dialog', {name: 'Review device enrollment'});
    await withPendingFence({identity: mock.user, family: 'gateway-device-enrollment', resourceId: 'new', isCurrent: () => true}, async (access) => {access.reserve(key, access.read().revision); access.clear(key);});
    await user.click(screen.getByRole('checkbox', {name: 'I compared the installation and fingerprints with the handset.'}));
    await user.click(screen.getByRole('button', {name: 'Confirm enrollment'}));
    expect(await screen.findByText('The request could not be started safely. Check the original request and review again.')).toBeVisible();
    expect(mock.request).not.toHaveBeenCalled();
  });
  it('checks an existing request with new enrollment disabled and never retries automatically', async () => {
    const user = userEvent.setup();
    await retainPending(mock.user, 'gateway-device-enrollment', 'new', key, 'gateway.manage', {...intent});
    mock.request.mockResolvedValueOnce({status: 'not_found'});
    render(<MemoryRouter><GatewayEnrollmentPage /></MemoryRouter>);
    await user.click(await screen.findByRole('button', {name: 'Check original request'}));
    expect(await screen.findByText(/No receipt was found/)).toBeVisible();
    expect(screen.queryByRole('button', {name: 'Review identical retry'})).not.toBeInTheDocument();
    expect(mock.request).toHaveBeenCalledTimes(1);
    expect(mock.request).toHaveBeenCalledWith(`operations/requests/${key}`);
  });
});
