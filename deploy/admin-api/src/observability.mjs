// Only closed, source-defined labels enter the health log. No request, error,
// actor, URL, SMS, credential or provider payload is an accepted argument.
const events = new Set(['service_degraded', 'rate_limited', 'unexpected_failure', 'email_dispatch_failed', 'cron_cleanup_failed']);
const components = new Set(['auth', 'core', 'operations', 'reconciliation', 'sms', 'gateway', 'email', 'account', 'cron']);
export function recordAdminHealth(event, component, emit = value => console.warn(value)) {
  if (!events.has(event) || !components.has(component)) return;
  emit(JSON.stringify({ service: 'collect_admin', schema_version: 1, event, component }));
}
export function adminHealthComponent(path) {
  const route = path.replace(/^\/api\/admin/, '');
  if (route.startsWith('/auth/')) return 'auth';
  if (route.startsWith('/core/')) return 'core';
  if (route.startsWith('/operations/')) return 'operations';
  if (route.startsWith('/reconciliations')) return 'reconciliation';
  if (route.startsWith('/sms/')) return 'sms';
  if (route.startsWith('/gateway') || path.startsWith('/api/gateway')) return 'gateway';
  if (route.startsWith('/emails')) return 'email';
  return 'account';
}
