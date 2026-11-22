import {useState, type FormEvent} from 'react';
import {AdminRequestError} from '../api/client';
import {Button, Card, Field, PageHeader} from '../ui';
import {authFailureMessage} from './AuthFrame';
import {useSession} from './SessionProvider';

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
      setFeedback(authFailureMessage(failure));
    } finally {setBusy(false);}
  }
  function backToSignIn() {session.clearLocalSession(); onSignIn();}
  return <><PageHeader title="Account security" subtitle="Manage your sign-in and account verification." /><div className="admin-security-layout"><Card className="admin-security-links"><Button onClick={onVerify}>{session.verificationMode === 'email' ? 'Verify email' : 'Authenticator'}</Button>{session.verificationMode === 'email' && session.user?.mfaAvailable === true && onAuthenticator && <Button onClick={onAuthenticator}>Authenticator</Button>}<Button onClick={onLicenses}>Open-source licenses</Button></Card><Card className="admin-security-card"><h2>Change password</h2><form className="admin-auth-form" onSubmit={submit}><Field label="Current password" htmlFor="current-password"><input className="admin-input" id="current-password" type="password" autoComplete="current-password" required maxLength={512} value={current} onChange={(event) => setCurrent(event.target.value)} disabled={busy || unknown} /></Field><Field label="New password" htmlFor="security-new-password" hint="Use at least 12 characters."><input className="admin-input" id="security-new-password" type="password" autoComplete="new-password" minLength={12} maxLength={128} required value={password} onChange={(event) => setPassword(event.target.value)} disabled={busy || unknown} /></Field><Field label="Confirm new password" htmlFor="security-confirm-password"><input className="admin-input" id="security-confirm-password" type="password" autoComplete="new-password" minLength={12} maxLength={128} required value={confirm} onChange={(event) => setConfirm(event.target.value)} disabled={busy || unknown} /></Field>{feedback && <p className="admin-auth-feedback" role="status">{feedback}</p>}{unknown && <p>The password change is unconfirmed. Do not repeat it. Sign in using your email code, or request a new reset link.</p>}<Button type="submit" variant="primary" loading={busy} disabled={unknown}>Change password</Button>{unknown ? <Button onClick={backToSignIn}>Back to sign in</Button> : session.verificationMode === 'email' && <Button disabled={busy} onClick={onPasswordRecovery}>Set or reset password by email</Button>}</form></Card></div></>;
}
