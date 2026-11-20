import {SUPABASE_PROJECT_ORIGIN} from './config';

const productionOrigin = 'https://platform-admin.collect.ikanisa.com';
const noticeKeys = ['collect.admin.pending-attempts.v1', 'collect.admin.mfa-intent.v1'];
const tabPrefix = 'collect.admin.notification-management.';
const sharedPrefixes = ['collect.admin.logout-intent.v1.', 'collect.privacy-review.v1.'];

// The serving Flutter clients used unqualified storage keys. Production is
// replacing the self-hosted database at the same origin. QA keeps its database.
const managedProduction = import.meta.env.VITE_ADMIN_EXPECTED_ORIGIN === productionOrigin &&
  import.meta.env.VITE_ADMIN_BACKEND === 'supabase' &&
  import.meta.env.VITE_SUPABASE_PROJECT_ORIGIN === SUPABASE_PROJECT_ORIGIN &&
  globalThis.location?.origin === productionOrigin;

export function custodyKey(key: string): string {
  return managedProduction ? `collect.realm.${SUPABASE_PROJECT_ORIGIN}:${key}` : key;
}

/** Only inspect key names. Earlier account data stays in its original storage. */
export function hasPredecessorCustody(): boolean {
  if (!managedProduction) return false;
  try {
    for (let index = 0; index < sessionStorage.length; index++) {
      const key = sessionStorage.key(index);
      if (key && (noticeKeys.includes(key) || key.startsWith(tabPrefix) && key.endsWith('.collect.admin.pending-attempts.v1'))) return true;
    }
    for (let index = 0; index < localStorage.length; index++) {
      const key = localStorage.key(index);
      if (key && sharedPrefixes.some(prefix => key.startsWith(prefix))) return true;
    }
    return false;
  } catch {
    // A browser denying storage cannot establish that earlier work is absent.
    return true;
  }
}
