import {useEffect, useState, type FormEvent, type ReactNode} from 'react';
import {AdminRequestError} from '../api/client';
import {Button, Card, Field, PageHeader} from '../ui';
import collectLogo from '../ui/assets/collect-logo.png';
import {useSession, type OtpReceipt} from './SessionProvider';
import './auth.css';

function AuthFrame({title, subtitle, children}: {title: string; subtitle: string; children: ReactNode}) {
  return <main className="admin-auth"><div className="admin-auth-inner"><div className="admin-auth-brand"><img src={collectLogo} alt="" /><span>collect <small>Admin workspace</small></span></div><Card className="admin-auth-card"><h1>{title}</h1><p className="admin-auth-subtitle">{subtitle}</p>{children}</Card></div></main>;
}

function message(failure: unknown): string {
  return failure instanceof Error ? failure.message : 'The request could not be confirmed. Try again.';
}

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
      setFeedback(message(failure));
    } finally {setBusy(false);}
  }
  async function verify() {
    if (!receipt || busy || needsSessionCheck) return;
    setBusy(true); setFeedback('');
    try {await session.verifyEmailOtp(email, receipt.challengeId, code); setCode('');}
    catch (failure) {if (failure instanceof AdminRequestError && failure.outcomeUnknown) setUnknown(true); setFeedback(message(failure));}
    finally {setBusy(false);}
  }
  async function checkSession() {
    setBusy(true); setFeedback('');
    try {await session.refresh(); setUnknown(false); setReceipt(null); setCode(''); setFeedback('Session check completed. If no account opens, sign in again.');}
    catch (failure) {setFeedback(message(failure));}
    finally {setBusy(false);}
  }
  function googleSignIn() {
    if (busy || needsSessionCheck || receipt) return;
    setBusy(true); setGooglePending(true); setFeedback('');
    // The popup is opened synchronously by signInWithGoogle before its first await.
    void session.signInWithGoogle().catch((failure: unknown) => {
      if (failure instanceof AdminRequestError && failure.outcomeUnknown) setUnknown(true);
      setFeedback(message(failure));
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

export function ForgotPasswordPage({onBackToLogin}: {onBackToLogin: () => void}) {
  const session = useSession();
  const [email, setEmail] = useState(''), [feedback, setFeedback] = useState('');
  const [busy, setBusy] = useState(false), [unknown, setUnknown] = useState(false);
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); if (busy || unknown) return;
    setBusy(true); setFeedback('');
    try {await session.requestPasswordReset(email); setFeedback('If this account is eligible, check your inbox for a password link.');}
    catch (failure) {if (failure instanceof AdminRequestError && failure.outcomeUnknown) setUnknown(true); setFeedback(message(failure));}
    finally {setBusy(false);}
  }
  return <AuthFrame title="Reset your password" subtitle="Enter the email you use for Collect Admin."><form className="admin-auth-form" onSubmit={submit}><Field label="Email" htmlFor="reset-email"><input className="admin-input" id="reset-email" type="email" autoComplete="email" required value={email} onChange={(event) => setEmail(event.target.value)} disabled={busy || unknown} /></Field>{feedback && <p className="admin-auth-feedback" role="status">{feedback}</p>}<Button variant="primary" type="submit" loading={busy} disabled={unknown}>Send reset email</Button><Button disabled={busy} onClick={onBackToLogin}>Back to sign in</Button></form></AuthFrame>;
}

export function PasswordSetupPage({setup, onBackToLogin, onRequestReset}: {setup: {token: string; invite: boolean} | null; onBackToLogin: () => void; onRequestReset: () => void}) {
  const session = useSession();
  const [password, setPassword] = useState(''), [confirm, setConfirm] = useState(''), [feedback, setFeedback] = useState('');
  const [busy, setBusy] = useState(false), [unknown, setUnknown] = useState(false), [complete, setComplete] = useState(false);
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); if (!setup || busy || unknown) return;
    if (password !== confirm) {setFeedback('The passwords do not match.'); return;}
    setBusy(true); setFeedback('');
    try {await session.completePasswordSetup(setup.token, password, setup.invite); setPassword(''); setConfirm(''); setComplete(true);}
    catch (failure) {setPassword(''); setConfirm(''); if (failure instanceof AdminRequestError && failure.outcomeUnknown) setUnknown(true); setFeedback(message(failure));}
    finally {setBusy(false);}
  }
  return <AuthFrame title={complete ? 'Your password is ready' : setup?.invite ? 'Join your Collect team' : 'Choose a new password'} subtitle={complete ? 'Continue to sign in.' : 'Use a password you do not use elsewhere.'}>
    {!setup ? <div className="admin-auth-form"><p role="alert">This link is incomplete or expired. Request a new email.</p><Button onClick={onRequestReset}>Request reset email</Button><Button onClick={onBackToLogin}>Back to sign in</Button></div> : complete ? <Button variant="primary" onClick={onBackToLogin}>Continue to sign in</Button> : <form className="admin-auth-form" onSubmit={submit}><Field label="New password" htmlFor="new-password" hint="Use at least 12 characters."><input className="admin-input" id="new-password" type="password" autoComplete="new-password" minLength={12} maxLength={128} required value={password} onChange={(event) => setPassword(event.target.value)} disabled={busy || unknown} /></Field><Field label="Confirm password" htmlFor="confirm-password"><input className="admin-input" id="confirm-password" type="password" autoComplete="new-password" minLength={12} maxLength={128} required value={confirm} onChange={(event) => setConfirm(event.target.value)} disabled={busy || unknown} /></Field>{feedback && <p className="admin-auth-feedback" role="status">{feedback}</p>}{unknown && <p>Do not repeat this request. Sign in using your email code or request a new reset link.</p>}<Button type="submit" variant="primary" loading={busy} disabled={unknown}>Set password</Button><Button onClick={onBackToLogin} disabled={busy}>Back to sign in</Button></form>}
  </AuthFrame>;
}

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
    catch (failure) {if ((failure instanceof AdminRequestError && failure.outcomeUnknown) || session.sensitiveEmailRecovery()) setUnknown(true); setFeedback(message(failure));}
    finally {setBusy(false);}
  }
  async function verify(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); if (!receipt || expired || busy || unknown) return; setBusy(true); setFeedback('');
    try {await session.verifySensitiveEmailVerification(receipt.challengeId, code); setCode(''); onDone(true);}
    catch (failure) {if (failure instanceof AdminRequestError && failure.outcomeUnknown) setUnknown(true); setFeedback(message(failure));}
    finally {setBusy(false);}
  }
  async function check() {
    if (busy) return; setBusy(true); setFeedback('');
    try {if (await session.recheckEmailVerification()) {setUnknown(false); onDone(true);} else {setUnknown(session.sensitiveEmailRecovery() !== null); setClock(Date.now()); setFeedback('Verification is not confirmed yet. Check again before continuing.');}}
    catch (failure) {setFeedback(message(failure));}
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

export function AccountSecurityPage({onVerify, onAuthenticator, onLicenses, onPasswordRecovery, onSignIn}: {onVerify: () => void; onAuthenticator?: () => void; onLicenses: () => void; onPasswordRecovery: () => void; onSignIn: () => void}) {
  const session = useSession();
  const [current, setCurrent] = useState(''), [password, setPassword] = useState(''), [confirm, setConfirm] = useState(''), [feedback, setFeedback] = useState('');
  const [busy, setBusy] = useState(false), [unknown, setUnknown] = useState(false);
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); if (busy || unknown) return;
    if (password !== confirm) {setFeedback('The passwords do not match.'); return;}
    setBusy(true); setFeedback('');
    try {await session.changePassword(current, password); setCurrent(''); setPassword(''); setConfirm(''); onSignIn();}
    catch (failure) {
      if (failure instanceof AdminRequestError && failure.outcomeUnknown) {setCurrent(''); setPassword(''); setConfirm(''); setUnknown(true);}
      setFeedback(message(failure));
    } finally {setBusy(false);}
  }
  function backToSignIn() {session.clearLocalSession(); onSignIn();}
  return <><PageHeader title="Account security" subtitle="Manage your sign-in and account verification." /><div className="admin-security-layout"><Card className="admin-security-links"><Button onClick={onVerify}>{session.verificationMode === 'email' ? 'Verify email' : 'Authenticator'}</Button>{session.verificationMode === 'email' && session.user?.mfaAvailable === true && onAuthenticator && <Button onClick={onAuthenticator}>Authenticator</Button>}<Button onClick={onLicenses}>Open-source licenses</Button></Card><Card className="admin-security-card"><h2>Change password</h2><form className="admin-auth-form" onSubmit={submit}><Field label="Current password" htmlFor="current-password"><input className="admin-input" id="current-password" type="password" autoComplete="current-password" required maxLength={512} value={current} onChange={(event) => setCurrent(event.target.value)} disabled={busy || unknown} /></Field><Field label="New password" htmlFor="security-new-password" hint="Use at least 12 characters."><input className="admin-input" id="security-new-password" type="password" autoComplete="new-password" minLength={12} maxLength={128} required value={password} onChange={(event) => setPassword(event.target.value)} disabled={busy || unknown} /></Field><Field label="Confirm new password" htmlFor="security-confirm-password"><input className="admin-input" id="security-confirm-password" type="password" autoComplete="new-password" minLength={12} maxLength={128} required value={confirm} onChange={(event) => setConfirm(event.target.value)} disabled={busy || unknown} /></Field>{feedback && <p className="admin-auth-feedback" role="status">{feedback}</p>}{unknown && <p>The password change is unconfirmed. Do not repeat it. Sign in using your email code, or request a new reset link.</p>}<Button type="submit" variant="primary" loading={busy} disabled={unknown}>Change password</Button>{unknown ? <Button onClick={backToSignIn}>Back to sign in</Button> : session.verificationMode === 'email' && <Button disabled={busy} onClick={onPasswordRecovery}>Set or reset password by email</Button>}</form></Card></div></>;
}
