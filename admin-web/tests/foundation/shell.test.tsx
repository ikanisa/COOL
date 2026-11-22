import { fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { useState } from 'react';
import { describe, expect, it, vi } from 'vitest';
import { AdminShell } from '../../src/layout/AdminShell';
import { Button, Dialog } from '../../src/ui';

const navigation = [
  { label: 'Overview', path: '/admin', section: 'Workspace', icon: 'home' },
  { label: 'Groups', path: '/admin/groups', section: 'Workspace', icon: 'users' },
  { label: 'Users', path: '/admin/users', section: 'People', icon: 'user' },
];

describe('Admin shell', () => {
  it('shows supplied destinations, the current section and the signed-in operator', () => {
    const signOut = vi.fn();
    render(<AdminShell navigation={navigation} currentPath="/admin/groups/record" identity={{ name: 'Operator', role: 'Staff' }} onSignOut={signOut}><h1>Group detail</h1></AdminShell>);
    expect(screen.getByRole('link', { name: 'Groups' })).toHaveAttribute('aria-current', 'location');
    expect(screen.getByRole('link', { name: 'Groups' })).toHaveAttribute('href', '#/admin/groups');
    expect(screen.getByRole('heading', { name: 'Group detail' })).toBeVisible();
    expect(screen.getByRole('button', { name: 'Account: Operator' })).toBeVisible();
    expect(signOut).not.toHaveBeenCalled();
  });

  it('filters only supplied navigation and supports the search shortcut', async () => {
    const user = userEvent.setup();
    render(<AdminShell navigation={navigation} currentPath="/admin"><p>Overview</p></AdminShell>);
    fireEvent.keyDown(document, { key: 'k', ctrlKey: true });
    const search = screen.getByRole('searchbox', { name: 'Search admin sections' });
    expect(search).toHaveFocus();
    await user.type(search, 'users');
    const nav = screen.getByRole('navigation', { name: 'Admin sections' });
    expect(within(nav).getByRole('link', { name: 'Users' })).toBeVisible();
    expect(within(nav).queryByRole('link', { name: 'Groups' })).not.toBeInTheDocument();
    await user.keyboard('{Escape}');
    expect(within(nav).getByRole('link', { name: 'Groups' })).toBeVisible();
  });

  it('opens only the selected match when keyboard navigation offers multiple sections', async () => {
    const original = window.location.href;
    window.history.replaceState(null, '', '#/admin');
    try {
      const user = userEvent.setup();
      const receipts = [
        {label: 'SMS receipts', path: '/admin/sms-receipts', section: 'Communications'},
        {label: 'MoMo receipts', path: '/admin/momo-receipts', section: 'Communications'},
      ];
      render(<AdminShell navigation={receipts} currentPath="/admin"><p>Overview</p></AdminShell>);
      const search = screen.getByRole('searchbox', {name: 'Search admin sections'});
      await user.type(search, 'receipts{Enter}');
      expect(window.location.hash).toBe('#/admin');
      await user.keyboard('{ArrowDown}');
      expect(screen.getByRole('link', {name: 'SMS receipts'})).toHaveFocus();
      await user.keyboard('{ArrowDown}');
      expect(screen.getByRole('link', {name: 'MoMo receipts'})).toHaveFocus();
      await user.keyboard('{Enter}');
      await waitFor(() => expect(window.location.hash).toBe('#/admin/momo-receipts'));
    } finally {
      window.history.replaceState(null, '', original);
    }
  });

  it('exposes mobile navigation state and closes it with Escape', async () => {
    const user = userEvent.setup();
    render(<AdminShell navigation={navigation} currentPath="/admin"><p>Overview</p></AdminShell>);
    const menu = screen.getByRole('button', { name: 'Open navigation' });
    expect(menu).toHaveAttribute('aria-expanded', 'false');
    await user.click(menu);
    expect(menu).toHaveAttribute('aria-expanded', 'true');
    await user.keyboard('{Escape}');
    expect(menu).toHaveAttribute('aria-expanded', 'false');
    expect(menu).toHaveFocus();
  });

  it('returns keyboard focus to the account trigger when its disclosure closes', async () => {
    const user = userEvent.setup(), signOut = vi.fn();
    render(<AdminShell navigation={navigation} currentPath="/admin" identity={{name: 'Operator'}} onSignOut={signOut}>
      <p>Overview</p>
    </AdminShell>);
    const trigger = screen.getByRole('button', {name: 'Account: Operator'});
    await user.click(trigger);
    await user.tab();
    expect(screen.getByRole('button', {name: 'Sign out'})).toHaveFocus();
    await user.keyboard('{Escape}');
    expect(trigger).toHaveAttribute('aria-expanded', 'false');
    expect(trigger).toHaveFocus();
    expect(signOut).not.toHaveBeenCalled();
  });

  it('opens matching navigation after searching on a small screen', async () => {
    const previous = window.matchMedia;
    window.matchMedia = vi.fn().mockReturnValue({matches: true});
    try {
      const user = userEvent.setup();
      render(<AdminShell navigation={navigation} currentPath="/admin"><p>Overview</p></AdminShell>);
      const search = screen.getByRole('searchbox', { name: 'Search admin sections' });
      await user.type(search, 'users{Enter}');
      expect(screen.getByRole('button', { name: 'Open navigation' })).toHaveAttribute('aria-expanded', 'true');
      expect(within(screen.getByRole('navigation', { name: 'Admin sections' })).getByRole('link', { name: 'Users' })).toBeVisible();
    } finally {window.matchMedia = previous;}
  });
});

function DialogExample() {
  const [open, setOpen] = useState(false);
  return <><Button onClick={() => setOpen(true)}>Review</Button><Dialog open={open} title="Review record" onClose={() => setOpen(false)}><label htmlFor="note">Note</label><input id="note" /><Button>Confirm</Button></Dialog></>;
}

describe('Shared controls', () => {
  it('traps dialog keyboard focus and restores the trigger on Escape', async () => {
    const user = userEvent.setup();
    render(<DialogExample />);
    const trigger = screen.getByRole('button', { name: 'Review' });
    await user.click(trigger);
    const dialog = screen.getByRole('dialog', { name: 'Review record' });
    expect(within(dialog).getByRole('button', { name: 'Close dialog' })).toHaveFocus();
    await user.tab({ shift: true });
    expect(within(dialog).getByRole('button', { name: 'Confirm' })).toHaveFocus();
    await user.keyboard('{Escape}');
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    expect(trigger).toHaveFocus();
  });

  it('disables a loading action and exposes its busy state', () => {
    render(<Button loading>Save</Button>);
    expect(screen.getByRole('button', { name: 'Save' })).toBeDisabled();
    expect(screen.getByRole('button', { name: 'Save' })).toHaveAttribute('aria-busy', 'true');
  });
});
