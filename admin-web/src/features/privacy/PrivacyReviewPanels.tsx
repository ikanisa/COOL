import type {ReactNode} from 'react';
import {Button, Card, EmptyState, StatusBadge} from '../../ui';
import {canStartPrivacyClaim, type PrivacyDetail, type PrivacyPageData, type RetentionInspection} from './contracts';

const states: Record<string, string> = {
  not_started: 'Not started',
  awaiting_review: 'Awaiting review',
  claim_active: 'Review in progress',
  claim_expired: 'Review claim expired',
  blocked: 'Waiting for approved policy',
};

function formatDate(value: number): string {
  return new Date(value).toISOString().replace('T', ' ').replace(/\.\d{3}Z$/, ' UTC');
}

interface PrivacyQueueProps {
  page: PrivacyPageData;
  number: number;
  busy: boolean;
  onPrevious: () => void;
  onNext: () => void;
  onOpen: (requestId: string) => void;
}

export function PrivacyReviewQueue({page, number, busy, onPrevious, onNext, onOpen}: PrivacyQueueProps) {
  return <Card className="privacy-panel">
    <h2>Requests · page {number}</h2>
    {page.items.length === 0 ? <EmptyState title="No privacy requests on this page" description="Refresh to check again." /> :
      <div className="admin-table-wrap" role="region" aria-label="Privacy requests" tabIndex={0}>
        <table className="admin-table">
          <thead><tr><th scope="col">Request identifier</th><th scope="col">State</th><th scope="col">Accepted</th><th scope="col">Open</th></tr></thead>
          <tbody>{page.items.map(item => <tr key={item.requestId}>
            <td><code>{item.requestId}</code></td>
            <td><StatusBadge tone="warning">{states[item.state]}</StatusBadge></td>
            <td>{formatDate(item.acceptedAt)}</td>
            <td><Button disabled={busy} onClick={() => onOpen(item.requestId)}>Open request</Button></td>
          </tr>)}</tbody>
        </table>
      </div>}
    <div className="privacy-actions">
      <Button disabled={busy || number < 2} onClick={onPrevious}>Previous requests</Button>
      <Button disabled={busy || !page.next} onClick={onNext}>Next requests</Button>
    </div>
  </Card>;
}

function RetentionInspectionTable({inspection}: {inspection: RetentionInspection}) {
  const rows = [
    ['Stored objects', inspection.objectCount],
    ['Active legal holds', inspection.activeHoldCount],
    ['Unresolved work', inspection.inFlightUnresolved ? 'Present' : 'None observed'],
    ...Object.entries(inspection.tableCounts),
    ['Source fingerprint', <code>{inspection.sourceId}</code>],
    ['Schema fingerprint', <code>{inspection.schemaSha256}</code>],
    ['Scope fingerprint', <code>{inspection.snapshotSha256}</code>],
  ] as const;
  return <div className="admin-table-wrap" role="region" aria-label="Retained information" tabIndex={0}>
    <table className="admin-table"><thead><tr><th scope="col">Field</th><th scope="col">Value</th></tr></thead>
      <tbody>{rows.map(([field, value]) => <tr key={field}><td>{field}</td><td>{value}</td></tr>)}</tbody>
    </table>
  </div>;
}

interface PrivacyDetailProps {
  detail: PrivacyDetail;
  inspection: RetentionInspection | null;
  busy: boolean;
  onInspect: () => void;
  onPrepare?: (kind: 'claim' | 'outcome') => void;
  children?: ReactNode;
}

export function PrivacyReviewDetail({detail, inspection, busy, onInspect, onPrepare, children}: PrivacyDetailProps) {
  const item = detail.item;
  return <Card className="privacy-panel">
    <h2>Request details</h2>
    {item ? <dl className="privacy-details">
      <div><dt>Request identifier</dt><dd>{item.requestId}</dd></div>
      <div><dt>State</dt><dd>{states[item.state]}</dd></div>
      <div><dt>Accepted</dt><dd>{formatDate(item.acceptedAt)}</dd></div>
      <div><dt>Observed revision</dt><dd>{item.revision}</dd></div>
      <div><dt>Evidence checked</dt><dd>{formatDate(detail.checkedAt)}</dd></div>
      {item.claimExpiresAt !== null && <div><dt>Review claim expires</dt><dd>{formatDate(item.claimExpiresAt)}</dd></div>}
      {item.outcomeRecordedAt !== null && <div><dt>Policy blocker recorded</dt><dd>{formatDate(item.outcomeRecordedAt)}</dd></div>}
    </dl> : <p>This request is no longer available.</p>}
    {detail.ownClaim && <p>The current session owns this review claim.</p>}
    {item && onPrepare && <div className="privacy-actions">
      <Button disabled={busy || !canStartPrivacyClaim(item)} onClick={() => onPrepare('claim')}>Start review</Button>
      <Button disabled={busy || !detail.ownClaim} onClick={() => onPrepare('outcome')}>Record policy blocker</Button>
    </div>}
    {children}
    {item && <section>
      <h3>Retained information</h3>
      <p>Inspect retained information, legal holds and unresolved work. Retained records are not automatically eligible for erasure.</p>
      <Button disabled={busy} onClick={onInspect}>Inspect retained scope</Button>
      {inspection && <RetentionInspectionTable inspection={inspection} />}
    </section>}
  </Card>;
}
