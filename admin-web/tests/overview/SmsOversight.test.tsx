import {render, screen} from '@testing-library/react';
import {describe, expect, it, vi} from 'vitest';
import {parseSmsOversight, SmsOversight} from '../../src/features/overview/SmsOversight';

function sample(checkedAt = new Date().toISOString()) {
  return {contract_version: 1, scope: 'admin_operational_health', metrics_scope: 'all_retained_rows',
    worker_heartbeat: 'not_recorded', external_services_checked: false, checked_at: checkedAt,
    configuration: {momo_processing: 'paused', native_auto_processing: 'disabled', native_sms_ledger: 'disabled'},
    queues: {assisted_sms: {queued: 4, claimed: 1, send_started: 2, uncertain: 1, automatic_retry: false}}};
}
describe('SMS oversight', () => {
  it('rejects changed meaning, invalid timestamps and unbounded counts', () => {
    expect(parseSmsOversight(sample()).counts.queued).toBe(4);
    expect(() => parseSmsOversight({...sample(), worker_heartbeat: 'healthy'})).toThrow();
    expect(() => parseSmsOversight({...sample(), checked_at: '2026-02-31T00:00:00.000Z'})).toThrow();
    const bad = sample(); bad.queues.assisted_sms.queued = -1;
    expect(() => parseSmsOversight(bad)).toThrow();
  });
  it('shows only authorized fresh samples without claiming provider availability', async () => {
    const request = vi.fn(async () => sample());
    const {rerender} = render(<SmsOversight request={request} permissions={['system_health.read']} authorityKey="session-a" />);
    expect(await screen.findByText('Queued receipts')).toBeInTheDocument();
    expect(screen.getByText(/worker activity and provider availability are not verified/i)).toBeInTheDocument();
    rerender(<SmsOversight request={request} permissions={[]} authorityKey="session-b" />);
    expect(screen.queryByText('Queued receipts')).not.toBeInTheDocument();
    expect(request).toHaveBeenCalledTimes(1);
  });
  it('keeps scoped internal credits, gateway acceptance and reported delivery distinct', async () => {
    const value = sample();
    const payer = {pending: 0, gateway_accepted: 3, sent: 2, delivered: 1, failed: 0, unknown: 2, suppressed: 0};
    const payload = {...value, queues: {...value.queues,
      burimunsi_sms: {pending: 2, retrying: 1, blocked: 0, unmatched: 1, posted: 7, oldest_pending_seconds: 90},
      burimunsi_payer_sms: payer,
    }};
    render(<SmsOversight request={vi.fn(async () => payload)} permissions={['system_health.read', 'sms.read']} authorityKey="session-a" />);
    expect(await screen.findByRole('heading', {name: 'BuriMunsi payer receipts'})).toBeVisible();
    expect(screen.getByText('Internally credited')).toBeVisible();
    expect(screen.getByText('Gateway accepted')).toBeVisible();
    expect(screen.getByText('Reported delivered')).toBeVisible();
    expect(() => parseSmsOversight({...payload, queues: {...payload.queues, burimunsi_payer_sms: {...payer, delivered: -1}}})).toThrow();
  });
  it('does not show stale counts as current', async () => {
    const request = vi.fn(async () => sample(new Date(Date.now() - 65_000).toISOString()));
    render(<SmsOversight request={request} permissions={['system_health.read']} authorityKey="session-a" />);
    expect(await screen.findByText('Sample expired. Refresh for current counts.')).toBeInTheDocument();
    expect(screen.queryByText('Queued receipts')).not.toBeInTheDocument();
  });
});
