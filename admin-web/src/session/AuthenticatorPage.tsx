/* eslint-disable no-control-regex -- Reject ASCII control characters in server-supplied labels. */
import {useEffect, useState, type FormEvent} from 'react';
import {AdminRequestError, type JsonObject} from '../api/client';
import {Button, Card, Field, LoadingState, PageHeader} from '../ui';
import {useSession, type AdminUser} from './SessionProvider';
import {MANAGED_MFA_TRANSITION_QUALIFIED} from './mfaQualification';
import './auth.css';

const ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
interface Factor {id: string; name: string; verified: boolean}
interface Setup {factor: Factor; secret: string}
function isObject(value: unknown): value is JsonObject {return !!value && typeof value === 'object' && !Array.isArray(value);}

export function parseFactor(value: unknown): Factor {
  if (!isObject(value) || typeof value.id !== 'string' || !ID.test(value.id) || value.factor_type !== 'totp' || (value.status !== 'verified' && value.status !== 'unverified')) throw new Error('The authenticator response could not be verified.');
  const name = value.friendly_name ?? 'Authenticator';
  if (typeof name !== 'string' || !name.trim() || name.length > 64 || /[\x00-\x1f\x7f]/.test(name)) throw new Error('The authenticator response could not be verified.');
  return {id: value.id, name, verified: value.status === 'verified'};
}

export function parseSetup(value: JsonObject, user: AdminUser): Setup {
  const factor = parseFactor(value), totp = value.totp;
  if (factor.verified || !isObject(totp) || typeof totp.secret !== 'string' || !/^[A-Z2-7]{32}$/.test(totp.secret) || typeof totp.uri !== 'string') throw new Error('The authenticator setup could not be verified.');
  let uri: URL;
  try {uri = new URL(totp.uri);} catch {throw new Error('The authenticator setup could not be verified.');}
  let label: string;
  try {label = decodeURIComponent(uri.pathname.slice(1));} catch {throw new Error('The authenticator setup could not be verified.');}
  const expected: Record<string, string> = {secret: totp.secret, issuer: 'Collect', algorithm: 'SHA1', digits: '6', period: '30'};
  if (uri.protocol !== 'otpauth:' || uri.hostname !== 'totp' || uri.port || uri.username || uri.password || uri.hash || uri.pathname.slice(1).includes('/') || label !== `Collect:${user.email}` || [...uri.searchParams.keys()].length !== Object.keys(expected).length || Object.entries(expected).some(([key, val]) => uri.searchParams.getAll(key).length !== 1 || uri.searchParams.get(key) !== val)) throw new Error('The authenticator setup could not be verified.');
  return {factor, secret: totp.secret};
}

function parseFactors(body: JsonObject, principalId: string): Factor[] {
  if (body.id !== principalId || !Array.isArray(body.factors) || body.factors.length > 128) throw new Error('The authenticator response could not be verified.');
  const factors = body.factors.map(parseFactor);
  if (new Set(factors.map((item) => item.id.toLowerCase())).size !== factors.length) throw new Error('The authenticator response could not be verified.');
  return factors;
}

export function AuthenticatorPage({onBack, onSignIn, onVerified}: {onBack: () => void; onSignIn: () => void; onVerified?: () => void}) {
  const session = useSession(), user = session.user, request = session.request;
  const [factors, setFactors] = useState<Factor[]>([]), [selected, setSelected] = useState(''), [setup, setSetup] = useState<Setup | null>(null);
  const [code, setCode] = useState(''), [error, setError] = useState(''), [unknown, setUnknown] = useState(false);
  const [busy, setBusy] = useState(false), [loading, setLoading] = useState(true), [reload, setReload] = useState(0), [confirmCancel, setConfirmCancel] = useState(false);
  const principalId = user?.principalId ?? null, epoch = session.epoch;
  const managed = session.verificationMode === 'email' && user?.mfaAvailable === true;
  const available = !!principalId && (session.verificationMode === 'authenticator' || managed && MANAGED_MFA_TRANSITION_QUALIFIED);
  const mayEnroll = managed || user?.permissions.includes('auth.mfa.enroll') === true;
  const current = () => !!user && session.isCurrentAuthority(epoch, user.id, user.sessionId);
  const factor = setup?.factor ?? factors.find((item) => item.id === selected) ?? factors[0];
  useEffect(() => {
    let alive = true;
    if (!principalId || !available) return;
    void request(managed ? 'auth/mfa/factors' : 'auth/user', {authenticated: true}).then((body) => {
      if (!alive) return;
      const items = parseFactors(body, principalId);
      setFactors(items); setSelected((previous) => items.some((item) => item.id === previous) ? previous : items[0]?.id ?? ''); setUnknown(false); setError('');
    }).catch((failure: unknown) => {if (alive) setError(failure instanceof Error ? failure.message : 'Authenticator access is unavailable.');})
      .finally(() => {if (alive) setLoading(false);});
    return () => {alive = false;};
  }, [request, principalId, epoch, reload, managed, available]);

  async function enroll() {
    if (!user || !mayEnroll || busy || unknown || !current()) return;
    setBusy(true); setError('');
    try {
      if (managed && (!(await session.recheckEmailVerification()) || !current())) throw new Error('Verify your email before connecting an authenticator.');
      const result = await request('auth/mfa/enroll', {body: {friendly_name: 'Collect Admin', factor_type: 'totp'}});
      let next: Setup;
      try {next = parseSetup(result, user);} catch {throw new AdminRequestError('Authenticator setup could not be confirmed. Recheck the setup.', {outcomeUnknown: true});}
      setSetup(next); setSelected(next.factor.id);
    }
    catch (failure) {if (failure instanceof AdminRequestError && failure.outcomeUnknown) setUnknown(true); setError(failure instanceof Error ? failure.message : 'Authenticator setup could not be confirmed.');}
    finally {setBusy(false);}
  }
  async function verify(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); if (!factor || busy || unknown || !/^[0-9]{6}$/.test(code) || !current()) return;
    const token = code; setCode(''); setBusy(true); setError('');
    try {
      const body = await request('auth/mfa/challenge', {body: {factor_id: factor.id}}), now = Math.floor(Date.now() / 1000);
      if (typeof body.challenge_id !== 'string' || !ID.test(body.challenge_id) || body.id !== body.challenge_id || managed && body.factor_id !== factor.id || !Number.isInteger(body.expires_at) || (body.expires_at as number) <= now || (body.expires_at as number) > now + 600) throw new AdminRequestError('The authenticator challenge could not be verified.', {outcomeUnknown: true});
      if (!current()) throw new AdminRequestError('Your sign-in changed. Reopen this page.');
      await session.verifyAuthenticator(factor.id, body.challenge_id, token);
      setSetup(null); setReload((value) => value + 1); onVerified?.();
    } catch (failure) {if (failure instanceof AdminRequestError && failure.outcomeUnknown) setUnknown(true); setError(failure instanceof Error ? failure.message : 'Verification could not be confirmed.');}
    finally {setBusy(false);}
  }
  async function cancelPending() {
    if (!factor || factor.verified || !mayEnroll || busy || unknown || !current()) return; setBusy(true); setError('');
    try {
      if (managed && (!(await session.recheckEmailVerification()) || !current())) throw new Error('Verify your email before cancelling an authenticator setup.');
      const result = await request('auth/mfa/cancel-enrollment', {body: {factor_id: factor.id}});
      if (result.id !== factor.id || result.factor_type !== 'totp' || result.status !== 'revoked') throw new AdminRequestError('Cancellation could not be confirmed. Recheck the setup.', {outcomeUnknown: true});
      setSetup(null); setConfirmCancel(false); setReload((value) => value + 1);
    } catch (failure) {if (failure instanceof AdminRequestError && failure.outcomeUnknown) setUnknown(true); setError(failure instanceof Error ? failure.message : 'Cancellation could not be confirmed.');}
    finally {setBusy(false);}
  }
  async function recheck() {
    if (busy) return; setBusy(true); setError('');
    try {await session.refresh(); setSetup(null); setReload((value) => value + 1);}
    catch (failure) {setError(failure instanceof Error ? failure.message : 'Your session could not be checked.');}
    finally {setBusy(false);}
  }
  function signIn() {session.clearLocalSession(); onSignIn();}
  if (!available) return <><PageHeader title="Authenticator" /><p>Authenticator access is unavailable for this account.</p><Button onClick={onBack}>Back</Button></>;
  return <><PageHeader title="Authenticator" subtitle="Manage two-step access for this account." /><Card className="admin-security-card admin-auth-task">{loading ? <LoadingState label="Checking authenticator" /> : <div className="admin-auth-form">{user?.assuranceLevel === 2 && <p>Two-step verification is complete for this session.</p>}{setup && <><p>Add this key to your authenticator as Collect, then enter its six-digit code.</p><Field label="Setup key" htmlFor="authenticator-secret"><input id="authenticator-secret" className="admin-input" value={setup.secret} readOnly /></Field></>}{factor && !factor.verified && !setup && <p>Setup is pending. Enter a code if you saved the key, or cancel this setup and connect again.</p>}{factors.length > 1 && !setup && <Field label="Authenticator" htmlFor="authenticator-factor"><select id="authenticator-factor" className="admin-input" value={factor?.id ?? ''} onChange={(event) => setSelected(event.target.value)} disabled={busy}>{factors.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></Field>}{factor && <form className="admin-auth-form" onSubmit={verify}><Field label="Authenticator code" htmlFor="authenticator-code"><input id="authenticator-code" className="admin-input" type="password" inputMode="numeric" autoComplete="one-time-code" pattern="[0-9]{6}" maxLength={6} required value={code} onChange={(event) => setCode(event.target.value.replace(/[^0-9]/g, ''))} disabled={busy || unknown} /></Field><Button variant="primary" type="submit" loading={busy} disabled={unknown}>Verify code</Button></form>}{!factor && mayEnroll && <Button variant="primary" loading={busy} disabled={unknown} onClick={() => void enroll()}>Connect authenticator</Button>}{factor && !factor.verified && mayEnroll && !confirmCancel && <Button disabled={busy || unknown} onClick={() => setConfirmCancel(true)}>Cancel pending setup</Button>}{confirmCancel && <><p>Remove this pending setup?</p><Button variant="danger" disabled={busy || unknown} onClick={() => void cancelPending()}>Confirm cancellation</Button><Button disabled={busy} onClick={() => setConfirmCancel(false)}>Keep setup</Button></>}{error && <p role="alert" className="admin-auth-feedback">{error}</p>}{unknown && <Button disabled={busy} onClick={() => void recheck()}>Recheck setup and session</Button>}{error && <Button disabled={busy} onClick={signIn}>Sign in again</Button>}<Button onClick={onBack} disabled={busy}>Back</Button></div>}</Card></>;
}
