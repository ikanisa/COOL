import {
  countOtpRateEvents,
  createAdminSession,
  error,
  getClientIp,
  hashActorKey,
  json,
  makeSessionCookieHeader,
  normalizeAccess,
  readJson,
  recordAdminBrowserEvent,
  recordOtpRateEvent,
  supabaseFetch,
} from '../../_shared/supabase.js';

const VERIFY_IP_LIMIT = 10;
const VERIFY_PHONE_LIMIT = 5;
const VERIFY_WINDOW_MS = 15 * 60 * 1000;
const GENERIC_VERIFY_FAILURE =
  'The verification code could not be accepted. Request a new code and try again.';

export async function onRequestPost(context) {
  const body = await readJson(context.request);
  const phone = body?.phone?.toString().trim() || '';
  const code = body?.code?.toString().trim() || '';

  if (!phone || !code) {
    return error('Phone number and verification code are required.', {
      status: 400,
      code: 'OTP_INPUT_REQUIRED',
    });
  }

  const normalizedPhone = phone.startsWith('+') ? phone : `+${phone}`;
  const rateLimit = await resolveRateLimit(context, normalizedPhone);
  if (rateLimit.limited) {
    return error('Too many verification attempts. Wait a few minutes and try again.', {
      status: 429,
      code: 'OTP_RATE_LIMITED',
    });
  }

  const result = await supabaseFetch(context, '/functions/v1/verify-otp', {
    method: 'POST',
    body: { phone: normalizedPhone, code },
  });

  if (!result.response.ok) {
    await Promise.all([
      recordOtpRateEvent(context, {
        action: 'verify_ip',
        actorKey: rateLimit.ipKey,
        outcome: 'failed',
        phone: normalizedPhone,
      }),
      recordOtpRateEvent(context, {
        action: 'verify_phone',
        actorKey: rateLimit.phoneKey,
        outcome: 'failed',
        phone: normalizedPhone,
      }),
      recordAdminBrowserEvent(context, {
        eventName: 'admin_auth_verify_otp_failed',
        path: new URL(context.request.url).pathname,
        detail: { reason: 'upstream_rejected' },
      }),
    ]);

    return error(GENERIC_VERIFY_FAILURE, {
      status: result.response.status === 429 ? 429 : 401,
      code: result.response.status === 429 ? 'OTP_RATE_LIMITED' : 'OTP_VERIFY_FAILED',
    });
  }

  const data = result.data && typeof result.data === 'object' ? result.data : {};
  const session = data.session && typeof data.session === 'object' ? data.session : data;
  const accessToken = session.access_token || data.access_token || '';
  const refreshToken = session.refresh_token || data.refresh_token || '';
  const user = session.user || data.user || null;

  if (!accessToken || !refreshToken || !user?.id) {
    return error('Admin sign-in is temporarily unavailable. Try again shortly.', {
      status: 502,
      code: 'SESSION_CREATE_FAILED',
    });
  }

  const accessResult = await supabaseFetch(context, '/rest/v1/rpc/get_admin_access_for_user', {
    method: 'POST',
    accessToken,
    body: {},
  });

  if (!accessResult.response.ok) {
    return error('Admin sign-in is temporarily unavailable. Try again shortly.', {
      status: 502,
      code: 'ACCESS_RESOLUTION_FAILED',
    });
  }

  const access = normalizeAccess(accessResult.data);
  if (!access.hasAnyAdminAccess) {
    await recordAdminBrowserEvent(context, {
      eventName: 'admin_auth_verify_otp_denied',
      userId: user.id,
      path: new URL(context.request.url).pathname,
      detail: { reason: 'no_admin_access' },
    });

    return error('Admin access could not be granted for this session.', {
      status: 403,
      code: 'ACCESS_DENIED',
    });
  }

  const createdSession = await createAdminSession(context, {
    userId: user.id,
    accessToken,
    refreshToken,
    metadata: {
      source: 'cool_admin_pwa',
      phone: normalizedPhone,
    },
  });

  await Promise.all([
    recordOtpRateEvent(context, {
      action: 'verify_ip',
      actorKey: rateLimit.ipKey,
      outcome: 'accepted',
      phone: normalizedPhone,
    }),
    recordOtpRateEvent(context, {
      action: 'verify_phone',
      actorKey: rateLimit.phoneKey,
      outcome: 'accepted',
      phone: normalizedPhone,
    }),
    recordAdminBrowserEvent(context, {
      eventName: 'admin_auth_verify_otp_succeeded',
      sessionId: createdSession.sessionId,
      userId: user.id,
      path: new URL(context.request.url).pathname,
      detail: {
        has_platform_access: access.hasPlatformAccess,
        bank_partner_count: access.bankPartnerIds.length,
      },
    }),
  ]);

  return json(
    {
      success: true,
      user,
      access,
    },
    {
      headers: {
        'Set-Cookie': makeSessionCookieHeader(createdSession.sessionId),
      },
    },
  );
}

async function resolveRateLimit(context, normalizedPhone) {
  const now = Date.now();
  const clientIp = getClientIp(context.request) || 'unknown';
  const ipKey = await hashActorKey(`verify:${clientIp}`);
  const phoneKey = await hashActorKey(`verify:${normalizedPhone}`);

  const [recentIp, recentPhone] = await Promise.all([
    countOtpRateEvents(context, {
      action: 'verify_ip',
      actorKey: ipKey,
      windowStartIso: new Date(now - VERIFY_WINDOW_MS).toISOString(),
    }),
    countOtpRateEvents(context, {
      action: 'verify_phone',
      actorKey: phoneKey,
      windowStartIso: new Date(now - VERIFY_WINDOW_MS).toISOString(),
    }),
  ]);

  return {
    limited: recentIp >= VERIFY_IP_LIMIT || recentPhone >= VERIFY_PHONE_LIMIT,
    ipKey,
    phoneKey,
  };
}
