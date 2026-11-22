import {useEffect, useRef, useState} from 'react';
import {Button, Card} from '../../ui';
import {evidenceReference, formatField, label} from '../core/contracts';
import type {FeatureAccess} from '../core/types';
import {parseReconciliationDetail, type ReconciliationPage} from './contracts';

const relatedFields: readonly [string, string][] = [['id', 'Record'], ['status', 'Status'], ['outcome', 'Outcome'], ['amount_rwf', 'Amount'], ['kind', 'Kind'], ['reference', 'Reference'], ['created_at', 'Created']];

export function RelatedReconciliationRecords({ name, initial, id, actorId, principalId, financialModel, permissions, role, request, version, groupVersion }: {
  name: string; initial: ReconciliationPage; id: string; actorId: string; principalId: string | null;
  financialModel: FeatureAccess['financialModel']; permissions: readonly string[]; role: string; request: FeatureAccess['request']; version: unknown; groupVersion: number | null;
}) {
  const [page, setPage] = useState(initial);
  const [state, setState] = useState<'ready' | 'loading' | 'error'>('ready');
  const mounted = useRef(true);
  useEffect(() => { mounted.current = true; return () => { mounted.current = false; }; }, []);
  const go = async (offset: number) => {
    if (state !== 'ready') return;
    setState('loading');
    try {
      const query = new URLSearchParams({ [financialModel === 'canonical_evidence_ledger' ? 'relation' : 'related']: name, limit: String(page.limit), offset: String(offset) });
      const data = await request(`reconciliations/${id}?${query.toString()}`);
      const parsed = parseReconciliationDetail(data, financialModel, id, actorId, principalId, permissions, role, name, page.limit, offset);
      if (parsed.resource.version !== version || parsed.groupVersion !== groupVersion) throw new Error('The payment or group changed');
      if (mounted.current) { setPage(parsed.related[name]); setState('ready'); }
    } catch { if (mounted.current) setState('error'); }
  };
  const visibleFields = relatedFields.filter(([key]) => page.rows.some(row => key in row));
  return <Card><div className="core-detail"><h2>{label(name)}</h2>{state === 'error' && <p role="alert">This page could not be verified. Reopen the record before continuing.</p>}
    {page.rows.length === 0 ? <p>No records found.</p> : <div className="admin-table-wrap" role="region" aria-label={`${label(name)} records`} tabIndex={0}><table className="admin-table"><thead><tr>{visibleFields.map(([key, title]) => <th key={key} scope="col">{financialModel === 'canonical_evidence_ledger' && name === 'evidence' && key === 'reference' ? 'Evidence reference' : title}</th>)}</tr></thead><tbody>{page.rows.map(row => <tr key={String(row.id)}>{visibleFields.map(([key]) => <td key={key}>{financialModel === 'canonical_evidence_ledger' && name === 'evidence' && key === 'reference' ? evidenceReference(row[key]) : formatField(key, row[key])}</td>)}</tr>)}</tbody></table></div>}
    <div className="core-pager"><span>{page.total === 0 ? '0 records' : `${page.offset + 1}–${page.offset + page.rows.length} of ${page.total}`}</span><div><Button type="button" disabled={state !== 'ready' || page.offset === 0} onClick={() => void go(Math.max(0, page.offset - page.limit))}>Previous</Button><Button type="button" disabled={state !== 'ready' || page.nextOffset === null} onClick={() => void go(page.nextOffset!)}>Next</Button></div></div>
  </div></Card>;
}
