import {
  countOtpRateEvents,
  error,
  getClientIp,
  hashActorKey,
  json,
  readJson,
  recordAdminBrowserEvent,
  recordOtpRateEvent,
  supabaseFetch,
  supabaseServiceFetch,
} from '../../_shared/supabase.js';

const GENERIC_SEND_RESPONSE =
  'If the number is authorized, a verification code will be sent shortly.';

const SEND_IP_LIMIT = 8;
const SEND_PHONE_LIMIT = 3;
const SEND_IP_WINDOW_MS = 30 * 60 * 1000;
const SEND_PHONE_WINDOW_MS = 15 * 60 * 1000;

export async function onRequestPost(context) {
  const body = await readJson(context.request);
  const phone = body?.phone?.toString().trim() || '';

  if (!phone) {
    return error('Phone number is required.', {
      status: 400,
      code: 'PHONE_REQUIRED',
    });
  }

  const normalizedPhone = phone.startsWith('+') ? phone : `+${phone}`;
  const rateLimit = await resolveRateLimit(context, normalizedPhone);
  if (rateLimit.limited) {
    return error('Too many verification requests. Wait a few minutes and try again.', {
      status: 429,
      code: 'OTP_RATE_LIMITED',
    });
  }

  const eligible = await checkAdminPhoneEligible(context, normalizedPhone);
  let upstreamFailed = false;

  if (eligible) {
    const result = await supabaseFetch(context, '/functions/v1/send-otp', {
      method: 'POST',
      body: { phone: normalizedPhone, language: 'en' },
    });

    upstreamFailed = !result.response.ok;
    if (upstreamFailed) {
      await recordOtpRateEvent(context, {
        action: 'send_phone',
        actorKey: rateLimit.phoneKey,
        outcome: 'upstream_failed',
        phone: normalizedPhone,
      });
      return error('Admin sign-in is temporarily unavailable. Try again shortly.', {
        status: 502,
        code: 'OTP_DELIVERY_FAILED',
      });
    }
  }

  await Promise.all([
    recordOtpRateEvent(context, {
      action: 'send_ip',
      actorKey: rateLimit.ipKey,
      outcome: eligible ? 'accepted' : 'filtered',
      phone: normalizedPhone,
    }),
    recordOtpRateEvent(context, {
      action: 'send_phone',
      actorKey: rateLimit.phoneKey,
      outcome: eligible ? 'accepted' : 'filtered',
      phone: normalizedPhone,
    }),
    recordAdminBrowserEvent(context, {
      eventName: 'admin_auth_send_otp',
      path: new URL(context.request.url).pathname,
      detail: {
        eligible,
        upstream_failed: upstreamFailed,
      },
    }),
  ]);

  return json({
    success: true,
    message: GENERIC_SEND_RESPONSE,
  });
}

async function resolveRateLimit(context, normalizedPhone) {
  const now = Date.now();
  const clientIp = getClientIp(context.request) || 'unknown';
  const ipKey = await hashActorKey(`send:${clientIp}`);
  const phoneKey = await hashActorKey(`send:${normalizedPhone}`);

  const [recentIp, recentPhone] = await Promise.all([
    countOtpRateEvents(context, {
      action: 'send_ip',
      actorKey: ipKey,
      windowStartIso: new Date(now - SEND_IP_WINDOW_MS).toISOString(),
    }),
    countOtpRateEvents(context, {
      action: 'send_phone',
      actorKey: phoneKey,
      windowStartIso: new Date(now - SEND_PHONE_WINDOW_MS).toISOString(),
    }),
  ]);

  return {
    limited: recentIp >= SEND_IP_LIMIT || recentPhone >= SEND_PHONE_LIMIT,
    ipKey,
    phoneKey,
  };
}

async function checkAdminPhoneEligible(context, phone) {
  const userResult = await supabaseServiceFetch(
    context,
    `/rest/v1/users?phone=eq.${encodeURIComponent(phone)}&select=id,is_admin&limit=1`,
  );

  if (!userResult.response.ok || !Array.isArray(userResult.data) || userResult.data.length === 0) {
    return false;
  }

  const user = userResult.data[0];
  if (user.is_admin === true) {
    return true;
  }

  const roleResult = await supabaseServiceFetch(
    context,
    `/rest/v1/admin_role_assignments?user_id=eq.${encodeURIComponent(user.id)}&select=id&is_active=is.true&limit=1`,
  );

  return roleResult.response.ok &&
    Array.isArray(roleResult.data) &&
    roleResult.data.length > 0;
}
