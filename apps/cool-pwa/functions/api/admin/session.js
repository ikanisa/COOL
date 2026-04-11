import { json, loadAdminContext } from '../../_shared/supabase.js';

export async function onRequestGet(context) {
  const admin = await loadAdminContext(context);
  if (admin.response) {
    return admin.response;
  }

  const issuedAt = admin.session?.issuedAt ? Date.parse(admin.session.issuedAt) : Date.now();
  const sessionAgeSeconds = Math.max(0, Math.floor((Date.now() - issuedAt) / 1000));

  return json({
    success: true,
    live: true,
    user: admin.user,
    access: admin.access,
    session: {
      id: admin.sessionId || null,
      age_seconds: sessionAgeSeconds,
      reauth_required: admin.session?.reauthRequired === true,
      issued_at: admin.session?.issuedAt || null,
    },
  });
}
