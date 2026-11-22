import { execFileSync } from 'node:child_process';
import { MANAGED_SUPABASE_ORIGIN } from '../../supabase/functions/_shared/deployment-profile.js';
import { sha256 } from './pwa-assets.mjs';

export function publicConfiguration(root, mode) {
  if (mode === 'fixture') {
    const origin = process.env.ADMIN_PWA_FIXTURE_ORIGIN ?? 'http://127.0.0.1:4175';
    const url = new URL(origin);
    if (url.protocol !== 'http:' || url.hostname !== '127.0.0.1' || url.origin !== origin || !url.port) {
      throw new Error('React Admin fixture requires an explicit HTTP loopback port.');
    }
    return {
      defines: {
        VITE_ADMIN_EXPECTED_ORIGIN: origin, VITE_ADMIN_BACKEND: 'supabase',
        VITE_ADMIN_CAPTCHA_ENABLED: 'false', VITE_ADMIN_GOOGLE_ENABLED: 'false',
        VITE_SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_react_admin_local_fixture',
        VITE_SUPABASE_PROJECT_ORIGIN: MANAGED_SUPABASE_ORIGIN,
      },
    };
  }
  const script = [
    'import json, os, sys',
    'from pathlib import Path',
    'from scripts.supabase.admin_build_config import configuration',
    'print(json.dumps(configuration(dict(os.environ), Path.cwd(), qualification=sys.argv[1] == "qualification")))',
  ].join('\n');
  let validated;
  try {
    validated = JSON.parse(execFileSync('python3', ['-c', script, mode], { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }));
  } catch {
    throw new Error('Supply the reviewed Admin origin, Supabase project, public key and security settings.');
  }
  const [settings, metadata] = validated;
  const defines = {
    VITE_ADMIN_EXPECTED_ORIGIN: settings.ADMIN_APP_URL, VITE_ADMIN_BACKEND: 'supabase',
    VITE_ADMIN_CAPTCHA_ENABLED: settings.AUTH_CAPTCHA_ENABLED, VITE_ADMIN_GOOGLE_ENABLED: settings.GOOGLE_AUTH_ENABLED,
    VITE_SUPABASE_PUBLISHABLE_KEY: settings.SUPABASE_PUBLISHABLE_KEY, VITE_SUPABASE_PROJECT_ORIGIN: settings.SUPABASE_URL,
  };
  return {
    defines,
    metadata: {
      ...metadata,
      environment: mode,
      public_build_config_sha256: sha256(JSON.stringify({ defines, settings, metadata })),
    },
  };
}
