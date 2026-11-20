import {describe, expect, it} from 'vitest';
import {readAdminConfig} from '../../src/config';

describe('public Admin configuration', () => {
  const valid = {VITE_ADMIN_EXPECTED_ORIGIN: 'http://localhost:4173', VITE_ADMIN_BACKEND: 'cloudflare',
    VITE_ADMIN_CAPTCHA_ENABLED: 'false', VITE_ADMIN_GOOGLE_ENABLED: 'false'};

  it('accepts an explicitly configured same-origin local fixture', () => {
    expect(readAdminConfig(valid, 'http://localhost:4173')).toMatchObject({backend: 'cloudflare', captchaEnabled: false, googleEnabled: false});
  });

  it('refuses missing policies, foreign origins and unqualified credentials', () => {
    expect(() => readAdminConfig({...valid, VITE_ADMIN_CAPTCHA_ENABLED: undefined}, 'http://localhost:4173')).toThrow();
    expect(() => readAdminConfig(valid, 'https://other.example')).toThrow();
    expect(() => readAdminConfig({...valid, VITE_ADMIN_BACKEND: 'supabase', VITE_SUPABASE_PUBLISHABLE_KEY: 'secret_key'}, 'http://localhost:4173')).toThrow();
    expect(() => readAdminConfig({...valid, VITE_ADMIN_GOOGLE_ENABLED: 'true'}, 'http://localhost:4173')).toThrow();
    expect(() => readAdminConfig({...valid, VITE_ADMIN_CAPTCHA_ENABLED: 'true'}, 'http://localhost:4173')).toThrow();
  });

  it('accepts the managed Supabase project and rejects the retired and foreign origins', () => {
    const candidate = {...valid, VITE_ADMIN_BACKEND: 'supabase', VITE_SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_' + 'a'.repeat(32),
      VITE_SUPABASE_PROJECT_ORIGIN: 'https://rrlduytparvsjfmegalh.supabase.co'};
    expect(readAdminConfig(candidate, 'http://localhost:4173')).toMatchObject({backend: 'supabase', supabaseProjectOrigin: 'https://rrlduytparvsjfmegalh.supabase.co'});
    expect(readAdminConfig({...candidate, VITE_ADMIN_EXPECTED_ORIGIN: 'https://platform-admin.collect.ikanisa.com', VITE_ADMIN_GOOGLE_ENABLED: 'true'}, 'https://platform-admin.collect.ikanisa.com')).toMatchObject({googleEnabled: true, supabaseProjectOrigin: 'https://rrlduytparvsjfmegalh.supabase.co'});
    expect(() => readAdminConfig({...candidate, VITE_ADMIN_GOOGLE_ENABLED: 'true', VITE_SUPABASE_PROJECT_ORIGIN: ''}, 'http://localhost:4173')).toThrow('Google sign-in');
    expect(() => readAdminConfig({...candidate, VITE_SUPABASE_PROJECT_ORIGIN: 'https://supabase.collect.ikanisa.com'}, 'http://localhost:4173')).toThrow('project origin');
    expect(() => readAdminConfig({...candidate, VITE_SUPABASE_PROJECT_ORIGIN: 'https://attacker.example'}, 'http://localhost:4173')).toThrow('project origin');
    expect(() => readAdminConfig({...candidate, VITE_SUPABASE_PROJECT_ORIGIN: 'https://supabase.collect.ikanisa.com.attacker.example'}, 'http://localhost:4173')).toThrow('project origin');
    expect(() => readAdminConfig({...candidate, VITE_SUPABASE_PROJECT_ORIGIN: 'https://supabase.collect.ikanisa.com/path'}, 'http://localhost:4173')).toThrow('project origin');
  });
});
