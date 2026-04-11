/**
 * COOL Admin API client.
 *
 * Session management: HttpOnly cookies are set/cleared by the server.
 * The browser only carries an opaque session cookie.
 */

async function requestJson(
  path,
  { method = 'GET', body } = {},
  { allowUnavailable = false } = {},
) {
  const headers = new Headers({
    Accept: 'application/json',
  });

  if (body !== undefined) {
    headers.set('Content-Type', 'application/json');
  }

  let response;
  try {
    response = await fetch(path, {
      method,
      headers,
      credentials: 'same-origin',
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  } catch (fetchError) {
    return {
      ok: false,
      status: 0,
      data: null,
      unavailable: allowUnavailable,
      error: fetchError,
    };
  }

  if (allowUnavailable && response.status === 404) {
    return {
      ok: false,
      status: response.status,
      data: null,
      unavailable: true,
    };
  }

  let data = null;
  try {
    data = await response.json();
  } catch (_) {
    data = null;
  }

  return {
    ok: response.ok,
    status: response.status,
    data,
    unavailable: false,
  };
}

export async function clearAdminSession() {
  try {
    await fetch('/api/auth/logout', {
      method: 'POST',
      credentials: 'same-origin',
    });
  } catch (_) {
    // Best effort. The UI still clears local state.
  }
}

export async function sendAdminOtp(phone) {
  const result = await requestJson(
    '/api/auth/send-otp',
    {
      method: 'POST',
      body: { phone },
    },
    { allowUnavailable: true },
  );

  if (result.unavailable) {
    throw new Error('Live admin auth is unavailable in this static preview.');
  }

  if (!result.ok) {
    const err = new Error(result.data?.message || 'Failed to send the admin sign-in code.');
    err.code = result.data?.code || null;
    throw err;
  }

  return result.data;
}

export async function verifyAdminOtp(phone, code) {
  const result = await requestJson(
    '/api/auth/verify-otp',
    {
      method: 'POST',
      body: { phone, code },
    },
    { allowUnavailable: true },
  );

  if (result.unavailable) {
    throw new Error('Live admin auth is unavailable in this static preview.');
  }

  if (!result.ok) {
    const err = new Error(
      result.data?.message || 'Failed to verify the admin sign-in code.',
    );
    err.code = result.data?.code || null;
    throw err;
  }

  // Server sets HttpOnly cookie — no client-side token storage needed
  return result.data;
}

export async function getAdminSessionState() {
  const probe = await requestJson('/api/admin/session', {}, { allowUnavailable: true });

  if (probe.unavailable) {
    return {
      live: false,
      authenticated: false,
      authorized: false,
    };
  }

  if (probe.data?.live === false || probe.data?.staticPreview === true) {
    return {
      live: false,
      authenticated: false,
      authorized: false,
    };
  }

  if (probe.ok) {
    return {
      live: true,
      authenticated: true,
      authorized: true,
      user: probe.data?.user || null,
      access: probe.data?.access || null,
    };
  }

  if (probe.status === 403) {
    const details = probe.data?.details || {};
    return {
      live: true,
      authenticated: true,
      authorized: false,
      user: details.user || null,
      access: details.access || null,
      message: probe.data?.message || 'This account cannot open COOL Admin.',
      code: probe.data?.code || 'ACCESS_DENIED',
    };
  }

  if (probe.status === 401) {
    // Try silent refresh via cookie
    const refreshResult = await requestJson(
      '/api/auth/refresh',
      { method: 'POST' },
      { allowUnavailable: true },
    );

    if (refreshResult.ok) {
      // Cookie updated server-side — retry session probe
      const retryProbe = await requestJson('/api/admin/session', {}, { allowUnavailable: true });
      if (retryProbe.ok) {
        return {
          live: true,
          authenticated: true,
          authorized: true,
          user: retryProbe.data?.user || null,
          access: retryProbe.data?.access || null,
        };
      }
    }

    return {
      live: true,
      authenticated: false,
      authorized: false,
      message: probe.data?.message || 'Your COOL admin session expired.',
      code: probe.data?.code || 'AUTH_REQUIRED',
    };
  }

  return {
    live: true,
    authenticated: true,
    authorized: false,
    message: probe.data?.message || 'Failed to resolve the COOL admin session.',
    code: probe.data?.code || 'SESSION_ERROR',
  };
}

export async function fetchAdminRouteData(route) {
  const params = new URLSearchParams(window.location.search);
  params.set('route', route);
  const result = await requestJson(
    `/api/admin/data?${params.toString()}`,
    {},
    { allowUnavailable: true },
  );

  if (result.unavailable) {
    return { unavailable: true };
  }

  if (result.ok) {
    return result.data;
  }

  if (result.status === 401) {
    // Try silent refresh
    const refreshResult = await requestJson(
      '/api/auth/refresh',
      { method: 'POST' },
      { allowUnavailable: true },
    );

    if (refreshResult.ok) {
      const retryResult = await requestJson(
        `/api/admin/data?${params.toString()}`,
        {},
        { allowUnavailable: true },
      );
      if (retryResult.ok) {
        return retryResult.data;
      }
    }

    return {
      unauthorized: true,
      message: result.data?.message || 'The COOL admin session is no longer valid.',
    };
  }

  if (result.status === 403) {
    const details = result.data?.details || {};
    return {
      forbidden: true,
      message: result.data?.message || 'This route is not available for the current admin role.',
      code: result.data?.code || 'ROUTE_FORBIDDEN',
      access: details.access || null,
      user: details.user || null,
    };
  }

  throw new Error(result.data?.message || 'Failed to load COOL admin route data.');
}

export async function mutateAdmin(action, payload) {
  const result = await requestJson('/api/admin/mutate', {
    method: 'POST',
    body: { action, ...payload },
  });

  if (result.status === 401) {
    // Try silent refresh and retry
    const refreshResult = await requestJson(
      '/api/auth/refresh',
      { method: 'POST' },
      { allowUnavailable: true },
    );

    if (refreshResult.ok) {
      const retryResult = await requestJson('/api/admin/mutate', {
        method: 'POST',
        body: { action, ...payload },
      });

      if (retryResult.ok) {
        return retryResult.data;
      }
    }
  }

  if (!result.ok) {
    const err = new Error(result.data?.message || `Failed to complete ${action}.`);
    err.code = result.data?.code || null;
    throw err;
  }

  return result.data;
}
