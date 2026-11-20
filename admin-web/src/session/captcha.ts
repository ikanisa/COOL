/* eslint-disable no-control-regex -- Reject ASCII control characters in challenge tokens. */
import {AdminRequestError} from '../api/client';

const ENDPOINT = '/functions/v1/collect-api/v1/security/challenge';
let active: {attempt: string; reject: (reason: Error) => void} | null = null;

export function parseCaptchaEnvelope(input: unknown, attempt: string): string {
  let value = input;
  if (typeof value === 'string') {
    if (value.length > 4096) throw new Error('Invalid challenge response.');
    try {value = JSON.parse(value);} catch {throw new Error('Invalid challenge response.');}
  }
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Invalid challenge response.');
  const data = value as Record<string, unknown>;
  if (Object.keys(data).length !== 3 || data.type !== 'collect.turnstile.v1' || data.attempt_id !== attempt || typeof data.token !== 'string' || !data.token || data.token.length > 2048 || /[\x00-\x20\x7f]/.test(data.token)) throw new Error('Invalid challenge response.');
  return data.token;
}

export interface CaptchaEnvironment { window: Window; document: Document; crypto: Crypto }

/** The challenge document is same-origin; the backend verifies the token itself. */
export async function acquireSameOriginCaptcha(environment: CaptchaEnvironment = {window, document, crypto}): Promise<string> {
  const {window: host, document: doc, crypto: cryptography} = environment;
  if (active || !doc.body || host.location.protocol !== 'https:' || !host.isSecureContext || !cryptography.randomUUID) throw new AdminRequestError('Security verification is unavailable.');
  const attempt = cryptography.randomUUID();
  const url = new URL(ENDPOINT, host.location.origin);
  url.searchParams.set('attempt_id', attempt);
  url.searchParams.set('parent_origin', host.location.origin);
  url.searchParams.set('theme', 'auto');
  const previousFocus = doc.activeElement;
  const dialog = doc.createElement('dialog');
  dialog.setAttribute('aria-label', 'Verify your sign-in');
  dialog.className = 'admin-challenge-dialog';
  const frame = doc.createElement('iframe');
  frame.title = 'Collect security verification';
  frame.src = url.href;
  frame.referrerPolicy = 'no-referrer';
  frame.setAttribute('sandbox', 'allow-scripts allow-same-origin');
  frame.className = 'admin-challenge-frame';
  const cancel = doc.createElement('button');
  cancel.type = 'button'; cancel.textContent = 'Cancel'; cancel.className = 'admin-btn admin-btn--secondary admin-challenge-cancel';
  dialog.append(frame, cancel);
  let settle!: (token: string) => void;
  let reject!: (error: Error) => void;
  const result = new Promise<string>((resolve, fail) => {settle = resolve; reject = fail;});
  active = {attempt, reject};
  const failure = () => reject(new AdminRequestError('Security verification was cancelled.'));
  const onMessage = (event: MessageEvent) => {
    if (event.origin !== url.origin || event.source !== frame.contentWindow || active?.attempt !== attempt) return;
    try {settle(parseCaptchaEnvelope(event.data, attempt));}
    catch {reject(new AdminRequestError('Security verification could not finish.'));}
  };
  const onCancel = (event: Event) => {event.preventDefault(); failure();};
  host.addEventListener('message', onMessage);
  cancel.addEventListener('click', onCancel);
  dialog.addEventListener('cancel', onCancel);
  const timeout = setTimeout(() => reject(new AdminRequestError('Security verification expired.')), 120_000);
  try {
    doc.body.append(dialog); dialog.showModal(); cancel.focus();
    return await result;
  } finally {
    clearTimeout(timeout);
    if (active?.attempt === attempt) active = null;
    host.removeEventListener('message', onMessage);
    cancel.removeEventListener('click', onCancel);
    dialog.removeEventListener('cancel', onCancel);
    if (dialog.open) dialog.close();
    dialog.remove();
    if (previousFocus instanceof HTMLElement) previousFocus.focus();
  }
}

export function cancelSameOriginCaptcha(): void {
  active?.reject(new AdminRequestError('Security verification was cancelled.'));
  active = null;
}
