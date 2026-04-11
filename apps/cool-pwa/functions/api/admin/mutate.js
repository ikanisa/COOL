import {
  error,
  json,
  loadAdminContext,
  mapUpstreamError,
  recordAdminBrowserEvent,
  revokeAdminSessionsForUser,
  supabaseFetch,
} from '../../_shared/supabase.js';

const SUPPORTED_ASSIGNABLE_ROLES = new Set(['admin', 'bank', 'rayon_sport']);

export async function onRequestPost(context) {
  const admin = await loadAdminContext(context, { requirePlatformAccess: true });
  if (admin.response) {
    return admin.response;
  }

  const body = await context.request.json().catch(() => null);
  const action = body?.action?.toString().trim() || '';

  if (!action) {
    return error('Mutation action is required.', {
      status: 400,
      code: 'ACTION_REQUIRED',
    });
  }

  switch (action) {
    case 'assign_role':
      return await assignRole(context, admin.accessToken, body);
    case 'revoke_role':
      return await revokeRole(context, admin.accessToken, body);
    case 'toggle_user_platform_access':
      return await toggleUserPlatformAccess(context, admin.accessToken, body);
    case 'upsert_app_config':
      return await upsertAppConfig(context, admin.accessToken, body);
    default:
      return error(`Unsupported admin mutation "${action}".`, {
        status: 400,
        code: 'UNSUPPORTED_ACTION',
      });
  }
}

async function assignRole(context, accessToken, body) {
  const targetUserId = body?.targetUserId?.toString().trim() || '';
  const role = body?.role?.toString().trim() || '';
  const bankId = body?.bankId?.toString().trim() || null;
  const notes = body?.notes?.toString().trim() || null;

  if (!targetUserId || !role) {
    return error('Target user and role are required.', {
      status: 400,
      code: 'ROLE_INPUT_REQUIRED',
    });
  }

  if (!SUPPORTED_ASSIGNABLE_ROLES.has(role)) {
    return error('Unsupported admin role.', {
      status: 400,
      code: 'ROLE_INVALID',
    });
  }

  if (role === 'bank' && !bankId) {
    return error('A bank partner must be selected for bank-scoped access.', {
      status: 400,
      code: 'BANK_SCOPE_REQUIRED',
    });
  }

  const result = await supabaseFetch(context, '/rest/v1/rpc/assign_admin_role', {
    method: 'POST',
    accessToken,
    body: {
      p_target_user_id: targetUserId,
      p_role: role,
      ...(bankId ? { p_partner_scope_id: bankId } : {}),
      ...(notes ? { p_notes: notes } : {}),
    },
  });

  if (!result.response.ok) {
    return mapUpstreamError(result, 'Could not assign the admin role.');
  }

  await recordAdminBrowserEvent(context, {
    eventName: 'admin_mutation_assign_role',
    userId: targetUserId,
    path: new URL(context.request.url).pathname,
    detail: {
      role,
      bank_id: bankId,
      notes_present: Boolean(notes),
    },
  });

  return json({
    success: true,
    action: 'assign_role',
    result: result.data,
  });
}

async function revokeRole(context, accessToken, body) {
  const assignmentId = body?.assignmentId?.toString().trim() || '';
  const notes = body?.notes?.toString().trim() || null;

  if (!assignmentId) {
    return error('Assignment ID is required.', {
      status: 400,
      code: 'ASSIGNMENT_REQUIRED',
    });
  }

  const result = await supabaseFetch(context, '/rest/v1/rpc/revoke_admin_role', {
    method: 'POST',
    accessToken,
    body: {
      p_assignment_id: assignmentId,
      ...(notes ? { p_notes: notes } : {}),
    },
  });

  if (!result.response.ok) {
    return mapUpstreamError(result, 'Could not revoke the admin role.');
  }

  await revokeAdminSessionsForUser(
    context,
    result.data?.user_id || null,
    'admin_role_revoked',
  );
  await recordAdminBrowserEvent(context, {
    eventName: 'admin_mutation_revoke_role',
    userId: result.data?.user_id || null,
    path: new URL(context.request.url).pathname,
    detail: {
      assignment_id: assignmentId,
      notes_present: Boolean(notes),
    },
  });

  return json({
    success: true,
    action: 'revoke_role',
    result: result.data,
  });
}

async function toggleUserPlatformAccess(context, accessToken, body) {
  const enabled = body?.enabled === true;
  const assignmentId = body?.assignmentId?.toString().trim() || '';
  const userId = body?.userId?.toString().trim() || '';

  if (enabled) {
    return await assignRole(context, accessToken, {
      targetUserId: userId,
      role: 'admin',
      notes: body?.notes,
    });
  }

  if (!assignmentId) {
    // TODO(legacy-admin-revocation): Legacy users.is_admin rows predate the
    // role_assignments table. To revoke these, a backend migration must:
    //   1. Create a matching row in admin_role_assignments for each legacy admin.
    //   2. Set users.is_admin = false.
    //   3. After migration, this code path becomes unreachable.
    // Tracked as a prerequisite for full browser-based access governance.
    return error(
      'This admin account does not have a revocable role assignment. Legacy users.is_admin records still require a backend migration path.',
      {
        status: 409,
        code: 'LEGACY_ADMIN_NOT_REVOCABLE',
      },
    );
  }

  return await revokeRole(context, accessToken, {
    assignmentId,
    notes: body?.notes,
  });
}

async function upsertAppConfig(context, accessToken, body) {
  const key = body?.key?.toString().trim() || '';
  const value = body?.value?.toString() ?? '';
  const description = body?.description?.toString().trim() || null;
  const country = body?.country?.toString().trim().toUpperCase() || null;
  const changeReason = body?.changeReason?.toString().trim() || '';

  if (!key) {
    return error('Config key is required.', {
      status: 400,
      code: 'CONFIG_KEY_REQUIRED',
    });
  }

  if (!changeReason) {
    return error('A change reason is required for config mutations.', {
      status: 400,
      code: 'CONFIG_REASON_REQUIRED',
    });
  }

  const existing = await supabaseFetch(
    context,
    `/rest/v1/app_config?select=key,value,description,country&key=eq.${encodeURIComponent(key)}&limit=1`,
    {
      method: 'GET',
      accessToken,
      includeJsonContentType: false,
    },
  );

  if (!existing.response.ok) {
    return mapUpstreamError(existing, 'Could not inspect the target config entry.');
  }

  const payload = {
    key,
    value,
    description,
    country,
  };

  const result =
    Array.isArray(existing.data) && existing.data.length > 0
      ? await supabaseFetch(
          context,
          `/rest/v1/app_config?key=eq.${encodeURIComponent(key)}`,
          {
            method: 'PATCH',
            accessToken,
            body: payload,
            extraHeaders: { Prefer: 'return=representation' },
          },
        )
      : await supabaseFetch(context, '/rest/v1/app_config', {
          method: 'POST',
          accessToken,
          body: payload,
          extraHeaders: { Prefer: 'return=representation' },
        });

  if (!result.response.ok) {
    return mapUpstreamError(result, 'Could not save the app config entry.');
  }

  const beforeState =
    Array.isArray(existing.data) && existing.data.length > 0
      ? existing.data[0]
      : null;
  const afterState =
    Array.isArray(result.data) && result.data.length > 0 ? result.data[0] : payload;

  await supabaseFetch(context, '/rest/v1/rpc/record_admin_action', {
    method: 'POST',
    accessToken,
    body: {
      p_action: beforeState ? 'update' : 'create',
      p_target_table: 'app_config',
      p_target_id: key,
      p_old_data: beforeState,
      p_new_data: afterState,
      p_notes: changeReason,
    },
  }).catch(() => {});

  await recordAdminBrowserEvent(context, {
    eventName: 'admin_mutation_upsert_app_config',
    path: new URL(context.request.url).pathname,
    detail: {
      key,
      country,
      change_reason: changeReason,
    },
  });

  return json({
    success: true,
    action: 'upsert_app_config',
    result: result.data,
  });
}
