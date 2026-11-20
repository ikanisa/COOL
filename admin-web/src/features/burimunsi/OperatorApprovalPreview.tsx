import {useRef, useState, type FormEvent} from 'react';
import {Button, Card} from '../../ui';
import type {BuriDirectory} from './contracts';
import {BURI_CAPABILITIES, prepareBuriApproval, type BuriApprovalDraft} from './operatorPreparation';

import {applyBuriApproval, canApplyBuriApproval, checkBuriApproval, type BuriApprovalResult} from './operatorApproval';
import type {NativeRevokeContext} from './nativeRevocation';

export function OperatorPreparation({directory, blocked, context, onRecorded}: {
  directory: BuriDirectory; blocked: boolean; context?: NativeRevokeContext; onRecorded?: (requestId: string) => void;
}) {
  const [principal, setPrincipal] = useState(''), [phone, setPhone] = useState(''), [role, setRole] = useState('staff');
  const [active, setActive] = useState(true), [capabilities, setCapabilities] = useState<string[]>(['records.read']);
  const [review, setReview] = useState<{directory: BuriDirectory; draft: BuriApprovalDraft} | null>(null), [error, setError] = useState('');
  const [working, setWorking] = useState(false), [result, setResult] = useState<BuriApprovalResult | null>(null);
  const inFlight = useRef(false);
  const canWrite = context?.enabled === true && directory.approvalContract === 2;
  const needsRecovery = result?.status === 'unknown' || result?.status === 'not_found' || result?.status === 'blocked';
  async function run(action: () => Promise<BuriApprovalResult>) {
    if (!context || inFlight.current || !context.isCurrent()) return;
    inFlight.current = true;
    setWorking(true);
    setError('');
    try {
      const next = await action();
      if (!context.isCurrent()) return;
      setResult(next);
      if (next.status === 'recorded') onRecorded?.(next.requestId);
    } catch (failure) {
      if (context.isCurrent()) setError(failure instanceof Error ? failure.message : 'The original approval could not be verified.');
    } finally {
      inFlight.current = false;
      setWorking(false);
    }
  }
  const choices = [...new Map([...directory.approvals.map(item => [item.operator.principalId, item.operator] as const), ...directory.team.map(item => [item.principalId, item] as const)]).values()];
  const existing = directory.approvals.find(item => item.operator.principalId === principal);
  const current = choices.find(item => item.principalId === principal);
  const invalidate = () => {setReview(null); setError('');};
  const select = (value: string) => {
    const approval = directory.approvals.find(item => item.operator.principalId === value);
    setPrincipal(value); setPhone(approval?.phone ?? ''); setRole(approval?.role ?? 'staff'); setActive(approval?.active ?? true);
    setCapabilities(approval ? [...approval.capabilities] : ['records.read']); invalidate();
  };
  const submit = (event: FormEvent) => {
    event.preventDefault(); invalidate();
    try {setReview({directory, draft: prepareBuriApproval(directory, principal, {phone, role, capabilities, active})});}
    catch (failure) {setError(failure instanceof Error ? failure.message : 'The access preview could not be prepared.');}
  };
  return <Card><div className="core-detail"><h2>Prepare operator access</h2>
    {!canWrite && <p>This group is available for access review. Guarded approval is currently unavailable.</p>}
    {blocked && <p role="alert">Check the original group request before preparing another change.</p>}
    {!directory.configured && <p>Prepare this group before reviewing access.</p>}
    <form className="core-edit-form" onSubmit={submit}>
      <fieldset disabled={working || needsRecovery || blocked || !directory.configured}>
        <label>Collect account<select className="admin-input" value={principal} onChange={event => select(event.target.value)}><option value="">Select an account</option>{choices.map(item => <option key={item.principalId} value={item.principalId}>{item.displayName || item.email} · {item.email}</option>)}</select></label>
        {current && <>
          <label>Login phone<input className="admin-input" value={phone} inputMode="tel" autoComplete="off" onChange={event => {setPhone(event.target.value); invalidate();}} /></label>
          <label>BuriMunsi role<select className="admin-input" value={role} disabled={!!existing} onChange={event => {setRole(event.target.value); setCapabilities(['records.read']); invalidate();}}><option value="staff">Staff</option>{(current.role !== 'staff' || existing?.role === 'admin') && <option value="admin">Administrator</option>}</select></label>
          <label>Access status<select className="admin-input" value={active ? 'enabled' : 'disabled'} disabled={!existing} onChange={event => {setActive(event.target.value === 'enabled'); invalidate();}}><option value="enabled">Enabled</option><option value="disabled">Disabled</option></select></label>
          <fieldset><legend>Capabilities</legend>{BURI_CAPABILITIES.map(([name, label], index) => <label key={name}><input type="checkbox" checked={capabilities.includes(name)} disabled={name === 'records.read' || role === 'staff' && index > 2} onChange={event => {setCapabilities(previous => event.target.checked ? [...previous, name] : previous.filter(item => item !== name)); invalidate();}} /> {label}</label>)}</fieldset>
        </>}
        <Button type="submit" disabled={!current}>Review access</Button>
      </fieldset>
    </form>
    {error && <p role="alert">{error}</p>}
    {context && <Button type="button" disabled={working} onClick={() => void run(() => checkBuriApproval(context))}>Check saved approval</Button>}
    {result?.status === 'ready' && <p role="status">There is no saved approval for this group.</p>}
    {result?.status === 'blocked' && <p role="status">Resolve the other saved group request before applying an approval.</p>}
    {(result?.status === 'unknown' || result?.status === 'not_found') && <p role="status">
      The approval is unconfirmed. Keep the original request <code>{result.requestId}</code>.
    </p>}
    {result?.status === 'not_found' && result.canRetry && canWrite && context &&
      <Button type="button" disabled={working} onClick={() => void run(() => checkBuriApproval(context, result.requestId))}>Retry original approval</Button>}
    {review?.directory === directory && <section aria-label="Access preview"><h3>Access preview</h3><p>Nothing has been sent or changed.</p><dl>
      <div><dt>Group reference</dt><dd>{review.draft.collectionId}</dd></div><div><dt>Account</dt><dd>{review.draft.operator.email}</dd></div><div><dt>Person reference</dt><dd>{review.draft.operator.principalId}</dd></div>
      <div><dt>Login phone</dt><dd>{review.draft.phone}</dd></div><div><dt>Role</dt><dd>{review.draft.role}</dd></div>
      <div><dt>Status</dt><dd>{review.draft.active ? 'Enabled' : 'Disabled'}</dd></div><div><dt>Capabilities</dt><dd>{review.draft.capabilities.join(', ')}</dd></div>
      <div><dt>Current approval version</dt><dd>{review.draft.expectedVersion}</dd></div>
    </dl>
    {canWrite && context && canApplyBuriApproval(review.draft) &&
      <Button type="button" disabled={blocked || working || needsRecovery}
        onClick={() => void run(() => applyBuriApproval(context, review.draft))}>Confirm operator approval</Button>}
    </section>}
  </div></Card>;
}
