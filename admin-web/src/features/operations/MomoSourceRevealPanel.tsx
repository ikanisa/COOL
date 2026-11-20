import { useLayoutEffect, useRef, useState, type FormEvent } from 'react';
import { Link } from 'react-router';
import { verifySensitiveAccess } from '../../app/sensitive-access';
import { useSession, type AdminUser, type SessionContextValue } from '../../session/SessionProvider';
import { Button, Field } from '../../ui';
import type { MomoSourceJob } from './momoContracts';
import type { MomoExtraction } from './momoSourceActions';
import { momoRevealReason, revealMomoSource, type MomoRevealedSource, type MomoSourceRevealContext } from './momoSourceReveal';

/** Unmount the sensitive view on any gate, source or authority change. */
export function MomoSourceRevealPanel({source, enabled = false, onCandidate}: {source: MomoSourceJob; enabled?: boolean; onCandidate?: (candidate: MomoExtraction | null) => void}) {
  const session = useSession(), user = session.user;
  if (!enabled || session.status !== 'authenticated' || !user || user.financialModel !== 'canonical_evidence_ledger' || !['sms.read', 'sms.reveal'].every((permission) => user.permissions.includes(permission))) return null;
  if (!source.body_sha256) return <p>Original source access is unavailable because its recorded digest is missing.</p>;
  const scope = JSON.stringify([session.epoch, user.id, user.sessionId, user.email, user.role, user.principalId, user.financialModel, user.expiresAt, [...user.permissions].sort(), source.raw_sms_id, source.body_sha256]);
  return <MomoSourceRevealSession key={scope} source={source} session={session} user={user} onCandidate={onCandidate} />;
}
function MomoSourceRevealSession({source, session, user, onCandidate}: {source: MomoSourceJob; session: SessionContextValue; user: AdminUser; onCandidate?: (candidate: MomoExtraction | null) => void}) {
  const live = useRef(session), mounted = useRef(false), pending = useRef<AbortController | null>(null), busyRef = useRef(false);
  useLayoutEffect(() => {live.current = session;}, [session]);
  useLayoutEffect(() => {mounted.current = true; return () => {mounted.current = false; pending.current?.abort();};}, []);
  const [reason, setReason] = useState(''), [reviewReason, setReviewReason] = useState<string | null>(null), [confirmed, setConfirmed] = useState(false), [busy, setBusy] = useState(false);
  const [content, setContent] = useState<MomoRevealedSource | null>(null), [message, setMessage] = useState(''), [needsVerification, setNeedsVerification] = useState(false);
  const current = () => {
    const actor = live.current.user;
    return mounted.current && live.current.status === 'authenticated' && !!actor && actor.id === user.id && actor.sessionId === user.sessionId && actor.principalId === user.principalId &&
      actor.financialModel === user.financialModel && JSON.stringify([...actor.permissions].sort()) === JSON.stringify([...user.permissions].sort()) &&
      Date.parse(actor.expiresAt) > Date.now() && live.current.isCurrentAuthority(session.epoch, user.id, user.sessionId);
  };
  const review = (event: FormEvent) => {
    event.preventDefault(); if (!current() || busyRef.current) return;
    try {setReviewReason(momoRevealReason(reason)); setConfirmed(false); setMessage(''); setNeedsVerification(false);}
    catch {setMessage('Enter a reason of 8 to 500 characters on one line.');}
  };
  const reveal = async () => {
    if (!reviewReason || !confirmed || !current() || busyRef.current) return;
    busyRef.current = true; setBusy(true); setMessage(''); setNeedsVerification(false); setContent(null);
    const controller = new AbortController(); pending.current = controller;
    const context: MomoSourceRevealContext = {request: session.request, identity: {id: user.id, sessionId: user.sessionId, email: user.email, role: user.role, permissions: user.permissions, expiresAt: user.expiresAt}, financialModel: user.financialModel,
      source, enabled: true, isCurrent: current, signal: controller.signal,
      verifyFresh: async () => {const actor = live.current.user; return !!actor && actor.id === user.id && actor.sessionId === user.sessionId && await verifySensitiveAccess(live.current, actor);}};
    try {
      const result = await revealMomoSource(context, reviewReason);
      if (current()) {setContent(result); onCandidate?.(result.candidate ?? null); setMessage('Source access recorded. The message is evidence and does not confirm provider settlement.');}
    } catch (error) {
      if (current()) {
        const verification = error instanceof Error && error.message.includes('current verification'); setNeedsVerification(verification);
        setMessage(verification ? 'Complete current verification before viewing this source.' : 'Source access could not be confirmed. An access event may have been recorded. A new request requires your confirmation and may record another event.');
      }
    } finally {pending.current = null; busyRef.current = false; if (current()) {setBusy(false); setReviewReason(null); setConfirmed(false);}}
  };
  return <section className="momo-assignment" aria-label="Original source access"><h3>Original source</h3><p>Viewing this message records your reason and access. The message is evidence and does not by itself credit a contribution or confirm provider settlement.</p>
    {message && <p role="status">{message}</p>}
    {needsVerification && <p><Link className="operations-link" to={`/admin/security/${session.verificationMode === 'email' ? 'verify-email' : 'authenticator'}?returnTo=%2Fadmin%2Fmomo-receipts`}>Verify identity</Link></p>}
    {!content && <form className="operations-action-form" onSubmit={review}><Field label="Reason to review the original source" htmlFor="momo-source-reason"><input id="momo-source-reason" className="admin-input" value={reason} onChange={(event) => setReason(event.target.value)} minLength={8} maxLength={500} required disabled={busy || reviewReason !== null} /></Field><Button type="submit" disabled={busy || reviewReason !== null}>Review source access</Button></form>}
    {reviewReason && <section className="momo-assignment-review" aria-label="Confirm source access"><h4>Confirm source access</h4><p>Source reference: <code>{source.raw_sms_id}</code></p><p>Reason: {reviewReason}</p><p>Each access is separately recorded. There is no request status lookup for this access.</p><label><input type="checkbox" checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} disabled={busy} /> I confirm this source review.</label><div className="momo-assignment-actions"><Button onClick={() => {setReviewReason(null); setConfirmed(false);}} disabled={busy}>Cancel</Button><Button variant="primary" onClick={() => void reveal()} disabled={!confirmed || busy}>View original SMS</Button></div></section>}
    {content && <section aria-label="Revealed original source"><h4>Original SMS evidence</h4><p>Sender: {content.sender}</p><pre className="operations-source-content">{content.body}</pre><Button onClick={() => setContent(null)}>Hide message</Button></section>}
  </section>;
}
