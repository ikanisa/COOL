import {afterEach, describe, expect, it, vi} from 'vitest';
import {googleAuthorizationUrl, googleAvailable, openGooglePopup} from '../../src/session/google';

afterEach(() => vi.restoreAllMocks());

describe('Google popup handoff', () => {
  it('ignores foreign messages and accepts only the current popup and state', async () => {
    const state = 'a'.repeat(43), origin = 'https://platform-admin.collect.ikanisa.com';
    const popup = {closed: false, location: {href: ''}, close: vi.fn()} as unknown as Window;
    vi.spyOn(window, 'open').mockReturnValue(popup);
    const handoff = openGooglePopup(state, origin);
    const pending = handoff.authorize(async () => 'https://rrlduytparvsjfmegalh.supabase.co/auth/v1/authorize');
    await vi.waitFor(() => expect(popup.location.href).toContain('/auth/v1/authorize'));
    let settled = false; void pending.then(() => {settled = true;});
    window.dispatchEvent(new MessageEvent('message', {origin: 'https://evil.example', source: popup, data: {type: 'collect-google-auth', state, code: 'b'.repeat(43)}}));
    await Promise.resolve(); expect(settled).toBe(false);
    window.dispatchEvent(new MessageEvent('message', {origin, source: popup, data: {type: 'collect-google-auth', state, code: 'b'.repeat(43)}}));
    await expect(pending).resolves.toEqual({state, code: 'b'.repeat(43), error: undefined});
    expect(popup.close).toHaveBeenCalledOnce();
  });

  it('closes immediately when cancelled during the pending start request', async () => {
    const popup = {closed: false, location: {href: ''}, close: vi.fn()} as unknown as Window;
    vi.spyOn(window, 'open').mockReturnValue(popup);
    let finish!: (url: string) => void;
    const handoff = openGooglePopup('a'.repeat(43), 'https://platform-admin.collect.ikanisa.com');
    const pending = handoff.authorize(() => new Promise<string>((resolve) => {finish = resolve;}));
    handoff.cancel();
    await expect(pending).rejects.toThrow('cancelled');
    expect(popup.close).toHaveBeenCalledOnce();
    finish('https://rrlduytparvsjfmegalh.supabase.co/auth/v1/authorize');
    await Promise.resolve();
    expect(popup.location.href).toBe('');
  });
});

describe('Configured Google authorization origins', () => {
  const admin = 'https://platform-admin.collect.ikanisa.com';
  const managed = 'https://rrlduytparvsjfmegalh.supabase.co', otherProject = 'https://other.supabase.co';
  const url = (project: string, callback: string = admin) => {
    const target = new URL(project + '/auth/v1/authorize'), redirect = new URL(callback + '/functions/v1/collect-api/v1/auth/google/callback');
    redirect.searchParams.set('state', 'a'.repeat(43));
    target.search = new URLSearchParams({provider: 'google', redirect_to: redirect.href, code_challenge: 'b'.repeat(43), code_challenge_method: 's256', scopes: 'openid email profile', prompt: 'select_account'}).toString();
    return target.href;
  };

  it('accepts the configured Collect Cloud project', () => {
    expect(googleAvailable('supabase', true, managed, admin)).toBe(true);
    expect(googleAuthorizationUrl(url(managed), admin, managed)).toBe(url(managed));
    expect(() => googleAuthorizationUrl(url(otherProject), admin, managed)).toThrow();
    expect(() => googleAuthorizationUrl(url(managed), admin, otherProject)).toThrow();
    expect(googleAvailable('supabase', false, managed, admin)).toBe(false);
  });

  it('rejects the previous authorization issuer', () => {
    const previous = 'https://supabase.collect.ikanisa.com';
    expect(googleAvailable('supabase', true, previous, admin)).toBe(false);
    expect(() => googleAuthorizationUrl(url(previous), admin, previous)).toThrow();
  });

  it('rejects foreign projects, mismatched callbacks and origin lookalikes', () => {
    expect(googleAvailable('supabase', true, 'https://evil.example', admin)).toBe(false);
    expect(googleAvailable('supabase', true, managed + '.evil.example', admin)).toBe(false);
    expect(googleAvailable('supabase', true, undefined, admin)).toBe(false);
    expect(googleAvailable('cloudflare', true, managed, admin)).toBe(false);
    expect(() => googleAuthorizationUrl(url(managed, 'https://admin-supabase-qa.collect.ikanisa.com'), admin, managed)).toThrow();
    expect(() => googleAuthorizationUrl(url('https://evil.example'), admin, 'https://evil.example')).toThrow();
    expect(() => googleAuthorizationUrl(url(managed), admin, undefined)).toThrow();
    expect(() => googleAuthorizationUrl(url(managed), 'https://platform-admin.collect.ikanisa.com.evil.example', managed)).toThrow();
  });
});
