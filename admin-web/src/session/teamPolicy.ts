export const TEAM_OWNER_EMAIL = 'info@ikanisa.com';
export const TEAM_MANAGE = 'admin_users.manage';
export const TEAM_MEMBER_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export const TEAM_VERIFICATION_REQUIRED = 'Verify your current owner sign-in before managing team access.';

/** Check the owning session before every access, including after a digest. */
export function bindTeamStorage(requireCurrent: () => void, resolveStorage = () => sessionStorage): Storage {
  return {
    get length() { return 0; },
    clear() { throw new Error('Unsupported recovery operation.'); },
    key() { return null; },
    getItem(key) {
      requireCurrent();
      return resolveStorage().getItem(key);
    },
    setItem(key, value) {
      requireCurrent();
      resolveStorage().setItem(key, value);
    },
    removeItem(key) {
      requireCurrent();
      resolveStorage().removeItem(key);
    },
  };
}
