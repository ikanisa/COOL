// Public routing constants only. No environment secrets or host Auth state.
export const PUBLIC_CONFIG = Object.freeze({
  format: 'collect.supabase.static-host.v1',
  backend: 'supabase',
  frontendOrigin: 'https://platform-admin.collect.ikanisa.com',
  supabaseOrigin: 'https://rrlduytparvsjfmegalh.supabase.co',
  memberPrefix: '/functions/v1/collect-api',
  adminPrefix: '/functions/v1/admin-api',
});

export function validatePublicConfiguration(value) {
  if (!value || Object.getPrototypeOf(value) !== Object.prototype ||
      Object.keys(value).length !== Object.keys(PUBLIC_CONFIG).length ||
      Object.keys(PUBLIC_CONFIG).some(key => value[key] !== PUBLIC_CONFIG[key]) ||
      Object.keys(value).some(key => !Object.hasOwn(PUBLIC_CONFIG, key))) {
    throw new TypeError('Expected the exact public Collect Supabase host configuration');
  }
  return Object.freeze({...value});
}
