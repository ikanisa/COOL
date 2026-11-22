/* eslint-disable no-control-regex -- Reject control characters in recorded operator names. */
import {useEffect, useLayoutEffect, useMemo, useRef, useState, type FormEvent} from 'react';
import {Button, Card, ErrorState, LoadingState, PageHeader} from '../../ui';
import {isId} from './contracts';
import {currentLegacyPerson, type LegacyPersonSnapshot} from './legacyUserEdit';
import {LEGACY_LOGIN_IDENTITY_QUALIFIED, LEGACY_OPERATOR_LINK_QUALIFIED, lookupLegacyPersonAccess, parseLegacyPersonAccessIntent, restoreLegacyPersonAccess, retryLegacyPersonAccess, submitLegacyPersonAccess, type LegacyPersonAccessContext, type LegacyPersonAccessIntent, type LegacyPersonAccessPending} from './legacyPersonAccess';
import type {PendingIdentity} from './pendingAttempt';
import {usePendingIdentity} from './usePendingIdentity';
import type {FeatureAccess} from './types';
import './core.css';

interface OperatorChoice {id: string; email: string; name: string; role: string; publicId: string;}
export interface LegacyPersonAccessProps extends FeatureAccess {
  id: string; identity: PendingIdentity;
  allowContacts?: boolean; allowLoginType?: boolean; allowOperatorLinks?: boolean;
  verifyFresh?: () => Promise<boolean>;
}
function operators(value: Record<string, unknown>, identity: PendingIdentity): OperatorChoice[] {
  if (value.currentEmail !== identity.email || value.canManage !== true || !Array.isArray(value.members) || value.members.length > 1000) throw new Error('Operator list unavailable.');
  const choices: OperatorChoice[] = [], ids = new Set<string>(), publicIds = new Set<string>();
  for (const item of value.members) {
    if (!item || typeof item !== 'object' || Array.isArray(item)) throw new Error('Operator list unavailable.');
    const row = item as Record<string, unknown>;
    if (!isId(row.id) || ids.has(row.id) || typeof row.email !== 'string' || row.email.length > 254 || row.email !== row.email.trim().toLowerCase() || !/^\S+@\S+\.\S+$/.test(row.email) ||
        !['owner', 'admin', 'staff'].includes(String(row.role)) || !['active', 'invited', 'revoked'].includes(String(row.status)) ||
        typeof row.publicId !== 'string' || !/^\d{6}$/.test(row.publicId) || publicIds.has(row.publicId) ||
        !(row.displayName === null || typeof row.displayName === 'string' && row.displayName.length <= 120 && !/[\x00-\x1f\x7f]/.test(row.displayName))) throw new Error('Operator list unavailable.');
    ids.add(row.id); publicIds.add(row.publicId);
    if (row.status === 'active') choices.push({id: row.id, email: row.email, name: typeof row.displayName === 'string' ? row.displayName : '', role: String(row.role), publicId: row.publicId});
  }
  return choices;
}

/** Default-off candidate; operator links cannot commit until server qualification. */
export function LegacyPersonAccessPage({id, request, permissions, actorId, role, authorityKey, financialModel, navigate, identity,
  allowContacts = false, allowLoginType = false, allowOperatorLinks = false, verifyFresh}: LegacyPersonAccessProps) {
  const permissionKey = JSON.stringify([...new Set(permissions)].sort());
  const stableIdentity = usePendingIdentity(identity);
  const stablePermissions = useMemo<readonly string[]>(() => JSON.parse(permissionKey) as string[], [permissionKey]);
  const allowed = financialModel === 'transaction_journals' && role !== 'staff' && isId(id) && isId(actorId) && stableIdentity.id === actorId && stableIdentity.role === role &&
    ['users.read', 'users.manage', 'overview.read'].every(p => stablePermissions.includes(p) && stableIdentity.permissions.includes(p));
  const scope = JSON.stringify([authorityKey, financialModel, id, allowContacts, allowLoginType, allowOperatorLinks]), current = useRef(scope), contactsGate = useRef(allowContacts), typeGate = useRef(allowLoginType), linkGate = useRef(allowOperatorLinks), fresh = useRef(verifyFresh), busy = useRef(false);
  useLayoutEffect(() => {current.current = scope; return () => {current.current = '';};}, [scope]);
  useLayoutEffect(() => {contactsGate.current = allowContacts; typeGate.current = allowLoginType; linkGate.current = allowOperatorLinks; fresh.current = verifyFresh; return () => {contactsGate.current = false; typeGate.current = false; linkGate.current = false;};}, [allowContacts, allowLoginType, allowOperatorLinks, verifyFresh]);
  const context = useMemo<LegacyPersonAccessContext>(() => ({request, identity: stableIdentity, actorId, userId: id, permissions: stablePermissions, financialModel, enabled: false,
    contactsEnabled: allowContacts, loginTypeEnabled: allowLoginType, operatorLinkEnabled: allowOperatorLinks,
    isContactsEnabled: () => contactsGate.current, isLoginTypeEnabled: () => typeGate.current, isOperatorLinkEnabled: () => linkGate.current,
    verifyFresh: () => fresh.current?.() ?? Promise.resolve(false), isCurrent: () => current.current === scope && Date.parse(stableIdentity.expiresAt) > Date.now()}),
  [request, stableIdentity, actorId, id, stablePermissions, financialModel, allowContacts, allowLoginType, allowOperatorLinks, scope]);
  const [source, setSource] = useState<LegacyPersonSnapshot | null>(null), [pending, setPending] = useState<LegacyPersonAccessPending | null>(null), [loadedScope, setLoadedScope] = useState('');
  const [email, setEmail] = useState(''), [emailReason, setEmailReason] = useState(''), [phone, setPhone] = useState(''), [contactReason, setContactReason] = useState(''), [kind, setKind] = useState<'app' | 'direct'>('app'), [typeReason, setTypeReason] = useState('');
  const [choices, setChoices] = useState<OperatorChoice[]>([]), [operatorId, setOperatorId] = useState(''), [linkReason, setLinkReason] = useState('');
  const [review, setReview] = useState<LegacyPersonAccessIntent | null>(null), [revision, setRevision] = useState(''), [confirmed, setConfirmed] = useState(false), [retryAllowed, setRetryAllowed] = useState(false);
  const [state, setState] = useState<'loading' | 'ready' | 'checking' | 'sending' | 'success' | 'error'>('loading'), [message, setMessage] = useState('');
  useEffect(() => {
    if (!allowed) return; let live = true;
    restoreLegacyPersonAccess(context).then(async saved => {
      const canRead = saved.kind !== 'foreign' && (allowContacts || allowLoginType || allowOperatorLinks && role === 'owner');
      const person = canRead ? await currentLegacyPerson(context, true) : null;
      const team = person && allowOperatorLinks && role === 'owner' && stablePermissions.includes('admin_users.manage') && stableIdentity.permissions.includes('admin_users.manage') ? operators(await request('team'), stableIdentity) : [];
      if (live && context.isCurrent()) {
        setPending(saved); setSource(person); setChoices(team); setLoadedScope(scope); setState('ready');
        if (person) {setEmail(person.email ?? ''); setPhone(person.phone ?? ''); setKind(person.memberType === 'app' ? 'direct' : 'app'); setOperatorId(person.operatorId ?? '');}
        setMessage(saved.kind !== 'ready' ? 'A previous person change needs recovery. Check its original reference before continuing.' : !canRead ? 'Person access changes are not enabled for this workspace.' : '');
      }
    }).catch(() => {if (live && context.isCurrent()) {setLoadedScope(scope); setState('error'); setMessage('The person or recovery data could not be verified.');}});
    return () => {live = false;};
  }, [allowed, allowContacts, allowLoginType, allowOperatorLinks, context, request, role, scope, stableIdentity, stablePermissions]);
  const unresolved = pending && pending.kind !== 'ready' ? pending : null;
  const prepare = (event: FormEvent, change: 'contacts' | 'email' | 'type' | 'operator') => {
    event.preventDefault(); if (!source || pending?.kind !== 'ready' || busy.current || !context.isCurrent()) return;
    const input = change === 'contacts' ? {phone_e164: phone.trim() || null, expected_version: source.version, reason: contactReason.trim()} :
      change === 'email' ? {email: email.trim().toLowerCase() || null, expected_version: source.version, reason: emailReason.trim()} :
      change === 'type' ? {member_type: kind, expected_version: source.version, reason: typeReason.trim()} :
        {operator_admin_id: operatorId || null, expected_version: source.version, reason: linkReason.trim()};
    try {setReview(parseLegacyPersonAccessIntent(input, source)); setRevision(pending.revision); setConfirmed(false); setMessage('');}
    catch {setMessage('Check the selected change and enter a reason. App sign-in requires an email address.');}
  };
  const send = async () => {
    if (!review || !confirmed || !source || busy.current || !context.isCurrent() || unresolved?.kind === 'foreign' || unresolved?.kind === 'owned' && !retryAllowed ||
        'operator_admin_id' in review && !LEGACY_OPERATOR_LINK_QUALIFIED || ('member_type' in review || 'email' in review) && !LEGACY_LOGIN_IDENTITY_QUALIFIED) return;
    busy.current = true; setState('sending'); setMessage('');
    try {
      const result = unresolved?.kind === 'owned' ? await retryLegacyPersonAccess(context, unresolved) : await submitLegacyPersonAccess(context, review, source, revision);
      if (!context.isCurrent()) return;
      if (result.status === 'succeeded') {setPending(null); setState('success'); setMessage('The person was updated.');}
      else if (result.status === 'existing') {setPending(result.pending); setState('ready'); setMessage('A previous person change needs recovery.');}
      else {setPending({kind: 'owned', requestKey: result.requestKey, attempt: null}); setMessage(`The result is unconfirmed. Keep request reference ${result.requestKey} and check the original request.`); try {const saved = await restoreLegacyPersonAccess(context); if (context.isCurrent()) setPending(saved);} catch { /* Keep the reference visible. */ }}
    } catch {if (context.isCurrent()) {setMessage('The person or recovery data could not be verified. Check the original request before continuing.'); try {const saved = await restoreLegacyPersonAccess(context); if (context.isCurrent()) setPending(saved);} catch {if (context.isCurrent()) setState('error');}}}
    finally {busy.current = false; if (context.isCurrent()) {setState(previous => previous === 'sending' ? 'ready' : previous); setReview(null); setConfirmed(false); setRetryAllowed(false);}}
  };
  const check = async () => {
    if (!unresolved || unresolved.kind !== 'owned' || busy.current || !context.isCurrent()) return;
    busy.current = true; setState('checking'); setMessage(''); setRetryAllowed(false);
    try {const result = await lookupLegacyPersonAccess(context, unresolved); if (!context.isCurrent()) return;
      if (result.status === 'succeeded') {setPending(null); setState('success'); setMessage('The original person change was confirmed.');}
      else {setState('ready'); const retry = result.status === 'not_found' && result.retryAvailable;
        if (retry && unresolved.attempt && source) {setReview(parseLegacyPersonAccessIntent(unresolved.attempt.intent, source)); setConfirmed(false);}
        setRetryAllowed(retry); setMessage(result.status === 'not_found' ? 'The original request was not found. Review it before an identical retry.' : 'The original request is still unresolved.');}}
    catch {if (context.isCurrent()) {setState('ready'); setMessage('The original request could not be verified.');}}
    finally {busy.current = false;}
  };
  if (!allowed) return <ErrorState title="Person access unavailable" message="Your current account cannot review this person." />;
  if (loadedScope !== scope || state === 'loading') return <LoadingState label="Loading person" />;
  if (state === 'error') return <ErrorState title="Person access unavailable" message={message} />;
  const editable = !!source && source.status !== 'closed' && source.operatorId === null && !unresolved && state === 'ready';
  return <section className="admin-page">
    <PageHeader title="Person access" subtitle={source?.displayName ?? 'Recorded person'} actions={<Button variant="secondary" onClick={() => navigate(`/admin/users/${id}`)}>Back to person</Button>} />
    {message && <p role="status">{message}</p>}
    {unresolved?.kind === 'foreign' && <p>A different account must check the original person request.</p>}
    {unresolved?.kind === 'owned' && <Card><p>Request reference: {unresolved.requestKey}</p><Button onClick={check} disabled={state !== 'ready'}>Check original request</Button></Card>}
    {source && source.operatorId !== null && <p>This person is linked to an operator. Review their operator record before changing contact or sign-in details.</p>}
    {source && allowContacts && <Card><h2>Contact details</h2><p>App sign-in on this service uses an email code. The phone number is recorded contact information.</p>
      <form onSubmit={event => prepare(event, 'contacts')}><label>Phone contact<input className="admin-input" value={phone} maxLength={13} placeholder="+25078…" disabled={!editable} onChange={event => setPhone(event.target.value)} /></label>
        <label>Reason for contact change<textarea className="admin-input" value={contactReason} maxLength={1000} disabled={!editable} onChange={event => setContactReason(event.target.value)} /></label>
        <Button type="submit" disabled={!editable}>Review contact change</Button></form></Card>}
    {source && allowLoginType && <Card><h2>App sign-in</h2><p>Direct members do not have App sign-in. Changing to Direct ends existing member sessions. Sign-in changes are being prepared for this workspace.</p>
      <form onSubmit={event => prepare(event, 'email')}><label>Sign-in email<input className="admin-input" type="email" value={email} maxLength={254} disabled={!editable} onChange={event => setEmail(event.target.value)} /></label>
        <label>Reason for email change<textarea className="admin-input" value={emailReason} maxLength={1000} disabled={!editable} onChange={event => setEmailReason(event.target.value)} /></label>
        <Button type="submit" disabled={!editable}>Review email change</Button></form>
      <form onSubmit={event => prepare(event, 'type')}><label>New person type<select className="admin-input" value={kind} disabled={!editable} onChange={event => setKind(event.target.value as 'app' | 'direct')}><option value="app">App member</option><option value="direct">Direct member</option></select></label>
        <label>Reason for sign-in change<textarea className="admin-input" value={typeReason} maxLength={1000} disabled={!editable} onChange={event => setTypeReason(event.target.value)} /></label>
        <Button type="submit" disabled={!editable}>Review sign-in change</Button></form></Card>}
    {source && allowOperatorLinks && role === 'owner' && <Card><h2>Operator link</h2><p>Operator linking is being prepared for this workspace.</p>
      <form onSubmit={event => prepare(event, 'operator')}><label>Operator<select className="admin-input" value={operatorId} disabled={!!unresolved || source.status === 'closed'} onChange={event => setOperatorId(event.target.value)}><option value="">No operator</option>{choices.map(choice => <option key={choice.id} value={choice.id}>{choice.name || choice.email} · {choice.publicId} · {choice.role}</option>)}</select></label>
        <label>Reason for operator link<textarea className="admin-input" value={linkReason} maxLength={1000} disabled={!!unresolved || source.status === 'closed'} onChange={event => setLinkReason(event.target.value)} /></label>
        <Button type="submit" disabled={!!unresolved || source.status === 'closed'}>Review operator link</Button></form></Card>}
    {review && <Card><h2>Review change</h2><p>{'operator_admin_id' in review ? `Operator: ${choices.find(item => item.id === review.operator_admin_id)?.email ?? 'No operator'}` : 'member_type' in review ? `Person type: ${review.member_type}` : 'email' in review ? `Email: ${review.email ?? 'Not recorded'}` : `Phone contact: ${review.phone_e164 ?? 'Not recorded'}`}</p>
      <p>Reason: {review.reason}</p><label><input type="checkbox" checked={confirmed} onChange={event => setConfirmed(event.target.checked)} /> I reviewed the person and this change.</label>
      <Button onClick={send} disabled={!confirmed || state !== 'ready' || 'operator_admin_id' in review && !LEGACY_OPERATOR_LINK_QUALIFIED || ('member_type' in review || 'email' in review) && !LEGACY_LOGIN_IDENTITY_QUALIFIED}>Confirm change</Button>
      <Button variant="secondary" onClick={() => setReview(null)}>Cancel</Button></Card>}
  </section>;
}
