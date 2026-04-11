import {
  getSessionIdFromCookie,
  json,
  makeClearSessionCookieHeader,
  recordAdminBrowserEvent,
  revokeAdminSession,
} from '../../_shared/supabase.js';

export async function onRequestPost(context) {
  const sessionId = getSessionIdFromCookie(context.request);
  if (sessionId) {
    await revokeAdminSession(context, sessionId, 'signed_out');
    await recordAdminBrowserEvent(context, {
      eventName: 'admin_auth_logout',
      sessionId,
      path: new URL(context.request.url).pathname,
      detail: { signed_out: true },
    });
  }

  return json(
    { success: true, message: 'Admin session cleared.' },
    {
      headers: {
        'Set-Cookie': makeClearSessionCookieHeader(),
      },
    },
  );
}
