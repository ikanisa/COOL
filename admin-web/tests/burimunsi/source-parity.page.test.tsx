import {webcrypto} from 'node:crypto';
import {render, screen} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import {beforeEach, describe, expect, it, vi} from 'vitest';
import type {SessionContextValue} from '../../src/session/SessionProvider';
import {BuriMunsiPage} from '../../src/features/burimunsi';
import {owner} from './fixture';
import captured from './source-parity.generated.json';

const hook = vi.hoisted(() => ({value: null as unknown as SessionContextValue}));
vi.mock('../../src/session/SessionProvider', async original => ({...await original<typeof import('../../src/session/SessionProvider')>(), useSession: () => hook.value}));
function setup(mode: 'empty' | 'populated', user = owner) {
  const request = vi.fn<SessionContextValue['request']>(async path => {
    if (path === 'momo/native-setup') return captured[mode].setup;
    if (path === 'burimunsi/operators?collectionId=synthetic-savings') return captured[mode].operators;
    if (path === 'burimunsi/provisioning?collectionId=synthetic-savings') return captured[mode].provisioning;
    throw new Error(`Unexpected request: ${path}`);
  });
  hook.value = {status: 'authenticated', user, epoch: 7, verificationMode: 'email', request,
    isCurrentAuthority: () => true, isRecentSensitiveVerification: () => true, sensitiveEmailRecovery: () => null,
    recheckSensitiveEmailVerification: vi.fn(async () => true)} as unknown as SessionContextValue;
  return request;
}
beforeEach(() => {sessionStorage.clear(); localStorage.clear(); Object.defineProperty(globalThis, 'crypto', {value: webcrypto, configurable: true});});

describe('BuriMunsi read-only page with source-generated results', () => {
  it('shows an empty state without guessing or requesting a group', async () => {
    const request = setup('empty'), user = userEvent.setup(); render(<BuriMunsiPage readOnlyReview />);
    await user.click(screen.getByRole('button', {name: 'Check verification and load groups'}));
    expect(await screen.findByText('No prepared groups')).toBeVisible();
    expect(request).toHaveBeenCalledTimes(1); expect(request).toHaveBeenCalledWith('momo/native-setup');
  });
  it('shows real contract shapes, recorded versions and disabled scope without write controls', async () => {
    const request = setup('populated'), user = userEvent.setup(); render(<BuriMunsiPage readOnlyReview />);
    await user.click(screen.getByRole('button', {name: 'Check verification and load groups'}));
    expect(await screen.findByRole('option', {name: 'Group untitled-other'})).toBeInTheDocument();
    expect(screen.getByRole('option', {name: 'Synthetic line'})).toBeInTheDocument();
    await user.selectOptions(screen.getByRole('combobox', {name: 'Group'}), 'synthetic-savings');
    await user.click(screen.getByRole('button', {name: 'Load group access'}));
    expect(await screen.findByRole('row', {name: /staff@example.test/})).toHaveTextContent('Recorded enabled');
    expect(screen.getByRole('row', {name: /second@example.test/})).toHaveTextContent('Recorded disabled');
    expect(screen.getByText(/Recorded scope: not enabled · configured/)).toBeVisible();
    expect(screen.getByText(/internal_receiver · recorded active · version 9/)).toBeVisible();
    expect(screen.queryByRole('button', {name: /approve|grant|set pin|revocation|save access/i})).not.toBeInTheDocument();
    expect(request).toHaveBeenCalledTimes(3);
    expect(request.mock.calls.every(([, options]) => !options?.method || options.method === 'GET')).toBe(true);
  });
  it('does not request these records for an owner lacking the required permissions', () => {
    const request = setup('populated', {...owner, permissions: ['admin_users.manage']});
    render(<BuriMunsiPage readOnlyReview />);
    expect(screen.getByText(/needs current team and receiving-phone permissions/)).toBeVisible();
    expect(request).not.toHaveBeenCalled();
  });
  it('can preview a legacy operator while keeping approval mutation unavailable', async () => {
    const request = setup('populated'), user = userEvent.setup(); render(<BuriMunsiPage operatorPreparationEnabled />);
    await user.click(screen.getByRole('button', {name: 'Check verification and load groups'}));
    await user.selectOptions(await screen.findByRole('combobox', {name: 'Group'}), 'synthetic-savings');
    await user.click(screen.getByRole('button', {name: 'Load group access'}));
    await user.selectOptions(await screen.findByRole('combobox', {name: 'Collect account'}), '55555555-5555-4555-8555-555555555555');
    await user.click(screen.getByRole('button', {name: 'Review access'}));
    expect(await screen.findByRole('region', {name: 'Access preview'})).toHaveTextContent('Nothing has been sent or changed.');
    expect(screen.queryByRole('button', {name: /apply|confirm|submit|save access/i})).not.toBeInTheDocument();
    expect(request.mock.calls.every(([, options]) => !options?.method || options.method === 'GET')).toBe(true);
  });
});
