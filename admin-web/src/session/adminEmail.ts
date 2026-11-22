/* eslint-disable no-control-regex -- Reject controls in Admin email addresses. */
const LOCAL_PART = /^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+$/;
const DOMAIN_LABEL = /^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/;

export function isCanonicalAdminEmail(value: unknown): value is string {
  if (typeof value !== 'string' || value.length > 254 || value !== value.trim().toLowerCase() ||
      /[\s\x00-\x1f\x7f]/.test(value)) return false;
  const [local, domain, extra] = value.split('@');
  if (!local || !domain || extra !== undefined || local.length > 64 || local.startsWith('.') ||
      local.endsWith('.') || local.includes('..') || !LOCAL_PART.test(local)) return false;
  const labels = domain.split('.');
  return labels.length >= 2 && labels.every(label => label.length <= 63 && DOMAIN_LABEL.test(label));
}

export function normalizeAdminEmail(input: string): string {
  const email = input.trim().toLowerCase();
  if (!isCanonicalAdminEmail(email)) throw new Error('Check the email address.');
  return email;
}
