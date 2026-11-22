import {useEffect, useState} from 'react';
import type {AdminRequest} from '../../api/client';
import {Button, Card, ErrorState, Icon, LoadingState, PageHeader} from '../../ui';
import type {FinancialModel} from '../core/types';
import {formatOverviewValue, parseOverview, type OverviewData} from './overview';
import {SmsOversight} from './SmsOversight';
import './overview.css';

const metricAppearance: Record<string, {icon: string; tone: string}> = {
  groups: {icon: 'users', tone: 'success'},
  users: {icon: 'user', tone: 'info'},
  active_members: {icon: 'user-check', tone: 'success'},
  unallocated_transactions: {icon: 'layers', tone: 'warning'},
  payment_evidence: {icon: 'file', tone: 'info'},
  receipts_needing_review: {icon: 'message', tone: 'warning'},
  total_net_contributions_rwf: {icon: 'swap', tone: 'info'},
  total_posted_contributions_rwf: {icon: 'swap', tone: 'info'},
};

export function OverviewPage({request, permissions, financialModel, authorityKey}: {
  request: AdminRequest; permissions: readonly string[]; financialModel: FinancialModel; authorityKey: string;
}) {
  const [result, setResult] = useState<{scope: string; data: OverviewData | null; error: string} | null>(null);
  const [generation, setGeneration] = useState(0);
  const allowed = permissions.includes('overview.read');
  const scope = JSON.stringify([authorityKey, financialModel, generation]);
  const current = result?.scope === scope ? result : null;
  const loading = allowed && current === null;
  useEffect(() => {
    if (!allowed) return;
    const controller = new AbortController();
    void request('core/overview', {authenticated: true, signal: controller.signal})
      .then((value) => {if (!controller.signal.aborted) setResult({scope, data: parseOverview(value, financialModel), error: ''});})
      .catch((failure: unknown) => {if (!controller.signal.aborted) setResult({scope, data: null,
        error: failure instanceof Error ? failure.message : 'The workspace totals could not be loaded.'});});
    return () => controller.abort();
  }, [allowed, financialModel, request, scope]);
  if (!allowed) return <><PageHeader title="Operations overview" /><ErrorState title="Access unavailable" message="Your account cannot view workspace totals." /></>;
  const preferred = ['groups', 'users', 'active_members', 'unallocated_transactions',
    financialModel === 'canonical_evidence_ledger' ? 'payment_evidence' : 'receipts_needing_review',
    financialModel === 'canonical_evidence_ledger' ? 'total_net_contributions_rwf' : 'total_posted_contributions_rwf'];
  const data = current?.data;
  const metrics = data ? preferred.flatMap((key) => data.metrics.filter((metric) => metric.key === key)) : [];
  return <>
    <PageHeader eyebrow="Collect Admin / Workspace" title="Operations overview"
      subtitle="Review recorded activity and open the work your account can access."
      actions={<Button icon="refresh" disabled={loading} onClick={() => setGeneration((value) => value + 1)}>Refresh overview</Button>} />
    {loading ? <LoadingState label="Loading workspace totals" /> : current?.error ?
      <ErrorState message={current.error} onRetry={() => setGeneration((value) => value + 1)} /> : data && <>
        <div className="overview-grid" aria-label="Workspace metrics">{metrics.map((metric) => <Card className="overview-metric" key={metric.key}>
          <div className="overview-metric-heading"><span>{metric.label}</span>
            <span className={`overview-metric-icon overview-metric-icon--${metricAppearance[metric.key].tone}`}><Icon name={metricAppearance[metric.key].icon} /></span>
          </div><strong>{formatOverviewValue(metric)}</strong>
          <small>{metric.monetary ? 'Recorded evidence · not provider settlement' : 'Workspace total'}</small>
        </Card>)}</div>
        <p className="overview-measured">Measured {new Date(data.measuredAt).toLocaleString()} · {financialModel === 'canonical_evidence_ledger' ? 'Recorded evidence' : 'Transaction journals'}</p>
      </>}
    <SmsOversight request={request} permissions={permissions} authorityKey={authorityKey} />
  </>;
}
