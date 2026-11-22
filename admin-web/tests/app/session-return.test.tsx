import {render, screen} from '@testing-library/react';
import {MemoryRouter, Route, Routes, useLocation} from 'react-router';
import {describe, expect, it} from 'vitest';
import {SessionRedirectRoute} from '../../src/app/SessionRoutes';

function Destination() {
  const location = useLocation();
  return <output>{location.pathname}{location.search}</output>;
}

function openSession(returnTo?: string) {
  const search = returnTo === undefined ? '' : `?${new URLSearchParams({returnTo})}`;
  render(<MemoryRouter initialEntries={[`/admin/session${search}`]}><Routes>
    <Route path="/admin/session" element={<SessionRedirectRoute />} />
    <Route path="*" element={<Destination />} />
  </Routes></MemoryRouter>);
}

describe('legacy session return links', () => {
  it('retains a safe Admin destination and its query while the shell checks the session', async () => {
    openSession('/admin/transactions?view=momo');
    expect(await screen.findByText('/admin/transactions?view=momo')).toBeInTheDocument();
  });

  it.each([undefined, '//other.example/admin', '/admin/session', '/admin/../outside', '/admin/login', '/admin/Login/', '/admin/%6Cogin'])
    ('falls back to the overview for an absent or unsafe return location %s', async (returnTo) => {
      openSession(returnTo);
      expect(await screen.findByText('/admin')).toBeInTheDocument();
    });
});
