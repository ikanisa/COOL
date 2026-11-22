import {useCallback} from 'react';
import {useScopedRead} from '../../api/useScopedRead';
import {Button, Card, ErrorState, LoadingState, PageHeader} from '../../ui';
import {evidenceReference, formatField, isId, paymentReference} from '../core/contracts';
import type {PendingIdentity} from '../core/pendingAttempt';
import type {FeatureAccess} from '../core/types';
import {CanonicalReconciliationActions} from './CanonicalActions';
import {LegacyReconciliationActions} from './LegacyReconciliationActions';
import {RelatedReconciliationRecords} from './RelatedReconciliationRecords';
import {parseReconciliationDetail} from './contracts';
import {reconciliationPageSize, reconciliationReturnLocation} from './reconciliationRoutes';
import '../core/core.css';

interface DetailProps extends FeatureAccess {
  id: string;
  returnTo?: string | null;
  identity?: PendingIdentity;
  allowMutations?: boolean;
  verifyFresh?: () => Promise<boolean>;
}

const detailFields: readonly [string, string][] = [['title', 'Reference'], ['provider_reference', 'Provider reference'], ['group_name', 'Group'], ['group_title', 'Group'], ['payee_label', 'Receiver'], ['payee_name', 'Receiver'], ['amount_rwf', 'Recorded amount'], ['allocated_amount_rwf', 'Allocated amount'], ['unallocated_amount_rwf', 'Unallocated amount'], ['status', 'Status'], ['verification_status', 'Evidence status'], ['settlement_status', 'Provider settlement']];

export function ReconciliationDetailPage({ id, request, permissions, actorId, principalId, authorityKey, financialModel, navigate, returnTo, role, identity, allowMutations = false, verifyFresh }: DetailProps) {
  const allowed = permissions.includes('reconciliations.read');
  const permissionToken = JSON.stringify([...permissions].sort());
  const currentScope = JSON.stringify([authorityKey, financialModel, id, actorId, principalId, role, permissionToken]);
  const load = useCallback(async (signal: AbortSignal) => {
    const query = new URLSearchParams({limit: String(reconciliationPageSize), offset: '0'});
    const data = await request(`reconciliations/${id}?${query}`, {signal});
    return parseReconciliationDetail(data, financialModel, id, actorId, principalId, JSON.parse(permissionToken) as string[], role);
  }, [id, request, financialModel, actorId, principalId, permissionToken, role]);
  const {result: read, refresh} = useScopedRead(allowed && isId(id), currentScope, load);
  const result = read?.value;
  return <>
    <PageHeader title="Reconciliation" subtitle="Review the retained evidence and related records." actions={<Button type="button" onClick={() => navigate(reconciliationReturnLocation(returnTo))}>Back to reconciliations</Button>} />
    {!allowed ? <ErrorState title="Access unavailable" message="Your account does not have permission to view this record." /> :
      !isId(id) ? <ErrorState message="Select a valid record." /> :
      !read ? <LoadingState label="Loading reconciliation" /> :
      read.failed || !result ? <ErrorState message="The reconciliation could not be verified or the service is unavailable." onRetry={refresh} /> : <>
        <Card><div className="core-detail"><h2>Payment evidence</h2><dl>{detailFields.filter(([key]) => result.resource[key] !== undefined).map(([key, title]) => <div key={key}><dt>{financialModel === 'canonical_evidence_ledger' && key === 'provider_reference' ? 'Evidence reference' : title}</dt><dd>{financialModel === 'canonical_evidence_ledger' && key === 'title' ? paymentReference(result.resource) : financialModel === 'canonical_evidence_ledger' && key === 'provider_reference' ? evidenceReference(result.resource[key]) : formatField(key, result.resource[key])}</dd></div>)}</dl></div></Card>
        <p className="core-note">Recorded evidence does not establish provider settlement.</p>
        {financialModel === 'canonical_evidence_ledger' && identity && verifyFresh && <CanonicalReconciliationActions key={`${currentScope}:actions`} detail={result} identity={identity} allowMutations={allowMutations} verifyFresh={verifyFresh}
          access={{request, permissions, actorId, principalId, authorityKey, financialModel, navigate, role}}
          onCompleted={refresh} />}
        {financialModel === 'transaction_journals' && identity && verifyFresh && <LegacyReconciliationActions key={`${currentScope}:legacy-actions`} detail={result} identity={identity} allowMutations={allowMutations} verifyFresh={verifyFresh}
          access={{request, permissions, actorId, principalId, authorityKey, financialModel, navigate, role}}
          onCompleted={refresh} />}
        {Object.entries(result.related).map(([name, page]) => <RelatedReconciliationRecords key={`${currentScope}:${name}`} name={name} initial={page} id={id} actorId={actorId} principalId={principalId} financialModel={financialModel} permissions={permissions} role={role} request={request} version={result.resource.version} groupVersion={result.groupVersion} />)}
      </>}
  </>;
}
