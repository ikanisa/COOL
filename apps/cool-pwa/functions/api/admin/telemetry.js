import {
  getAdminSessionRecord,
  getSessionIdFromCookie,
  json,
  recordAdminBrowserEvent,
} from '../../_shared/supabase.js';

export async function onRequestPost(context) {
  const payload = await readTelemetryPayload(context.request);
  if (!payload || typeof payload !== 'object') {
    return json({ success: false, ignored: true }, { status: 202 });
  }

  const sessionId = getSessionIdFromCookie(context.request);
  const session = sessionId ? await getAdminSessionRecord(context, sessionId) : null;

  await recordAdminBrowserEvent(context, {
    eventName: payload.name || 'browser_event',
    sessionId,
    userId: session?.userId || null,
    route: payload.path || null,
    path: payload.path || null,
    online: payload.online === true,
    appVersion: payload.version || 'unknown',
    clientTs: payload.ts || new Date().toISOString(),
    detail: payload.detail && typeof payload.detail === 'object'
      ? payload.detail
      : {},
  });

  return json({ success: true }, { status: 202 });
}

async function readTelemetryPayload(request) {
  const contentType = request.headers.get('content-type') || '';

  if (contentType.includes('application/json')) {
    return await request.json().catch(() => null);
  }

  const text = await request.text().catch(() => '');
  if (!text) {
    return null;
  }

  try {
    return JSON.parse(text);
  } catch (_) {
    return null;
  }
}
