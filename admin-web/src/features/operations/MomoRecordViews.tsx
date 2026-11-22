import type {ReactNode} from 'react';
import {Button, EmptyState, ErrorState, LoadingState} from '../../ui';
import type {Page} from './contracts';
import type {OperationReadState} from './useOperationRead';

export const momoReadOptions = {invalidResponse: 'The MoMo records could not be verified.'};

const momoAmount = new Intl.NumberFormat('en-RW', {maximumFractionDigits: 0});

export function formatMomoAmount(value: number) {
  return `RWF ${momoAmount.format(value)}`;
}

export function MomoPager<T>({page, change}: {page: Page<T>; change: (offset: number) => void}) {
  return <div className="operations-pagination"><span>{page.rows.length ? `Showing ${page.offset + 1}–${page.offset + page.rows.length} of ${page.total}` : `No records on this page · ${page.total} total`}</span><div><Button onClick={() => change(Math.max(0, page.offset - page.limit))} disabled={page.offset === 0}>Previous</Button><Button onClick={() => change(page.offset + page.limit)} disabled={page.offset + page.rows.length >= page.total}>Next</Button></div></div>;
}
export function MomoTable({name, headings, children}: {name: string; headings: string[]; children: ReactNode}) {
  return <div className="admin-table-wrap" role="region" aria-label={name} tabIndex={0}><table className="admin-table"><thead><tr>{headings.map((heading) => <th scope="col" key={heading}>{heading}</th>)}</tr></thead><tbody>{children}</tbody></table></div>;
}
export function MomoResult<T>({result, retry, empty, children}: {result: OperationReadState<T> | null; retry: () => void; empty: (value: T) => boolean; children: (value: T) => ReactNode}) {
  if (!result) return <LoadingState label="Loading records" />;
  if (result.status === 'error') return <ErrorState message={result.message} onRetry={retry} />;
  if (empty(result.value)) return <EmptyState title="No matching records" description="Change your filters or check again later." />;
  return children(result.value);
}
