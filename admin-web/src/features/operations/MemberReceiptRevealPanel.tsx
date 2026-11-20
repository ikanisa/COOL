import {useLayoutEffect, useRef, useState, type FormEvent} from 'react';
import {useSession, type AdminUser, type SessionContextValue} from '../../session/SessionProvider';
import {Button, Field} from '../../ui';
import type {MemberReceipt} from './contracts';
import {memberReceiptRevealReason, revealMemberReceipt, type MemberReceiptRevealContext, type RevealedMemberReceipt} from './memberReceiptReveal';

/** Unmount the sensitive content when the action gate, receipt or authority changes. */
export function MemberReceiptRevealPanel({receipt, canManage, enabled = false}: {receipt: MemberReceipt; canManage: boolean; enabled?: boolean}) {
  const session = useSession(), user = session.user;
  if (!enabled || session.status !== 'authenticated' || !user || user.financialModel !== 'transaction_journals' || receipt.source_kind === 'capture' ||
      !canManage || user.role === 'staff' || !['payments.read', 'payments.manage'].every((permission) => user.permissions.includes(permission))) return null;
  const scope = JSON.stringify([session.epoch, user.id, user.sessionId, user.email, user.role, user.expiresAt, [...user.permissions].sort(), receipt.id, receipt.body_sha256]);
  return <MemberReceiptRevealSession key={scope} receipt={receipt} session={session} user={user} />;
}
function MemberReceiptRevealSession({receipt, session, user}: {receipt: MemberReceipt; session: SessionContextValue; user: AdminUser}) {
  const live = useRef(session), mounted = useRef(false), pending = useRef<AbortController | null>(null), busyRef = useRef(false);
  useLayoutEffect(() => {live.current = session;}, [session]);
  useLayoutEffect(() => {mounted.current = true; return () => {mounted.current = false; pending.current?.abort();};}, []);
  const [reason, setReason] = useState(''), [reviewReason, setReviewReason] = useState<string | null>(null), [confirmed, setConfirmed] = useState(false), [busy, setBusy] = useState(false);
  const [content, setContent] = useState<RevealedMemberReceipt | null>(null), [message, setMessage] = useState('');
  const current = () => {
    const actor = live.current.user;
    return mounted.current && live.current.status === 'authenticated' && !!actor && actor.id === user.id && actor.sessionId === user.sessionId && actor.financialModel === user.financialModel &&
      JSON.stringify([...actor.permissions].sort()) === JSON.stringify([...user.permissions].sort()) && Date.parse(actor.expiresAt) > Date.now() && live.current.isCurrentAuthority(session.epoch, user.id, user.sessionId);
  };
  const review = (event: FormEvent) => {
    event.preventDefault(); if (!current() || busyRef.current) return;
    try {setReviewReason(memberReceiptRevealReason(reason)); setConfirmed(false); setMessage('');}
    catch {setMessage('Enter a reason of 8 to 1000 characters on one line.');}
  };
  const reveal = async () => {
    if (!reviewReason || !confirmed || !current() || busyRef.current) return;
    busyRef.current = true; setBusy(true); setMessage(''); setContent(null);
    const controller = new AbortController(); pending.current = controller;
    const context: MemberReceiptRevealContext = {request: session.request, identity: {id: user.id, sessionId: user.sessionId, email: user.email, role: user.role, permissions: user.permissions, expiresAt: user.expiresAt},
      financialModel: user.financialModel, receipt, canManage: true, enabled: true, isCurrent: current, signal: controller.signal};
    try {const result = await revealMemberReceipt(context, reviewReason); if (current()) {setContent(result); setMessage('Receipt access recorded. The message is member-submitted evidence.');}}
    catch {if (current()) setMessage('Receipt access could not be confirmed. An access event may have been recorded. A new request requires confirmation and may record another event.');}
    finally {pending.current = null; busyRef.current = false; if (current()) {setBusy(false); setReviewReason(null); setConfirmed(false);}}
  };
  return <section className="momo-assignment" aria-label="Submitted receipt access"><h3>Submitted receipt</h3><p>Viewing the message records your reason and access. The message is evidence and does not confirm provider settlement.</p>
    {message && <p role="status">{message}</p>}
    {!content && <form className="operations-action-form" onSubmit={review}><Field label="Reason to review the submitted receipt" htmlFor="member-receipt-reason"><input id="member-receipt-reason" className="admin-input" value={reason} onChange={(event) => setReason(event.target.value)} minLength={8} maxLength={1000} required disabled={busy || reviewReason !== null} /></Field><Button type="submit" disabled={busy || reviewReason !== null}>Review receipt access</Button></form>}
    {reviewReason && <section className="momo-assignment-review" aria-label="Confirm receipt access"><h4>Confirm receipt access</h4><p>Receipt reference: <code>{receipt.id}</code></p><p>Reason: {reviewReason}</p><p>Each access is separately recorded. There is no access status lookup.</p><label><input type="checkbox" checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} disabled={busy} /> I confirm this receipt review.</label><div className="momo-assignment-actions"><Button onClick={() => {setReviewReason(null); setConfirmed(false);}} disabled={busy}>Cancel</Button><Button variant="primary" onClick={() => void reveal()} disabled={!confirmed || busy}>View submitted receipt</Button></div></section>}
    {content && <><h4>Sender</h4><p>{content.sender}</p><h4>Message</h4><pre className="operations-source-content">{content.body}</pre><Button onClick={() => {setContent(null); setReason(''); setMessage('');}}>Hide message</Button></>}
  </section>;
}
