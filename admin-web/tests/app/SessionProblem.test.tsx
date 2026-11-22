import {fireEvent, render, screen} from '@testing-library/react';
import {describe, expect, it, vi} from 'vitest';
import {SessionProblem} from '../../src/app/SessionRoutes';

describe('session recovery controls', () => {
  it('offers a recheck and explicit sign-out while MFA recovery is unresolved', () => {
    const refresh = vi.fn().mockResolvedValue(undefined), signOut = vi.fn().mockResolvedValue(undefined);
    render(<SessionProblem session={{logoutUnconfirmed: false, mfaRecoveryPending: true, error: 'Recovery is pending.', refresh, signOut}} />);
    fireEvent.click(screen.getByRole('button', {name: /try again/i}));
    expect(refresh).toHaveBeenCalledOnce(); expect(signOut).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole('button', {name: 'Sign out of this session'}));
    expect(signOut).toHaveBeenCalledOnce();
  });

  it('retries only sign-out when sign-out was not confirmed', () => {
    const refresh = vi.fn().mockResolvedValue(undefined), signOut = vi.fn().mockResolvedValue(undefined);
    render(<SessionProblem session={{logoutUnconfirmed: true, mfaRecoveryPending: true, error: 'Sign-out is pending.', refresh, signOut}} />);
    expect(screen.queryByRole('button', {name: 'Sign out of this session'})).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', {name: /try again/i}));
    expect(signOut).toHaveBeenCalledOnce(); expect(refresh).not.toHaveBeenCalled();
  });

  it('offers sign-out when the account policy cannot be opened', () => {
    const refresh = vi.fn().mockResolvedValue(undefined), signOut = vi.fn().mockResolvedValue(undefined);
    render(<SessionProblem session={{logoutUnconfirmed: false, mfaRecoveryPending: false, error: 'Account verification is unavailable.', refresh, signOut}} />);
    fireEvent.click(screen.getByRole('button', {name: 'Sign out of this session'}));
    expect(signOut).toHaveBeenCalledOnce(); expect(refresh).not.toHaveBeenCalled();
  });
});
