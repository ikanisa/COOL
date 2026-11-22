import {useEffect, useState, type FormEvent} from 'react';
import {AdminRequestError} from '../api/client';
import {Button, Field} from '../ui';
import {authFailureMessage} from './AuthFrame';
import {useSession, type OtpReceipt} from './SessionProvider';

export function SensitiveEmailVerificationPage({onDone}: {onDone: (completed: boolean) => void}) {
  const session = useSession();
  const [receipt, setReceipt] = useState<OtpReceipt | null>(null), [code, setCode] = useState(''), [feedback, setFeedback] = useState('');
  const [busy, setBusy] = useState(false), [unknown, setUnknown] = useState(() => session.sensitiveEmailRecovery() !== null);
  const [clock, setClock] = useState(() => Date.now()), [retryAt, setRetryAt] = useState(0), [expiresAt, setExpiresAt] = useState(0);
  const {cancelSensitiveEmailVerification} = session;
  useEffect(() => () => cancelSensitiveEmailVerification(), [cancelSensitiveEmailVerification]);
  useEffect(() => {const timer = setInterval(() => setClock(Date.now()), 1000); return () => clearInterval(timer);}, []);
  const recovery = session.sensitiveEmailRecovery();
  const seconds = Math.max(0, Math.ceil((retryAt - clock) / 1000));
  const recoverySeconds = recovery?.retryAt ? Math.max(0, Math.ceil((recovery.retryAt - clock) / 1000)) : 0;
  const expired = receipt !== null && expiresAt <= clock;
  const canRequestAfterUnknown = recovery?.kind === 'request' && recovery.checked && recoverySeconds === 0;
  async function send() {
    if (busy || seconds > 0 || (unknown && !canRequestAfterUnknown)) return; setBusy(true); setFeedback('');
    try {
      if (unknown) {session.releaseExpiredSensitiveRequest(); setUnknown(false);}
      const next = await session.requestSensitiveEmailVerification(), now = Date.now();
      setReceipt(next); setRetryAt(now + next.retryAfterSeconds * 1000); setExpiresAt(now + next.expiresInSeconds * 1000); setClock(now); setCode('');
      setFeedback(next.deliveryUnknown ? 'Email delivery is unconfirmed. If a code arrives, use it before requesting another.' : 'A code was accepted for sending. Check your email.');
    }
    catch (failure) {if ((failure instanceof AdminRequestError && failure.outcomeUnknown) || session.sensitiveEmailRecovery()) setUnknown(true); setFeedback(authFailureMessage(failure));}
    finally {setBusy(false);}
  }
  async function verify(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); if (!receipt || expired || busy || unknown) return; setBusy(true); setFeedback('');
    try {await session.verifySensitiveEmailVerification(receipt.challengeId, code); setCode(''); onDone(true);}
    catch (failure) {if (failure instanceof AdminRequestError && failure.outcomeUnknown) setUnknown(true); setFeedback(authFailureMessage(failure));}
    finally {setBusy(false);}
  }
  async function check() {
    if (busy) return; setBusy(true); setFeedback('');
    try {if (await session.recheckEmailVerification()) {setUnknown(false); onDone(true);} else {setUnknown(session.sensitiveEmailRecovery() !== null); setClock(Date.now()); setFeedback('Verification is not confirmed yet. Check again before continuing.');}}
    catch (failure) {setFeedback(authFailureMessage(failure));}
    finally {setBusy(false);}
  }
  return <div className="admin-auth-task"><h1>Verify your email</h1><p>Confirm sensitive changes using a code sent to your account email.</p><form className="admin-auth-form" onSubmit={verify}>
    {receipt && !expired && !unknown && <Field label="6-digit code" htmlFor="sensitive-email-code"><input className="admin-input" id="sensitive-email-code" inputMode="numeric" autoComplete="one-time-code" pattern="[0-9]{6}" maxLength={6} required value={code} onChange={(event) => setCode(event.target.value.replace(/[^0-9]/g, ''))} disabled={busy} /></Field>}
    {expired && !unknown && <p>This code has expired. Request a new code.</p>}
    {unknown && recovery?.kind === 'verify' && <p>The previous verification is unconfirmed. Check it or sign out and sign in again before continuing.</p>}
    {unknown && recovery?.kind === 'request' && <p>Check verification before requesting another code. {recovery.checked && recoverySeconds > 0 ? `You can request a new code in ${recoverySeconds}s.` : ''}</p>}
    {feedback && <p className="admin-auth-feedback" role="status">{feedback}</p>}
    {receipt && !expired && !unknown && <Button type="submit" variant="primary" loading={busy}>Verify email</Button>}
    {(!unknown || recovery?.kind === 'request') && <Button variant={receipt ? 'secondary' : 'primary'} loading={busy} disabled={seconds > 0 || (unknown && !canRequestAfterUnknown)} onClick={() => void send()}>{seconds > 0 && !unknown ? `Request again in ${seconds}s` : receipt || unknown ? 'Request a new code' : 'Send email code'}</Button>}
    <Button disabled={busy} onClick={() => void check()}>Check verification</Button><Button disabled={busy} onClick={() => onDone(false)}>Back</Button>
  </form></div>;
}
