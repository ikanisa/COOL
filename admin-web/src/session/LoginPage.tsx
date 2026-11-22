import {useEffect, useState, type FormEvent} from 'react';
import {AdminRequestError} from '../api/client';
import {Button, Field} from '../ui';
import {AuthFrame, authFailureMessage} from './AuthFrame';
import {useSession, type OtpReceipt} from './SessionProvider';

export function LoginPage({onSignedIn, onForgotPassword}: {onSignedIn: () => void; onForgotPassword: () => void}) {
  const session = useSession();
  const [email, setEmail] = useState('');
  const [code, setCode] = useState('');
  const [receipt, setReceipt] = useState<OtpReceipt | null>(null);
  const [retryAt, setRetryAt] = useState(0);
  const [clock, setClock] = useState(0);
  const [busy, setBusy] = useState(false);
  const [googlePending, setGooglePending] = useState(false);
  const [unknown, setUnknown] = useState(false);
  const [feedback, setFeedback] = useState('');
  const {status, cancelGoogleSignIn} = session;
  const needsSessionCheck = unknown || status === 'error';
  useEffect(() => {if (status === 'authenticated') onSignedIn();}, [status, onSignedIn]);
  useEffect(() => () => cancelGoogleSignIn(), [cancelGoogleSignIn]);
  useEffect(() => {
    if (!receipt || retryAt <= Date.now()) return;
    const timer = setInterval(() => setClock(Date.now()), 1000);
    return () => clearInterval(timer);
  }, [receipt, retryAt]);
  const seconds = Math.max(0, Math.ceil((retryAt - clock) / 1000));
  async function send() {
    if (busy || needsSessionCheck || (receipt && seconds > 0)) return;
    setBusy(true); setFeedback('');
    try {
      const next = await session.requestEmailOtp(email);
      setReceipt(next); setRetryAt(Date.now() + next.retryAfterSeconds * 1000); setClock(Date.now()); setCode('');
      setFeedback(next.deliveryUnknown ? 'The email request is unconfirmed. If a code arrives, enter it before requesting another.' : 'A sign-in code was accepted for sending. Check your inbox and spam folder.');
    } catch (failure) {
      setReceipt(null); setCode('');
      if (failure instanceof AdminRequestError && failure.outcomeUnknown) setUnknown(true);
      setFeedback(authFailureMessage(failure));
    } finally {setBusy(false);}
  }
  async function verify() {
    if (!receipt || busy || needsSessionCheck) return;
    setBusy(true); setFeedback('');
    try {await session.verifyEmailOtp(email, receipt.challengeId, code); setCode('');}
    catch (failure) {if (failure instanceof AdminRequestError && failure.outcomeUnknown) setUnknown(true); setFeedback(authFailureMessage(failure));}
    finally {setBusy(false);}
  }
  async function checkSession() {
    setBusy(true); setFeedback('');
    try {await session.refresh(); setUnknown(false); setReceipt(null); setCode(''); setFeedback('Session check completed. If no account opens, sign in again.');}
    catch (failure) {setFeedback(authFailureMessage(failure));}
    finally {setBusy(false);}
  }
  function googleSignIn() {
    if (busy || needsSessionCheck || receipt) return;
    setBusy(true); setGooglePending(true); setFeedback('');
    // The popup is opened synchronously by signInWithGoogle before its first await.
    void session.signInWithGoogle().catch((failure: unknown) => {
      if (failure instanceof AdminRequestError && failure.outcomeUnknown) setUnknown(true);
      setFeedback(authFailureMessage(failure));
    }).finally(() => {setBusy(false); setGooglePending(false);});
  }
  function submit(event: FormEvent<HTMLFormElement>) {event.preventDefault(); void (receipt ? verify() : send());}
  return <AuthFrame title={receipt ? 'Check your email' : 'Welcome to Collect'} subtitle={receipt ? `Enter the 6-digit code for ${email}.` : 'Enter your team email to sign in to your admin workspace.'}>
    <form className="admin-auth-form" onSubmit={submit}>
      {!receipt ? <Field label="Email" htmlFor="admin-email"><input className="admin-input" id="admin-email" type="email" autoComplete="username" required value={email} onChange={(event) => setEmail(event.target.value)} disabled={busy || needsSessionCheck} /></Field> : <Field label="6-digit code" htmlFor="admin-code"><input className="admin-input" id="admin-code" inputMode="numeric" autoComplete="one-time-code" pattern="[0-9]{6}" maxLength={6} required value={code} onChange={(event) => setCode(event.target.value.replace(/[^0-9]/g, ''))} disabled={busy || needsSessionCheck} /></Field>}
      {(feedback || (status === 'error' && session.error)) && <p className="admin-auth-feedback" role="status">{feedback || session.error}</p>}
      {needsSessionCheck ? <Button variant="primary" loading={busy} onClick={() => void checkSession()}>Check session</Button> : <Button type="submit" variant="primary" loading={busy}>{receipt ? 'Verify and sign in' : 'Send sign-in code'}</Button>}
      {!receipt && !needsSessionCheck && session.googleSignInAvailable && <Button disabled={busy} onClick={googleSignIn}>Continue with Google</Button>}
      {googlePending && <Button onClick={session.cancelGoogleSignIn}>Cancel Google sign-in</Button>}
      {receipt && !needsSessionCheck && <><Button disabled={busy || seconds > 0} onClick={() => void send()}>{seconds > 0 ? `Resend code in ${seconds}s` : 'Resend code'}</Button><Button disabled={busy} onClick={() => {setReceipt(null); setCode(''); setFeedback('');}}>Use a different email</Button></>}
      {!receipt && !needsSessionCheck && <><p className="admin-auth-help">New to the team? Ask your super admin for an invitation.</p><Button disabled={busy} onClick={onForgotPassword}>Reset your password</Button></>}
    </form>
  </AuthFrame>;
}
