import {render, screen, within} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import {describe, expect, it} from 'vitest';
import {LicensesPage} from '../../src/features/licenses/LicensesPage';

describe('offline license notices', () => {
  it('filters the bundled package list and exposes the notice text', async () => {
    render(<LicensesPage />);
    await userEvent.type(screen.getByLabelText('Search packages'), 'react-dom');
    const target = screen.getByText('react-dom').closest('details');
    expect(target).not.toBeNull();
    await userEvent.click(screen.getByText('react-dom'));
    expect(target).toHaveAttribute('open');
    expect(within(target!).getByText(/permission is hereby granted, free of charge/i)).toBeInTheDocument();
    expect(screen.queryByText('react-router')).not.toBeInTheDocument();
  });
});
