const JSON_HEADERS = {
  'Content-Type': 'application/json; charset=utf-8',
  'Cache-Control': 'no-store',
};

const PLATFORM_ONLY_ROUTES = new Set([
  'platform',
  'users',
  'app-config',
  'operations',
  'roles',
  'analytics',
  'audit-log',
  'groups',
]);

const SESSION_COOKIE = 'cool-admin-session';
const COOKIE_MAX_AGE = 7 * 24 * 60 * 60;
const SESSION_TABLE = '/rest/v1/admin_web_sessions';
const BROWSER_EVENTS_TABLE = '/rest/v1/admin_browser_events';

export function json(data, { status = 200, headers = {} } = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...JSON_HEADERS,
      ...headers,
    },
  });
}

export function error(
  message,
  { status = 400, code = 'BAD_REQUEST', details, headers = {} } = {},
) {
  return json(
    {
      success: false,
      code,
      message,
      ...(details === undefined ? {} : { details }),
    },
    { status, headers },
  );
}

export function getSupabaseConfig(env) {
  const url = (env.COOL_PROJECT_SUPABASE_URL || env.SUPABASE_URL || '').trim();
  const anonKey = (
    env.COOL_PROJECT_SUPABASE_ANON_KEY ||
    env.SUPABASE_ANON_KEY ||
    ''
  ).trim();

  if (!url || !anonKey) {
    throw new Error(
      'COOL admin API is missing Supabase runtime configuration. Set COOL_PROJECT_SUPABASE_URL and COOL_PROJECT_SUPABASE_ANON_KEY.',
    );
  }

  return { url: url.replace(/\/$/, ''), anonKey };
}

export function getServiceRoleKey(env) {
  const key = (
    env.COOL_PROJECT_SUPABASE_SERVICE_ROLE_KEY ||
    env.SUPABASE_SERVICE_ROLE_KEY ||
    ''
  ).trim();
  return key || null;
}

function createHeaders(
  config,
  { accessToken, includeJsonContentType = true, extraHeaders = {} } = {},
) {
  const headers = new Headers(extraHeaders);
  headers.set('apikey', config.anonKey);
  headers.set('Authorization', `Bearer ${accessToken || config.anonKey}`);
  if (includeJsonContentType) {
    headers.set('Content-Type', 'application/json');
  }
  return headers;
}

async function parseUpstreamBody(response) {
  const text = await response.text();
  if (!text) {
    return null;
  }

  try {
    return JSON.parse(text);
  } catch (_) {
    return text;
  }
}

export async function supabaseFetch(
  context,
  path,
  {
    method = 'GET',
    body,
    accessToken,
    extraHeaders,
    includeJsonContentType = true,
  } = {},
) {
  const config = getSupabaseConfig(context.env);
  const response = await fetch(`${config.url}${path}`, {
    method,
    headers: createHeaders(config, {
      accessToken,
      includeJsonContentType,
      extraHeaders,
    }),
    body: body === undefined ? undefined : JSON.stringify(body),
  });

  return {
    response,
    data: await parseUpstreamBody(response),
  };
}

export async function supabaseServiceFetch(
  context,
  path,
  {
    method = 'GET',
    body,
    extraHeaders,
    includeJsonContentType = true,
  } = {},
) {
  const config = getSupabaseConfig(context.env);
  const serviceKey = getServiceRoleKey(context.env);
  if (!serviceKey) {
    return { response: { ok: false, status: 503 }, data: null };
  }

  const response = await fetch(`${config.url}${path}`, {
    method,
    headers: createHeaders(config, {
      accessToken: serviceKey,
      includeJsonContentType,
      extraHeaders,
    }),
    body: body === undefined ? undefined : JSON.stringify(body),
  });

  return {
    response,
    data: await parseUpstreamBody(response),
  };
}

export async function readJson(request) {
  try {
    return await request.json();
  } catch (_) {
    return null;
  }
}

export function parseCookies(request) {
  const header = request.headers.get('Cookie') || '';
  const cookies = {};
  for (const pair of header.split(';')) {
    const [name, ...rest] = pair.trim().split('=');
    if (name) {
      cookies[name.trim()] = decodeURIComponent(rest.join('=').trim());
    }
  }
  return cookies;
}

export function getSessionIdFromCookie(request) {
  const cookies = parseCookies(request);
  return cookies[SESSION_COOKIE] || null;
}

export function getBearerToken(request) {
  const header = request.headers.get('Authorization') || '';
  const match = header.match(/^Bearer\s+(.+)$/i);
  if (match) {
    return match[1].trim();
  }
  return null;
}

export function makeSessionCookieHeader(sessionId) {
  return `${SESSION_COOKIE}=${encodeURIComponent(sessionId)}; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=${COOKIE_MAX_AGE}`;
}

export function makeClearSessionCookieHeader() {
  return `${SESSION_COOKIE}=; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=0`;
}

export function getClientIp(request) {
  const candidates = [
    request.headers.get('cf-connecting-ip'),
    request.headers.get('x-real-ip'),
    request.headers.get('fly-client-ip'),
    request.headers.get('x-forwarded-for')?.split(',')[0],
  ];

  for (const candidate of candidates) {
    const trimmed = candidate?.trim();
    if (trimmed) {
      return trimmed;
    }
  }

  return null;
}

export async function sha256Hex(value) {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(String(value ?? '')),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

export async function hashActorKey(value) {
  return await sha256Hex(String(value ?? '').trim().toLowerCase());
}

export async function countOtpRateEvents(
  context,
  { action, actorKey, windowStartIso },
) {
  const result = await supabaseServiceFetch(
    context,
    `${'/rest/v1/otp_rate_events'}?select=id&action=eq.${encodeURIComponent(action)}&actor_key=eq.${encodeURIComponent(actorKey)}&created_at=gte.${encodeURIComponent(windowStartIso)}&limit=100`,
    {
      method: 'GET',
      includeJsonContentType: false,
    },
  );

  if (!result.response.ok || !Array.isArray(result.data)) {
    return 0;
  }

  return result.data.length;
}

export async function recordOtpRateEvent(
  context,
  { action, actorKey, outcome, phone = null, metadata = {} },
) {
  await supabaseServiceFetch(context, '/rest/v1/otp_rate_events', {
    method: 'POST',
    body: {
      action,
      actor_key: actorKey,
      outcome,
      phone,
      metadata,
    },
  }).catch(() => {});
}

export async function recordAdminBrowserEvent(
  context,
  {
    eventName,
    sessionId = null,
    userId = null,
    route = null,
    path = null,
    online = null,
    appVersion = null,
    clientTs = null,
    detail = {},
  },
) {
  const serviceKey = getServiceRoleKey(context.env);
  if (!serviceKey) {
    return;
  }

  const ip = getClientIp(context.request);
  const userAgent = context.request.headers.get('user-agent') || null;

  await supabaseServiceFetch(context, BROWSER_EVENTS_TABLE, {
    method: 'POST',
    body: {
      session_id: sessionId,
      user_id: userId,
      event_name: eventName,
      route,
      path,
      online,
      app_version: appVersion,
      client_ts: clientTs,
      ip_hash: ip ? await sha256Hex(ip) : null,
      user_agent: userAgent,
      detail,
    },
  }).catch(() => {});
}

function normalizeSessionRecord(data) {
  if (!data || typeof data !== 'object') {
    return null;
  }

  return {
    id: data.id?.toString() || '',
    userId: data.user_id?.toString() || '',
    accessToken: data.access_token?.toString() || '',
    refreshToken: data.refresh_token?.toString() || '',
    issuedAt: data.issued_at?.toString() || '',
    lastVerifiedAt: data.last_verified_at?.toString() || '',
    lastSeenAt: data.last_seen_at?.toString() || '',
    expiresAt: data.expires_at?.toString() || '',
    revokedAt: data.revoked_at?.toString() || '',
    revokeReason: data.revoke_reason?.toString() || '',
    reauthRequired: data.reauth_required === true,
    metadata: data.metadata && typeof data.metadata === 'object' ? data.metadata : {},
  };
}

export async function createAdminSession(
  context,
  { userId, accessToken, refreshToken, metadata = {} },
) {
  const sessionId = crypto.randomUUID();
  const result = await supabaseServiceFetch(context, SESSION_TABLE, {
    method: 'POST',
    extraHeaders: { Prefer: 'return=representation' },
    body: {
      id: sessionId,
      user_id: userId,
      access_token: accessToken,
      refresh_token: refreshToken,
      expires_at: new Date(Date.now() + COOKIE_MAX_AGE * 1000).toISOString(),
      user_agent: context.request.headers.get('user-agent') || null,
      ip_hash: getClientIp(context.request)
        ? await sha256Hex(getClientIp(context.request))
        : null,
      metadata,
    },
  });

  if (!result.response.ok) {
    throw new Error('Could not create the COOL admin session.');
  }

  return {
    sessionId,
    session: normalizeSessionRecord(Array.isArray(result.data) ? result.data[0] : result.data),
  };
}

export async function getAdminSessionRecord(context, sessionId) {
  if (!sessionId) {
    return null;
  }

  const result = await supabaseServiceFetch(
    context,
    `${SESSION_TABLE}?id=eq.${encodeURIComponent(sessionId)}&select=id,user_id,access_token,refresh_token,issued_at,last_verified_at,last_seen_at,expires_at,revoked_at,revoke_reason,reauth_required,metadata&limit=1`,
    {
      method: 'GET',
      includeJsonContentType: false,
    },
  );

  if (!result.response.ok || !Array.isArray(result.data) || !result.data.length) {
    return null;
  }

  return normalizeSessionRecord(result.data[0]);
}

export async function updateAdminSessionTokens(
  context,
  sessionId,
  { accessToken, refreshToken, metadata = {} },
) {
  const result = await supabaseServiceFetch(
    context,
    `${SESSION_TABLE}?id=eq.${encodeURIComponent(sessionId)}&revoked_at=is.null`,
    {
      method: 'PATCH',
      extraHeaders: { Prefer: 'return=representation' },
      body: {
        access_token: accessToken,
        refresh_token: refreshToken,
        last_verified_at: new Date().toISOString(),
        last_seen_at: new Date().toISOString(),
        expires_at: new Date(Date.now() + COOKIE_MAX_AGE * 1000).toISOString(),
        metadata,
      },
    },
  );

  if (!result.response.ok) {
    return null;
  }

  const row = Array.isArray(result.data) ? result.data[0] : result.data;
  return normalizeSessionRecord(row);
}

export async function touchAdminSession(context, sessionId) {
  if (!sessionId) {
    return;
  }

  await supabaseServiceFetch(
    context,
    `${SESSION_TABLE}?id=eq.${encodeURIComponent(sessionId)}&revoked_at=is.null`,
    {
      method: 'PATCH',
      body: { last_seen_at: new Date().toISOString() },
    },
  ).catch(() => {});
}

export async function revokeAdminSession(context, sessionId, reason = 'signed_out') {
  if (!sessionId) {
    return;
  }

  await supabaseServiceFetch(
    context,
    `${SESSION_TABLE}?id=eq.${encodeURIComponent(sessionId)}&revoked_at=is.null`,
    {
      method: 'PATCH',
      body: {
        revoked_at: new Date().toISOString(),
        revoke_reason: reason,
      },
    },
  ).catch(() => {});
}

export async function revokeAdminSessionsForUser(
  context,
  userId,
  reason = 'access_changed',
) {
  if (!userId) {
    return;
  }

  await supabaseServiceFetch(
    context,
    `${SESSION_TABLE}?user_id=eq.${encodeURIComponent(userId)}&revoked_at=is.null`,
    {
      method: 'PATCH',
      body: {
        revoked_at: new Date().toISOString(),
        revoke_reason: reason,
      },
    },
  ).catch(() => {});
}

function sessionExpired(session) {
  const expiresAt = session?.expiresAt ? Date.parse(session.expiresAt) : Number.NaN;
  return Number.isFinite(expiresAt) && expiresAt <= Date.now();
}

export function mapUpstreamError(result, fallbackMessage) {
  const details =
    typeof result.data === 'object' && result.data !== null ? result.data : undefined;
  const message =
    details?.message ||
    details?.error_description ||
    details?.error ||
    (typeof result.data === 'string' ? result.data : null) ||
    fallbackMessage;

  return error(message, {
    status: result.response.status || 500,
    code: 'UPSTREAM_ERROR',
    details,
  });
}

export function normalizeAuthUser(data) {
  if (!data || typeof data !== 'object') {
    return null;
  }

  const metadata =
    data.user_metadata && typeof data.user_metadata === 'object'
      ? data.user_metadata
      : {};

  return {
    id: data.id?.toString() || '',
    phone: data.phone?.toString() || metadata.phone?.toString() || '',
    fullName:
      metadata.full_name?.toString() ||
      metadata.name?.toString() ||
      metadata.official_name?.toString() ||
      '',
    publicUserId: metadata.public_user_id?.toString() || '',
    appMetadata:
      data.app_metadata && typeof data.app_metadata === 'object' ? data.app_metadata : {},
  };
}

export function normalizeAccess(access) {
  const value = access && typeof access === 'object' ? access : {};
  const assignments = Array.isArray(value.role_assignments) ? value.role_assignments : [];
  const bankIds = Array.isArray(value.bank_partner_ids)
    ? value.bank_partner_ids.map((entry) => String(entry))
    : [];
  const capabilities = Array.isArray(value.capabilities)
    ? value.capabilities.map((entry) => String(entry))
    : [];

  return {
    hasPlatformAccess: value.has_platform_access === true,
    hasBankAccess: value.has_bank_access === true,
    hasAnyAdminAccess:
      value.has_platform_access === true ||
      value.has_bank_access === true ||
      bankIds.length > 0 ||
      assignments.length > 0,
    bankPartnerIds: bankIds,
    roleAssignments: assignments,
    capabilities,
  };
}

export async function loadAdminContext(context, { requirePlatformAccess = false } = {}) {
  let config;

  try {
    config = getSupabaseConfig(context.env);
  } catch (configError) {
    return {
      response: error(configError.message, {
        status: 503,
        code: 'CONFIG_MISSING',
      }),
    };
  }

  const bearerToken = getBearerToken(context.request);
  const sessionId = getSessionIdFromCookie(context.request);
  let session = null;
  let accessToken = bearerToken;

  if (!accessToken) {
    session = await getAdminSessionRecord(context, sessionId);

    if (!session || session.revokedAt || sessionExpired(session)) {
      if (sessionId) {
        await revokeAdminSession(context, sessionId, session?.revokedAt ? 'already_revoked' : 'expired_or_missing');
      }
      return {
        response: error('Sign in is required to open COOL Admin.', {
          status: 401,
          code: 'AUTH_REQUIRED',
          headers: {
            'Set-Cookie': makeClearSessionCookieHeader(),
          },
        }),
      };
    }

    accessToken = session.accessToken;
  }

  const [userResult, accessResult] = await Promise.all([
    supabaseFetch(context, '/auth/v1/user', {
      method: 'GET',
      accessToken,
      includeJsonContentType: false,
    }),
    supabaseFetch(context, '/rest/v1/rpc/get_admin_access_for_user', {
      method: 'POST',
      accessToken,
      body: {},
    }),
  ]);

  if (!userResult.response.ok) {
    return {
      response: mapUpstreamError(userResult, 'Could not verify the current admin session.'),
    };
  }

  if (!accessResult.response.ok) {
    return {
      response: mapUpstreamError(accessResult, 'Could not resolve admin access.'),
    };
  }

  const user = normalizeAuthUser(userResult.data);
  const access = normalizeAccess(accessResult.data);

  if (!access.hasAnyAdminAccess) {
    if (sessionId) {
      await revokeAdminSession(context, sessionId, 'access_denied');
    }
    return {
      response: error('This account does not have COOL admin access.', {
        status: 403,
        code: 'ACCESS_DENIED',
        details: { user, access },
        headers: sessionId
          ? { 'Set-Cookie': makeClearSessionCookieHeader() }
          : {},
      }),
    };
  }

  if (requirePlatformAccess && !access.hasPlatformAccess) {
    return {
      response: error('This COOL Admin route requires platform admin access.', {
        status: 403,
        code: 'PLATFORM_ACCESS_REQUIRED',
        details: { user, access },
      }),
    };
  }

  if (sessionId) {
    void touchAdminSession(context, sessionId);
  }

  return { config, sessionId, session, accessToken, user, access };
}

export function routeRequiresPlatformAccess(route) {
  return PLATFORM_ONLY_ROUTES.has(route);
}

export function toArray(data) {
  return Array.isArray(data) ? data : [];
}

export function toObject(data) {
  return data && typeof data === 'object' && !Array.isArray(data) ? data : {};
}

export function isoDate(value) {
  if (!value) {
    return '';
  }

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return '';
  }

  return date.toISOString();
}

export function shortDate(value) {
  const normalized = isoDate(value);
  if (!normalized) {
    return '';
  }

  return normalized.slice(0, 16).replace('T', ' ');
}

export function toneForHealth(value) {
  switch (String(value || '').toLowerCase()) {
    case 'failing':
    case 'critical':
    case 'error':
      return 'error';
    case 'degraded':
    case 'warning':
      return 'offline';
    case 'unknown':
    case 'pending':
      return 'syncing';
    default:
      return 'online';
  }
}

export function humanizeHealth(value) {
  const normalized = String(value || '').trim().toLowerCase();
  if (!normalized) {
    return 'Unknown';
  }
  return normalized
    .split(/[_\s-]+/)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(' ');
}

export function worstHealth(rows) {
  const order = new Map([
    ['failing', 0],
    ['critical', 0],
    ['degraded', 1],
    ['warning', 1],
    ['unknown', 2],
    ['healthy', 3],
    ['ok', 3],
  ]);

  return rows.reduce((worst, row) => {
    const current = String(row.health_status || row.severity || '').toLowerCase();
    const currentRank = order.get(current) ?? 99;
    const worstRank = order.get(worst) ?? 99;
    return currentRank < worstRank ? current : worst;
  }, 'healthy');
}
