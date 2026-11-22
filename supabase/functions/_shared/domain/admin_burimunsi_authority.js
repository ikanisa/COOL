import { adminSessionOriginMatches } from '../admin-security.js';
import { applicationWork, applicationWorkTuple } from '../application-fence.js';
import { verifyDeploymentProfile } from '../deployment-profile.js';
import { requireFreshAdminEmail } from './admin_email_policy.js';
import { preliminaryCurrentOwner } from './admin_owner_precheck.js';
import { ApiError } from './core.js';

export const BURI_ADMIN_PRIVATE_HEADERS = Object.freeze({
  'Cache-Control': 'no-store, private',
  'Pragma': 'no-cache',
  'Vary': 'Cookie, Origin',
});

/** Check the current Owner and the Admin request fence before selecting a collection. */
export async function requireBuriMunsiOwner({
  request,
  env,
  account,
  permissions,
  ownerMessage,
  unavailableCode,
  unavailableMessage,
}) {
  if (
    !await preliminaryCurrentOwner(env, account) ||
    !permissions.every((permission) => account.permissions.includes(permission))
  ) {
    throw new ApiError(403, 'owner_required', ownerMessage);
  }
  requireFreshAdminEmail(account);

  const work = applicationWork(env);
  const profile = await verifyDeploymentProfile(env);
  if (
    work.kind !== 'http_admin' || env.DB?.applicationWork !== work ||
    applicationWorkTuple(work)[2] !== env.BUILD_SOURCE_ID ||
    !adminSessionOriginMatches(request, env, profile, account)
  ) {
    throw new ApiError(503, unavailableCode, unavailableMessage);
  }
}
