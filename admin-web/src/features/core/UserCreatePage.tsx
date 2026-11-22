import { useEffect, useLayoutEffect, useRef, useState, type FormEvent } from 'react';
import { Button, Card, ErrorState, LoadingState, PageHeader } from '../../ui';
import { containsControl, isId, isObject } from './contracts';
import { readPending, retainPending } from './pendingAttempt';
import {clearOriginalAttempt, lookupCanonicalMutation, matchesCanonicalReceipt} from './canonicalMutation';
import {usePendingIdentity} from './usePendingIdentity';
import type { PendingAttempt, PendingIdentity } from './pendingAttempt';
import type { FeatureAccess } from './types';
import { LegacyUserCreatePage } from './LegacyUserCreatePage';
import './core.css';

export interface UserCreateProps extends FeatureAccess {
  identity: PendingIdentity;
  allowMutations?: boolean;
  verifyFresh: () => Promise<boolean>;
}
const FAMILY = 'operating-createuser', RESOURCE = 'new', PERMISSION = 'users.manage';
const COMMON = ['display_name', 'member_type', 'momo_provider', 'momo_number', 'momo_pay_code', 'email', 'status', 'reason'];
type Draft = { display_name: string; member_type: 'app' | 'direct'; momo_provider: string; momo_number: string; momo_pay_code: string; email: string; phone_e164: string; status: string; reason: string };
const initialDraft: Draft = { display_name: '', member_type: 'app', momo_provider: 'mtn_momo', momo_number: '', momo_pay_code: '', email: '', phone_e164: '', status: 'active', reason: '' };
function intent(value: unknown): Record<string, unknown> {
  if (!isObject(value)) throw new Error('Invalid person details');
  const fields = value.member_type === 'app' ? [...COMMON, 'phone_e164'] : COMMON;
  if (Object.keys(value).length !== fields.length || !fields.every(key => key in value) ||
      !['app', 'direct'].includes(String(value.member_type)) || typeof value.display_name !== 'string' || value.display_name.trim().length < 2 || value.display_name.length > 120 || containsControl(value.display_name) ||
      !['mtn_momo', 'airtel_money'].includes(String(value.momo_provider)) || typeof value.momo_number !== 'string' ||
      (value.momo_number !== '' && !/^07[2389]\d{7}$/.test(value.momo_number)) || typeof value.momo_pay_code !== 'string' ||
      (value.momo_pay_code !== '' && !/^\d{4,9}$/.test(value.momo_pay_code)) ||
      !(value.email === null || typeof value.email === 'string' && value.email.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value.email)) ||
      (value.member_type === 'app' && !(value.phone_e164 === null || typeof value.phone_e164 === 'string' && /^\+2507[2389]\d{7}$/.test(value.phone_e164))) ||
      (value.member_type === 'app' && value.email === null && value.phone_e164 === null) || (value.member_type === 'direct' && value.momo_number === '') ||
      !['active', 'suspended'].includes(String(value.status)) || typeof value.reason !== 'string' || value.reason.trim().length < 8 || value.reason.length > 500) throw new Error('Invalid person details');
  return value;
}

export function UserCreatePage(props: UserCreateProps) {
  return props.financialModel === 'transaction_journals' ? <LegacyUserCreatePage {...props} /> : <CanonicalUserCreatePage {...props} />;
}

/** Canonical person creation is opt-in until the migration is qualified. */
function CanonicalUserCreatePage({ request, permissions, actorId, principalId, role, authorityKey, financialModel, navigate, identity, allowMutations = false, verifyFresh }: UserCreateProps) {
  const stableIdentity = usePendingIdentity(identity);
  const allowed = financialModel === 'canonical_evidence_ledger' && role !== 'staff' && permissions.includes(PERMISSION) && stableIdentity.permissions.includes(PERMISSION) &&
    stableIdentity.id === actorId && stableIdentity.role === role && typeof principalId === 'string' && isId(principalId);
  const [draft, setDraft] = useState<Draft>(initialDraft), [pending, setPending] = useState<PendingAttempt | null>(null);
  const [review, setReview] = useState<Record<string, unknown> | null>(null), [retryAllowed, setRetryAllowed] = useState(false);
  const [state, setState] = useState<'loading' | 'ready' | 'sending' | 'checking' | 'success' | 'error'>('loading');
  const [scopeLoaded, setScopeLoaded] = useState(''), [message, setMessage] = useState(''), [createdId, setCreatedId] = useState('');
  const current = useRef(authorityKey), gate = useRef(allowMutations), busy = useRef(false);
  useLayoutEffect(() => { current.current = authorityKey; return () => { current.current = ''; }; }, [authorityKey]);
  useLayoutEffect(() => { gate.current = allowMutations; return () => { gate.current = false; }; }, [allowMutations]);
  const scope = JSON.stringify([authorityKey, financialModel]);
  const active = () => current.current === authorityKey && Date.parse(stableIdentity.expiresAt) > Date.now();
  useEffect(() => {
    if (!allowed) return;
    let live = true;
    readPending(stableIdentity, FAMILY, RESOURCE).then(saved => {
      if (saved && saved.permission !== PERMISSION) throw new Error('Invalid recovery');
      if (!live || current.current !== authorityKey) return;
      setPending(saved); setScopeLoaded(scope); setState('ready');
      if (saved) setMessage('A previous person creation needs recovery. Check its original request before continuing.');
      else if (!allowMutations) setMessage('Person creation is not enabled for this workspace.');
    }).catch(() => { if (live) { setScopeLoaded(scope); setState('error'); setMessage('The recovery record could not be verified.'); } });
    return () => { live = false; };
  }, [allowed, allowMutations, stableIdentity, authorityKey, scope]);

  const makeReview = (event: FormEvent) => {
    event.preventDefault(); if (!allowMutations || pending || state !== 'ready' || !active()) return;
    try {
      const body = intent({ display_name: draft.display_name.trim(), member_type: draft.member_type, momo_provider: draft.momo_provider,
        momo_number: draft.momo_number.trim(), momo_pay_code: draft.momo_pay_code.trim(), email: draft.member_type === 'app' ? draft.email.trim().toLowerCase() || null : null,
        ...(draft.member_type === 'app' ? { phone_e164: draft.phone_e164.trim() || null } : {}), status: draft.status, reason: draft.reason.trim() });
      setReview(body); setMessage('');
    } catch { setMessage('Check the recorded name, member type, payment details and reason. App members need an email or Rwanda login number; Direct members need a recorded MoMo number.'); }
  };
  const send = async (body: Record<string, unknown>, key: string) => {
    if (!allowed || !allowMutations || !principalId || !active() || busy.current) return;
    busy.current = true; setState('sending'); setMessage(''); let retained: PendingAttempt | null = null;
    try {
      const checked = intent(body);
      if (!await verifyFresh() || !active() || !gate.current) throw new Error('Verification required');
      retained = await retainPending(stableIdentity, FAMILY, RESOURCE, key, PERMISSION, checked);
      if (!active() || !gate.current) return;
      setPending(retained); setRetryAllowed(false);
      const receipt = await request('operations/users', { method: 'POST', body: checked, idempotencyKey: key });
      if (!active()) return;
      if (!await matchesCanonicalReceipt(receipt, principalId, key, {resourceType: 'users', version: 1})) throw new Error('Invalid receipt');
      await clearOriginalAttempt(stableIdentity, retained, active);
      if (!active()) return;
      setPending(null); setReview(null); setCreatedId(receipt.resource_id as string); setState('success'); setMessage('The person was recorded.');
    } catch {
      if (!active()) return;
      const stored = retained ?? await readPending(stableIdentity, FAMILY, RESOURCE).catch(() => null);
      setPending(stored); setReview(null); setState('ready'); setMessage(stored ? 'The result is unconfirmed. Check the original request before creating another person.' : 'Verification or recovery storage is unavailable. No person was submitted.');
    } finally { busy.current = false; }
  };
  const check = async () => {
    if (!pending || !principalId || !active() || busy.current) return;
    if (!permissions.includes('overview.read') || !permissions.includes('account.manage')) { setMessage('Your account cannot check request history. Contact an authorized administrator.'); return; }
    busy.current = true; const original = pending; setState('checking'); setMessage(''); setRetryAllowed(false);
    try {
      const data = await lookupCanonicalMutation(request, principalId, original.request_key);
      if (!active()) return;
      if (data.status === 'not_found') {
        let retryable = false; try { intent(original.intent); retryable = allowMutations; } catch { /* Unsupported retained intents can still be checked. */ }
        setRetryAllowed(retryable); setMessage(retryable ? 'No completed request was found. You may check again or review the same request with its original reference.' : 'No completed request was found. Keep the reference and check again.');
      } else {
        if (data.status === 'succeeded') {
          if (!await matchesCanonicalReceipt(data.receipt, principalId, original.request_key, {resourceType: 'users', version: 1})) throw new Error('Invalid receipt');
          await clearOriginalAttempt(stableIdentity, original, active);
          if (!active()) return;
          setPending(null); setCreatedId((data.receipt as Record<string, unknown>).resource_id as string); setState('success'); setMessage('The original person creation was recorded.'); return;
        }
        if (data.status === 'cancelled') {
          await clearOriginalAttempt(stableIdentity, original, active);
          if (!active()) return;
          setPending(null); setState('error'); setMessage('The original request was cancelled. Reopen creation before starting a new request.'); return;
        }
        setMessage('The request is still unconfirmed. Check again before continuing.');
      }
    } catch { if (active()) setMessage('The original request could not be verified. Keep its reference and check again.'); }
    finally { busy.current = false; if (active()) setState(previous => previous === 'checking' ? 'ready' : previous); }
  };

  return <>
    <PageHeader title="Create person" subtitle="Record an App or Direct person and their payment details." actions={<Button type="button" onClick={() => navigate('/admin/users')}>Back to users</Button>} />
    {!allowed ? <ErrorState title="Creation unavailable" message={financialModel === 'transaction_journals' ? 'This workspace uses the legacy financial model. Its person creation workflow is not available here yet.' : 'Your account cannot create people in this workspace.'} /> :
      state === 'loading' || scopeLoaded !== scope ? <LoadingState label="Checking recovery" /> : state === 'error' ? <ErrorState message={message} /> :
      state === 'success' ? <Card><div className="core-detail" role="status"><h2>Person recorded</h2><p>{message}</p><Button type="button" onClick={() => navigate(`/admin/users/${createdId}`)}>View person</Button></div></Card> : <Card><div className="core-detail">
        {message && <p role="alert">{message}</p>}
        {pending && <section><h2>Original request needs review</h2><p>Request reference: <code>{pending.request_key}</code></p><Button type="button" disabled={state !== 'ready'} onClick={() => void check()}>Check request</Button>{retryAllowed && <Button type="button" disabled={state !== 'ready'} onClick={() => { setReview(intent(pending.intent)); setRetryAllowed(false); }}>Review same request</Button>}</section>}
        {!pending && !review && allowMutations && <form className="core-edit-form" onSubmit={makeReview}>
          <label>Recorded full name<input className="admin-input" value={draft.display_name} maxLength={120} required onChange={event => setDraft({ ...draft, display_name: event.target.value })} /></label>
          <label>Member type<select className="admin-input" value={draft.member_type} onChange={event => setDraft({ ...draft, member_type: event.target.value as Draft['member_type'] })}><option value="app">App</option><option value="direct">Direct</option></select></label>
          <label>MoMo provider<select className="admin-input" value={draft.momo_provider} onChange={event => setDraft({ ...draft, momo_provider: event.target.value })}><option value="mtn_momo">MTN MoMo</option><option value="airtel_money">Airtel Money</option></select></label>
          <label>MoMo number<input className="admin-input" value={draft.momo_number} maxLength={10} onChange={event => setDraft({ ...draft, momo_number: event.target.value })} /></label>
          <label>MoMo code (optional)<input className="admin-input" value={draft.momo_pay_code} maxLength={9} onChange={event => setDraft({ ...draft, momo_pay_code: event.target.value })} /></label>
          {draft.member_type === 'app' && <><label>Email<input className="admin-input" type="email" value={draft.email} maxLength={254} onChange={event => setDraft({ ...draft, email: event.target.value })} /></label><label>WhatsApp login number<input className="admin-input" value={draft.phone_e164} maxLength={13} placeholder="+25078…" onChange={event => setDraft({ ...draft, phone_e164: event.target.value })} /></label></>}
          <label>Account status<select className="admin-input" value={draft.status} onChange={event => setDraft({ ...draft, status: event.target.value })}><option value="active">Active</option><option value="suspended">Suspended</option></select></label>
          <label>Reason for creation<textarea className="admin-input" value={draft.reason} minLength={8} maxLength={500} required onChange={event => setDraft({ ...draft, reason: event.target.value })} /></label>
          <p>Recorded names and payment details are not provider verified. Creating a person does not create an App sign-in.</p><Button type="submit" variant="primary" disabled={state !== 'ready'}>Review person</Button>
        </form>}
        {review && allowMutations && <section><h2>Review person creation</h2><dl>{Object.entries(review).map(([key, value]) => <div key={key}><dt>{key.replaceAll('_', ' ')}</dt><dd>{value === null || value === '' ? 'Not recorded' : String(value)}</dd></div>)}</dl><p>Recorded payment identity is not provider verified. App authentication is separate.</p>{review.member_type === 'direct' && typeof review.email === 'string' && review.email !== '' && <p>This retained Direct-member request includes an email, which the service does not store for Direct members.</p>}
          <Button type="button" disabled={state !== 'ready'} onClick={() => { setReview(null); if (pending) setRetryAllowed(true); }}>Cancel</Button><Button type="button" variant="primary" disabled={state !== 'ready'} onClick={() => { const key = pending?.request_key ?? globalThis.crypto?.randomUUID?.(); if (!key) { setMessage('A secure request reference is unavailable. No person was submitted.'); return; } void send(review, key); }}>{pending ? 'Confirm same request' : 'Confirm person'}</Button></section>}
      </div></Card>}
  </>;
}
