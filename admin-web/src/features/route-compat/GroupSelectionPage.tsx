import {useLayoutEffect, useRef, useState, type FormEvent} from 'react';
import {Button, Card, EmptyState, ErrorState, Field, PageHeader} from '../../ui';
import {containsControl, isId, isObject, isSafeCount, parseCoreRow} from '../core/contracts';
import type {FeatureAccess, FinancialModel} from '../core/types';

type GroupChoice = {id: string; label: string};
type Action = 'member' | 'payee';

function parseGroups(value: unknown, model: FinancialModel): GroupChoice[] {
  if (!isObject(value) || !Array.isArray(value.rows) || value.rows.length > 100) throw new Error('Invalid group results');
  if (model === 'canonical_evidence_ledger') {
    if (Object.keys(value).length !== 6 || value.contract_version !== 2 || value.model !== model || value.kind !== 'groups' ||
        value.group_id !== null || !isSafeCount(value.total) || value.rows.length !== Math.min(100, value.total)) throw new Error('Invalid group results');
  } else if (Object.keys(value).length !== 1) throw new Error('Invalid group results');
  const rows = value.rows.map((raw): GroupChoice => {
    if (!isObject(raw) || !isId(raw.id) || typeof raw.label !== 'string' || !raw.label.trim() || raw.label.length > 300 ||
        containsControl(raw.label) || !isSafeCount(raw.version) || raw.version < 1) throw new Error('Invalid group');
    if (model === 'canonical_evidence_ledger') {
      const group = parseCoreRow('groups', model, raw);
      if (raw.label !== raw.name || raw.label !== group.title || group.status !== 'active') throw new Error('Invalid group');
    } else if (Object.keys(raw).sort().join(',') !== 'id,label,version') throw new Error('Invalid group');
    return {id: raw.id, label: raw.label};
  });
  if (new Set(rows.map(row => row.id)).size !== rows.length) throw new Error('Duplicate groups');
  return rows;
}

/** Select a verified group before entering an existing, separately gated workflow. */
export function GroupSelectionPage({action, request, permissions, financialModel, authorityKey, navigate, isCurrent}: FeatureAccess & {action: Action; isCurrent: () => boolean}) {
  const [search, setSearch] = useState(''), [rows, setRows] = useState<GroupChoice[] | null>(null), [error, setError] = useState(''), [busy, setBusy] = useState(false);
  const generation = useRef(0), active = useRef(false), controller = useRef<AbortController | null>(null);
  useLayoutEffect(() => {active.current = true; return () => {active.current = false; controller.current?.abort();};}, [authorityKey, action, financialModel]);
  const allowed = permissions.includes('collections.read') && (action !== 'payee' || financialModel === 'transaction_journals');
  const title = action === 'member' ? 'Add group member' : 'Add payee';
  const find = async (event: FormEvent) => {
    event.preventDefault(); const query = search.trim();
    if (!allowed || !active.current || !isCurrent() || query.length > 200 || containsControl(query)) return;
    controller.current?.abort(); const next = new AbortController(); controller.current = next;
    const run = ++generation.current; setRows(null); setError(''); setBusy(true);
    try {
      const params = new URLSearchParams({kind: 'groups', search: query, limit: '100'});
      const choices = parseGroups(await request(`operations/lookups?${params}`, {signal: next.signal}), financialModel);
      if (active.current && isCurrent() && run === generation.current && !next.signal.aborted) setRows(choices);
    } catch {
      if (active.current && isCurrent() && run === generation.current && !next.signal.aborted) setError('Groups could not be verified. Search again.');
    } finally {if (active.current && isCurrent() && run === generation.current) setBusy(false);}
  };
  return <><PageHeader title={title} subtitle="Select an active group to continue." />
    {!allowed ? <ErrorState title="Group selection unavailable" message={financialModel === 'canonical_evidence_ledger' && action === 'payee' ?
      'Separate payee creation is unavailable for this workspace.' : 'Your account cannot view groups for this action.'} /> : <Card>
      <form onSubmit={event => void find(event)}><Field label="Search groups" htmlFor="select-group-search">
        <input className="admin-input" id="select-group-search" value={search} maxLength={200} onChange={event => {
          generation.current++; controller.current?.abort(); setBusy(false); setRows(null); setError(''); setSearch(event.target.value);
        }} />
      </Field><Button type="submit" loading={busy}>Search</Button></form>
      {error && <p role="alert">{error}</p>}
      {rows?.length === 0 && <EmptyState title="No active groups found" description="Change your search and try again." />}
      {rows && rows.length > 0 && <ul>{rows.map(row => <li key={row.id}>{row.label}{' '}
        <Button type="button" onClick={() => {if (active.current && isCurrent()) navigate(`/admin/groups/${row.id}/${action === 'member' ? 'members' : 'payees'}/new`);}}>Select {row.label}</Button>
      </li>)}</ul>}
    </Card>}
  </>;
}
