// The production handler defaults to the signed Cloud protocol. These
// fixtures exercise post-admission jobs logic without a separate ticket store.
export const jobDispatchFixture = Object.freeze({
  verify: (env, _payload, token) =>
    typeof env.FIXTURE_JOB_TOKEN === 'string' && token === 'Bearer ' + env.FIXTURE_JOB_TOKEN,
  claim: async () => true,
  complete: async () => true,
  admitNativeSms: () => ({allowed: true, enabled: false}),
});

export const withJobDispatchFixture = (reader) => () => ({
  ...reader(),
  COLLECT_JOB_AUTH_MODE: 'supabase_dispatch_hmac_v1',
});
