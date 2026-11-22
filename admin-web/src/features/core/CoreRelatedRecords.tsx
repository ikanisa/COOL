import { useEffect, useRef, useState } from 'react';
import { Button, Card } from '../../ui';
import { formatField, isId, isObject, isSafeCount, label } from './contracts';
import { listPending, type PendingAttempt, type PendingIdentity } from './pendingAttempt';
import {usePendingIdentity} from './usePendingIdentity';
import { relatedPage, validateRelated, type RelatedPage } from './relatedRecordContract';
import type { FeatureAccess, FinancialModel } from './types';

const relationFields: readonly [string, string][] = [['id', 'Record'], ['public_id', 'Collect ID'], ['group_title', 'Group'], ['title', 'Title'], ['name', 'Name'], ['display_name', 'Name on MoMo'], ['label', 'Label'], ['code', 'Code'], ['role', 'Role'], ['status', 'Status'], ['network', 'Provider'], ['momo_number_or_code', 'MoMo number / code'], ['amount_rwf', 'Amount'], ['created_at', 'Created']];

export function CoreRelatedSection({ name, initial, page, resource, id, actorId, financialModel, request, version, membershipRecovery, membershipWrite, accountRead, journalRecovery, journalWrite, navigate }: {
  name: string; initial: Record<string, unknown>[]; page: RelatedPage | null; resource: string; id: string; actorId: string;
  financialModel: FinancialModel; request: FeatureAccess['request']; version: unknown; membershipRecovery: boolean; membershipWrite: boolean; accountRead: boolean; journalRecovery: boolean; journalWrite: boolean; navigate: FeatureAccess['navigate'];
}) {
  const [rows, setRows] = useState(initial);
  const [currentPage, setCurrentPage] = useState(page);
  const [state, setState] = useState<'ready' | 'loading' | 'error'>('ready');
  const mounted = useRef(true);
  useEffect(() => { mounted.current = true; return () => { mounted.current = false; }; }, []);
  const go = async (offset: number) => {
    if (!currentPage || state === 'loading') return;
    setState('loading');
    try {
      const query = new URLSearchParams({ relation: name, limit: String(currentPage.limit), offset: String(offset) });
      const data = await request(`operations/${resource}/${id}?${query.toString()}`);
      if (data.resource_type !== resource || data.current_actor_id !== actorId || !isObject(data.resource) ||
          (data.resource.id !== id && !(resource === 'users' && data.resource.operator_admin_id === id)) || data.resource.version !== version ||
          (financialModel === 'canonical_evidence_ledger' && (data.contract_version !== 2 || data.model !== financialModel))) throw new Error('The record changed');
      validateRelated(data, resource, name);
      const related = data.related as Record<string, unknown>;
      const nextRows = related[name] as Record<string, unknown>[];
      const nextPage = relatedPage(data, name, nextRows);
      if (!nextPage || nextPage.offset !== offset || nextPage.limit !== currentPage.limit) throw new Error('Invalid related page');
      if (mounted.current) { setRows(nextRows); setCurrentPage(nextPage); setState('ready'); }
    } catch { if (mounted.current) setState('error'); }
  };
  const visibleFields = relationFields.filter(([key]) => rows.some(row => key in row));
  const membershipActions = name === 'memberships' && membershipRecovery;
  const accountActions = name === 'accounts' && resource === 'groups' && financialModel === 'transaction_journals' && accountRead;
  const allocationActions = name === 'allocations' && resource === 'transactions' && financialModel === 'transaction_journals' && journalRecovery;
  return <Card><div className="core-detail"><h2>{label(name)}</h2>{state === 'error' && <p role="alert">This page could not be verified. Reopen the record before continuing.</p>}
    {rows.length === 0 ? <p>No records found.</p> : <div className="admin-table-wrap" role="region" aria-label={`${label(name)} records`} tabIndex={0}><table className="admin-table"><thead><tr>{visibleFields.map(([key, title]) => <th scope="col" key={key}>{title}</th>)}{(membershipActions || accountActions || allocationActions) && <th scope="col">Action</th>}</tr></thead><tbody>{rows.map((row, index) => <tr key={typeof row.id === 'string' ? row.id : index}>{visibleFields.map(([key]) => <td key={key}>{formatField(key, row[key])}</td>)}{membershipActions && <td>{isId(row.group_id) && isId(row.user_id) && <Button type="button" onClick={() => navigate(`/admin/groups/${row.group_id}/members/${row.user_id}/edit`)}>{membershipWrite && (financialModel === 'transaction_journals' ? ['admin', 'receiver', 'member', 'contributor', 'viewer'].includes(String(row.role)) : ['member', 'admin'].includes(String(row.role)) && row.account_status === 'active') ? 'Edit membership' : 'Check membership request'}</Button>}</td>}{accountActions && <td>{isId(row.id) && <Button type="button" onClick={() => navigate(`/admin/ledger-accounts/${row.id}`)}>View account</Button>}</td>}{allocationActions && <td>{isId(row.id) && <Button type="button" onClick={() => navigate(`/admin/transactions/${id}/allocations/${row.id}/journal/new`)}>{journalWrite && isSafeCount(row.amount_rwf) && row.amount_rwf > 0 ? 'Review linked draft' : 'Check linked journal request'}</Button>}</td>}</tr>)}</tbody></table></div>}
    {currentPage && <div className="core-pager"><span>{currentPage.total === 0 ? '0 records' : `${currentPage.offset + 1}–${currentPage.offset + rows.length} of ${currentPage.total}`}</span><div><Button type="button" disabled={state !== 'ready' || currentPage.offset === 0} onClick={() => void go(Math.max(0, currentPage.offset - currentPage.limit))}>Previous</Button><Button type="button" disabled={state !== 'ready' || currentPage.nextOffset === null} onClick={() => void go(currentPage.nextOffset!)}>Next</Button></div></div>}
  </div></Card>;
}

export function MembershipRecoveries({ identity, scope, resource, id, navigate }: { identity: PendingIdentity; scope: string; resource: string; id: string; navigate: FeatureAccess['navigate'] }) {
  const stableIdentity = usePendingIdentity(identity);
  const [result, setResult] = useState<{scope: string; entries: PendingAttempt[]; error: boolean} | null>(null);
  useEffect(() => {
    let live = true;
    listPending(stableIdentity, 'operating-updatemembership', 'users.manage').then(entries => {
      for (const entry of entries) {
        const pair = entry.resource_id.split(':');
        if (pair.length !== 2 || !isId(pair[0]) || !isId(pair[1]) || !isSafeCount(entry.intent.expected_version) || entry.intent.expected_version < 1) throw new Error('Invalid membership recovery');
      }
      if (live) setResult({scope, entries: entries.filter(entry => {
        const [groupId, userId] = entry.resource_id.split(':');
        return resource === 'groups' ? groupId === id : userId === id;
      }), error: false});
    }).catch(() => { if (live) setResult({scope, entries: [], error: true}); });
    return () => { live = false; };
  }, [stableIdentity, scope, resource, id]);
  if (!result || result.scope !== scope) return null;
  if (result.error) return <Card><div className="core-detail"><p role="alert">Membership recovery data could not be verified. Check the original request before another change.</p></div></Card>;
  if (!result.entries.length) return null;
  return <Card><div className="core-detail"><h2>Pending membership requests</h2>{result.entries.map(entry => {
    const [groupId, userId] = entry.resource_id.split(':');
    return <div key={entry.request_key}><p>Group {groupId} · Member {userId} · Request <code>{entry.request_key}</code></p><Button type="button" onClick={() => navigate(`/admin/groups/${groupId}/members/${userId}/edit`)}>Check pending membership change</Button></div>;
  })}</div></Card>;
}
