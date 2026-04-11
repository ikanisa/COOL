import {
  error,
  getAdminSessionRecord,
  getSessionIdFromCookie,
  json,
  makeClearSessionCookieHeader,
  makeSessionCookieHeader,
  recordAdminBrowserEvent,
  revokeAdminSession,
  supabaseFetch,
  updateAdminSessionTokens,
} from '../../_shared/supabase.js';

export async function onRequestPost(context) {
  const sessionId = getSessionIdFromCookie(context.request);
  if (!sessionId) {
    return error('No valid session to refresh.', {
      status: 401,
      code: 'REFRESH_SESSION_REQUIRED',
      headers: {
        'Set-Cookie': makeClearSessionCookieHeader(),
      },
    });
  }

  const session = await getAdminSessionRecord(context, sessionId);
  if (!session || session.revokedAt) {
    await revokeAdminSession(context, sessionId, 'refresh_on_missing_session');
    return error('No valid session to refresh.', {
      status: 401,
      code: 'REFRESH_SESSION_REQUIRED',
      headers: {
        'Set-Cookie': makeClearSessionCookieHeader(),
      },
    });
  }

  const result = await supabaseFetch(
    context,
    '/auth/v1/token?grant_type=refresh_token',
    {
      method: 'POST',
      body: { refresh_token: session.refreshToken },
    },
  );

  if (!result.response.ok) {
    await revokeAdminSession(context, sessionId, 'refresh_rejected');
    await recordAdminBrowserEvent(context, {
      eventName: 'admin_auth_refresh_failed',
      sessionId,
      userId: session.userId,
      path: new URL(context.request.url).pathname,
      detail: { status: result.response.status || 500 },
    });

    return error('Could not refresh the COOL admin session.', {
      status: 401,
      code: 'REFRESH_REJECTED',
      headers: {
        'Set-Cookie': makeClearSessionCookieHeader(),
      },
    });
  }

  const accessToken = result.data?.access_token || '';
  const refreshToken = result.data?.refresh_token || '';

  const updatedSession = await updateAdminSessionTokens(context, sessionId, {
    accessToken,
    refreshToken,
    metadata: {
      ...(session.metadata || {}),
      refreshed_at: new Date().toISOString(),
    },
  });

  if (!updatedSession) {
    return error('Could not refresh the COOL admin session.', {
      status: 500,
      code: 'REFRESH_PERSIST_FAILED',
      headers: {
        'Set-Cookie': makeClearSessionCookieHeader(),
      },
    });
  }

  await recordAdminBrowserEvent(context, {
    eventName: 'admin_auth_refresh_succeeded',
    sessionId,
    userId: session.userId,
    path: new URL(context.request.url).pathname,
    detail: { refreshed: true },
  });

  return json(
    {
      success: true,
      user: result.data?.user || null,
    },
    {
      headers: {
        'Set-Cookie': makeSessionCookieHeader(sessionId),
      },
    },
  );
}
