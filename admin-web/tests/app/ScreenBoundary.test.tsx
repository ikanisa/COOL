import {lazy, Suspense} from 'react';
import {render, screen} from '@testing-library/react';
import {describe, expect, it, vi} from 'vitest';
import {ScreenBoundary} from '../../src/app/SessionRoutes';

describe('screen loading failure', () => {
  it('offers a manual recovery instead of leaving a blank workspace when a page chunk fails', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => undefined);
    const FailedPage = lazy(() => Promise.reject(new Error('Synthetic missing chunk')));
    render(<ScreenBoundary><Suspense fallback={<p>Opening</p>}><FailedPage /></Suspense></ScreenBoundary>);
    expect(await screen.findByRole('heading', {name: 'Page unavailable'})).toBeInTheDocument();
    expect(screen.getByText(/Finish work in other Admin tabs/)).toBeInTheDocument();
    expect(screen.getByRole('button', {name: 'Try again'})).toBeInTheDocument();
  });
});
