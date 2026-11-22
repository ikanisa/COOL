import {ApiError} from '../core.js';

export function failAdminAccount(code, status = 403) {
  const message = code === 'admin_access_not_approved'
    ? 'This email does not have Admin access. Contact the super admin to be added.'
    : 'This Admin action is unavailable.';
  throw new ApiError(status, code, message);
}

export const adminMfaDenied = () => new ApiError(403, 'mfa_admin_denied', 'This authenticator action is unavailable.');

export const adminMfaPending = () => new ApiError(503, 'mfa_operation_unknown',
  'The authenticator result could not be confirmed. Recheck your setup or sign-in before trying again.');
