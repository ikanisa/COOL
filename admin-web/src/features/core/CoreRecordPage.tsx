import { useEffect, useState } from 'react';
import { Button, Card, ErrorState, LoadingState, PageHeader } from '../../ui';
import { LegacyTransactionActions } from '../legacy-transactions/LegacyTransactionActions';
import { OperatorNotes } from '../notes/OperatorNotes';
import { containsControl, formatField, isId, isObject, parseCoreRow, paymentReference } from './contracts';
import { coreRecordActions } from './coreRecordActions';
import { CoreRelatedSection, MembershipRecoveries } from './CoreRelatedRecords';
import type { PendingIdentity } from './pendingAttempt';
import { relatedPage, validateRelated } from './relatedRecordContract';
import type { CoreArea, FeatureAccess } from './types';
import { AREA_TITLES, CORE_PERMISSIONS } from './types';
import './core.css';

type RecordProps = FeatureAccess & { area: CoreArea; id: string; returnTo?: string | null; allowMutations?: boolean; identity?: PendingIdentity; isCurrent?: () => boolean };

const fields: Record<CoreArea, readonly [string, string][]> = {
  groups: [['title', 'Group'], ['slug', 'Slug'], ['collection_type', 'Type'], ['purpose_label', 'Purpose'], ['visibility', 'Visibility'], ['active_members', 'Members'], ['status', 'Status'], ['created_at', 'Created']],
  users: [['public_id', 'Collect ID'], ['display_name', 'Name on MoMo'], ['member_type', 'Type'], ['whatsapp_number', 'WhatsApp'], ['email', 'Email'], ['momo_provider', 'MoMo provider'], ['momo_number', 'MoMo number'], ['momo_pay_code', 'MoMo code'], ['total_contributed_rwf', 'Recorded contributions'], ['status', 'Status']],
  members: [['public_id', 'Collect ID'], ['display_name', 'Name on MoMo'], ['member_type', 'Type'], ['whatsapp_number', 'WhatsApp'], ['momo_provider', 'MoMo provider'], ['momo_number', 'MoMo number'], ['momo_pay_code', 'MoMo code'], ['total_contributed_rwf', 'Recorded contributions'], ['status', 'Status']],
  payees: [['title', 'Payee'], ['group_name', 'Group'], ['network', 'Provider'], ['momo_number_or_code', 'MoMo number / code'], ['status', 'Status']],
  transactions: [['title', 'Reference'], ['group_name', 'Group'], ['payee_label', 'Receiver'], ['amount_rwf', 'Recorded amount'], ['allocated_amount_rwf', 'Allocated amount'], ['status', 'Evidence status'], ['settlement_status', 'Settlement'], ['observed_at', 'Observed']],
  ledgers: [['title', 'Record'], ['group_name', 'Group'], ['signed_amount_rwf', 'Signed amount'], ['debit_rwf', 'Debit'], ['credit_rwf', 'Credit'], ['status', 'Status'], ['created_at', 'Created']],
};

function safeReturn(area: CoreArea, raw?: string | null): string {
  if (!raw || raw.length > 2000 || containsControl(raw, true) || raw.includes('\\') || raw.includes('#') || !raw.startsWith('/') || raw.startsWith('//')) return `/admin/${area}`;
  try {
    const url = new URL(raw, 'https://collect.invalid');
    if (url.origin !== 'https://collect.invalid' || url.pathname !== `/admin/${area}` || url.hash) return `/admin/${area}`;
    const keys = [...url.searchParams.keys()];
    if (keys.some(key => !['search', 'status', 'sort', 'page'].includes(key)) || new Set(keys).size !== keys.length) return `/admin/${area}`;
    return `${url.pathname}${url.search}`;
  } catch { return `/admin/${area}`; }
}

export function CoreRecordPage({ area, id, request, permissions, actorId, principalId, role, authorityKey, financialModel, navigate, returnTo, allowMutations = false, identity, isCurrent }: RecordProps) {
  const allowed = permissions.includes(CORE_PERMISSIONS[area]);
  const [detail, setDetail] = useState<Record<string, unknown> | null>(null);
  const [detailScope, setDetailScope] = useState('');
  const currentScope = JSON.stringify([authorityKey, area, financialModel, id]);
  const [state, setState] = useState<'loading' | 'ready' | 'error'>('loading');
  const [retry, setRetry] = useState(0);
  const resource = area === 'members' ? 'users' : area === 'ledgers' && financialModel === 'transaction_journals' ? 'journals' : area;
  useEffect(() => {
    if (!allowed || !isId(id)) return;
    const controller = new AbortController(); let active = true;
    request(`operations/${resource}/${id}`, { signal: controller.signal }).then(data => {
      if (data.resource_type !== resource || data.current_actor_id !== actorId || typeof data.can_manage !== 'boolean' || !isObject(data.resource) || !isObject(data.related)) throw new Error('Invalid detail');
      if (financialModel === 'canonical_evidence_ledger') {
        if (data.contract_version !== 2 || data.model !== financialModel) throw new Error('Invalid model');
        parseCoreRow(area === 'members' ? 'users' : area, financialModel, data.resource);
      } else if (data.contract_version !== undefined || data.model !== undefined || (data.resource.id !== id && !(resource === 'users' && data.resource.operator_admin_id === id))) throw new Error('Invalid detail');
      if (data.resource.id !== id && !(resource === 'users' && data.resource.operator_admin_id === id)) throw new Error('Invalid identity');
      validateRelated(data, resource);
      if (active) { setDetail(data); setDetailScope(currentScope); setState('ready'); }
    }).catch(() => { if (active) { setDetailScope(currentScope); setState('error'); } });
    return () => { active = false; controller.abort(); };
  }, [allowed, id, resource, request, actorId, authorityKey, financialModel, area, currentScope, retry]);
  const back = safeReturn(area, returnTo);
  const {actions, membershipRecovery, membershipWrite, journalRecovery, journalWrite} = coreRecordActions({
    area, role, permissions, financialModel, allowMutations, actorId, id, resource,
    current: detailScope === currentScope && state === 'ready', detail, identity,
  });
  const reload = () => {setState('loading'); setRetry(value => value + 1);};
  return <>
    <PageHeader title={AREA_TITLES[area]} subtitle="Review this record and its related information." actions={<>
      <Button type="button" onClick={() => navigate(back)}>Back to {AREA_TITLES[area].toLowerCase()}</Button>
      {actions.map(action => <Button key={action.path} type="button" variant={action.variant} onClick={() => navigate(action.path)}>{action.label}</Button>)}
    </>} />
    {!allowed ? <ErrorState title="Access unavailable" message="Your account does not have permission to view this record." /> :
      !isId(id) ? <ErrorState message="Select a valid record." /> :
      state === 'loading' || detailScope !== currentScope ? <LoadingState label="Loading record" /> :
      state === 'error' || !detail ? <ErrorState message="The record could not be verified or the service is unavailable." onRetry={reload} /> : <>
        <Card><div className="core-detail"><h2>Record details</h2><dl>{fields[area].filter(([key]) => (detail.resource as Record<string, unknown>)[key] !== undefined).map(([key, title]) => <div key={key}><dt>{title}</dt><dd>{area === 'transactions' && financialModel === 'canonical_evidence_ledger' && key === 'title' ? paymentReference(detail.resource as Record<string, unknown>) : formatField(key, (detail.resource as Record<string, unknown>)[key])}</dd></div>)}</dl></div></Card>
        {area === 'transactions' && <p className="core-note">Recorded evidence does not establish provider settlement.</p>}
        {area === 'transactions' && financialModel === 'transaction_journals' && identity && identity.id === actorId && identity.role === role && isCurrent &&
          (['add', 'review'] as const).map(mode => <LegacyTransactionActions key={`${currentScope}:${mode}`} id={id} mode={mode} request={request} identity={identity}
            permissions={permissions} financialModel={financialModel} authorityKey={authorityKey} isCurrent={isCurrent} allowMutations={allowMutations}
            onUpdated={reload} />)}
        {membershipRecovery && identity && identity.id === actorId && identity.role === role && identity.permissions.includes('users.manage') && <MembershipRecoveries identity={identity} scope={currentScope} resource={resource} id={id} navigate={navigate} />}
        {financialModel === 'canonical_evidence_ledger' && identity && identity.role === role && (resource === 'groups' || resource === 'users') &&
          <OperatorNotes key={`${currentScope}:notes`} request={request} permissions={permissions} authorityKey={authorityKey} area={resource}
            id={id} identity={identity} actorId={actorId} principalId={principalId} allowMutations={allowMutations} />}
        {Object.entries(detail.related as Record<string, unknown>).map(([name, values]) => <CoreRelatedSection key={`${currentScope}:${name}`} name={name} initial={values as Record<string, unknown>[]} page={relatedPage(detail, name, values as unknown[])} resource={resource} id={id} actorId={actorId} financialModel={financialModel} request={request} version={(detail.resource as Record<string, unknown>).version} membershipRecovery={membershipRecovery} membershipWrite={membershipWrite} accountRead={permissions.includes('ledger.read')} journalRecovery={journalRecovery} journalWrite={journalWrite} navigate={navigate} />)}
      </>}
  </>;
}
