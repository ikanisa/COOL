import {useState, type FormEvent} from 'react';
import {AdminRequestError} from '../api/client';
import {Button, Field} from '../ui';
import {AuthFrame, authFailureMessage} from './AuthFrame';
import {useSession} from './SessionProvider';

export function ForgotPasswordPage({onBackToLogin}: {onBackToLogin: () => void}) {
  const session = useSession();
  const [email, setEmail] = useState(''), [feedback, setFeedback] = useState('');
  const [busy, setBusy] = useState(false), [unknown, setUnknown] = useState(false);
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); if (busy || unknown) return;
    setBusy(true); setFeedback('');
    try {await session.requestPasswordReset(email); setFeedback('If this account is eligible, check your inbox for a password link.');}
    catch (failure) {if (failure instanceof AdminRequestError && failure.outcomeUnknown) setUnknown(true); setFeedback(authFailureMessage(failure));}
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
    catch (failure) {setPassword(''); setConfirm(''); if (failure instanceof AdminRequestError && failure.outcomeUnknown) setUnknown(true); setFeedback(authFailureMessage(failure));}
    finally {setBusy(false);}
  }
  return <AuthFrame title={complete ? 'Your password is ready' : setup?.invite ? 'Join your Collect team' : 'Choose a new password'} subtitle={complete ? 'Continue to sign in.' : 'Use a password you do not use elsewhere.'}>
    {!setup ? <div className="admin-auth-form"><p role="alert">This link is incomplete or expired. Request a new email.</p><Button onClick={onRequestReset}>Request reset email</Button><Button onClick={onBackToLogin}>Back to sign in</Button></div> : complete ? <Button variant="primary" onClick={onBackToLogin}>Continue to sign in</Button> : <form className="admin-auth-form" onSubmit={submit}><Field label="New password" htmlFor="new-password" hint="Use at least 12 characters."><input className="admin-input" id="new-password" type="password" autoComplete="new-password" minLength={12} maxLength={128} required value={password} onChange={(event) => setPassword(event.target.value)} disabled={busy || unknown} /></Field><Field label="Confirm password" htmlFor="confirm-password"><input className="admin-input" id="confirm-password" type="password" autoComplete="new-password" minLength={12} maxLength={128} required value={confirm} onChange={(event) => setConfirm(event.target.value)} disabled={busy || unknown} /></Field>{feedback && <p className="admin-auth-feedback" role="status">{feedback}</p>}{unknown && <p>Do not repeat this request. Sign in using your email code or request a new reset link.</p>}<Button type="submit" variant="primary" loading={busy} disabled={unknown}>Set password</Button><Button onClick={onBackToLogin} disabled={busy}>Back to sign in</Button></form>}
  </AuthFrame>;
}
