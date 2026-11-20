import {afterEach, describe, expect, it, vi} from 'vitest';
import {acquireSameOriginCaptcha, cancelSameOriginCaptcha, type CaptchaEnvironment} from '../../src/session/captcha';

afterEach(() => {cancelSameOriginCaptcha(); vi.restoreAllMocks(); document.body.replaceChildren();});

describe('same-origin challenge frame', () => {
  it('accepts only the active frame and exact origin, and restores focus', async () => {
    const focus = document.createElement('button'); document.body.append(focus); focus.focus();
    HTMLDialogElement.prototype.showModal = function () {this.setAttribute('open', '');};
    HTMLDialogElement.prototype.close = function () {this.removeAttribute('open');};
    const events = new EventTarget();
    const host = {location: {protocol: 'https:', origin: 'https://platform-admin.collect.ikanisa.com'}, isSecureContext: true, addEventListener: events.addEventListener.bind(events), removeEventListener: events.removeEventListener.bind(events)} as unknown as Window;
    const attempt = '0d7bfc80-d88c-4b4c-9f7d-9935f6c5aaf1';
    const cryptography = {randomUUID: () => attempt} as unknown as Crypto;
    const pending = acquireSameOriginCaptcha({window: host, document, crypto: cryptography} satisfies CaptchaEnvironment);
    const frame = document.querySelector('iframe')!;
    const url = new URL(frame.src);
    expect(url.origin).toBe(host.location.origin);
    expect(url.searchParams.get('attempt_id')).toBe(attempt);
    expect(frame.getAttribute('sandbox')).toBe('allow-scripts allow-same-origin');
    let settled = false; void pending.then(() => {settled = true;});
    events.dispatchEvent(new MessageEvent('message', {origin: 'https://evil.example', source: frame.contentWindow, data: {type: 'collect.turnstile.v1', attempt_id: attempt, token: 'bad'}}));
    await Promise.resolve(); expect(settled).toBe(false);
    events.dispatchEvent(new MessageEvent('message', {origin: host.location.origin, source: frame.contentWindow, data: {type: 'collect.turnstile.v1', attempt_id: attempt, token: 'valid-token'}}));
    await expect(pending).resolves.toBe('valid-token');
    expect(document.querySelector('dialog')).toBeNull();
    expect(document.activeElement).toBe(focus);
  });
});
