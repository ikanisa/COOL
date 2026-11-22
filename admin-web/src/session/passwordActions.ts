import {AdminRequestError, type AdminApiClient, type AdminRequest} from '../api/client';

interface PasswordConfirmation {
  current: () => boolean;
  confirmAnonymous: () => Promise<boolean>;
}

export async function completePasswordSetup(
  {token, password, invite}: {token: string; password: string; invite: boolean},
  {request, current, confirmAnonymous}: PasswordConfirmation & {request: AdminApiClient['request']},
): Promise<void> {
  if (!/^\S{32,512}$/.test(token) || password.length < 12 || password.length > 128) throw new Error('Check the password and link.');
  const result = await request('auth/complete-password', {body: {token, password, invite}, authenticated: false}, {isCurrent: current});
  if (result.ok !== true || !current() || !(await confirmAnonymous())) {
    throw new AdminRequestError('The password result is not confirmed. Sign in using your email code or request a new reset link.', {outcomeUnknown: true});
  }
}

export async function changeAccountPassword(
  {currentPassword, newPassword}: {currentPassword: string; newPassword: string},
  {request, current, confirmAnonymous, verifyEmail}: PasswordConfirmation & {request: AdminRequest; verifyEmail?: () => Promise<boolean>},
): Promise<void> {
  if (!currentPassword || currentPassword.length > 512 || newPassword.length < 12 || newPassword.length > 128 || currentPassword === newPassword) {
    throw new Error('Enter your current password and a different new password of 12 to 128 characters.');
  }
  if (verifyEmail && !(await verifyEmail())) {
    throw new AdminRequestError('Verify your email before making this change.', {code: 'recent_email_sign_in_required'});
  }
  if (!current()) throw new AdminRequestError('Your sign-in changed. Reopen account security.');
  const result = await request('auth/change-password', {body: {currentPassword, newPassword}, authenticated: true, expectedStatus: 200});
  if (result.ok !== true || !current() || !(await confirmAnonymous())) {
    throw new AdminRequestError('The password result is not confirmed. Sign in using your email code or request a reset.', {outcomeUnknown: true});
  }
}
