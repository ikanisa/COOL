import {keychainStore, validateKeychainHelper, withSessionLock} from "./keychain_store.ts";
import {resolveStoredSession} from "./session_renewal.ts";
export {productionOrigin, scopedRuntime} from "./session_renewal.ts";

export async function runtimeCredentials(
  environment: NodeJS.ProcessEnv = process.env,
  options: {allowRefresh?: boolean} = {},
): Promise<NodeJS.ProcessEnv> {
  if (environment.COLLECT_SUPABASE_ANON_KEY && environment.COLLECT_OPERATOR_ACCESS_TOKEN) return environment;
  const helper = environment.COLLECT_OPERATOR_KEYCHAIN_HELPER;
  if (!helper) return environment;
  await validateKeychainHelper(helper);
  return withSessionLock(helper, () => resolveStoredSession(keychainStore(helper), environment, fetch, Date.now, options));
}
