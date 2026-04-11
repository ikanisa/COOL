import {
  error,
  humanizeHealth,
  json,
  loadAdminContext,
  routeRequiresPlatformAccess,
  shortDate,
  supabaseFetch,
  toArray,
  toObject,
  toneForHealth,
  worstHealth,
} from '../../_shared/supabase.js';

export async function onRequestGet(context) {
  const url = new URL(context.request.url);
  const route = url.searchParams.get('route')?.trim() || 'admin';

  const admin = await loadAdminContext(context, {
    requirePlatformAccess: routeRequiresPlatformAccess(route),
  });
  if (admin.response) {
    return admin.response;
  }

  try {
    const data = await buildRouteData(context, route, admin, url);
    return json({
      success: true,
      live: true,
      route,
      user: admin.user,
      access: admin.access,
      ...data,
    });
  } catch (routeError) {
    return error(routeError.message || 'Failed to load COOL admin data.', {
      status: 500,
      code: 'ROUTE_DATA_FAILED',
    });
  }
}

async function buildRouteData(context, route, admin, url) {
  switch (route) {
    case 'admin':
    case 'index':
      return buildWorkspaceData(admin);
    case 'platform':
      return await buildPlatformData(context, admin);
    case 'users':
      return await buildUsersData(context, admin, url);
    case 'app-config':
      return await buildAppConfigData(context, admin, url);
    case 'operations':
      return await buildOperationsData(context, admin);
    case 'roles':
      return await buildRolesData(context, admin);
    case 'analytics':
      return await buildAnalyticsData(context, admin);
    case 'audit-log':
      return await buildAuditLogData(context, admin, url);
    case 'groups':
      return await buildGroupsData(context, admin);
    case 'savings':
      return await buildSavingsData(context, admin);
    default:
      return buildWorkspaceData(admin);
  }
}

function buildWorkspaceData(admin) {
  const assignments = toArray(admin.access.roleAssignments);
  const roles = assignments.length
    ? assignments.map((assignment) => {
        const scope = assignment.partner_name
          ? ` scoped to ${assignment.partner_name}`
          : '';
        return {
          title: assignment.role === 'bank' ? 'Bank workspace' : 'Platform workspace',
          status: assignment.is_active === false ? 'Inactive' : 'Active',
          tone: assignment.is_active === false ? 'offline' : 'online',
          description: `${humanizeHealth(assignment.role)} access${scope}.`,
          meta: shortDate(assignment.granted_at),
        };
      })
    : [
        {
          title: 'Admin session active',
          status: admin.access.hasPlatformAccess ? 'Platform' : 'Scoped',
          tone: admin.access.hasPlatformAccess ? 'online' : 'syncing',
          description: admin.access.hasPlatformAccess
            ? 'Full platform administration is available in this PWA.'
            : 'Bank-scoped access is active. Platform-only routes stay protected.',
          meta: admin.user.phone || admin.user.id,
        },
      ];

  return {
    activity: roles,
    queue: [
      {
        title: 'Route guard',
        status: admin.access.hasPlatformAccess ? 'Unlocked' : 'Scoped',
        tone: admin.access.hasPlatformAccess ? 'online' : 'syncing',
        description: admin.access.hasPlatformAccess
          ? 'Platform routes can load live Supabase data and mutations.'
          : 'This account can sign in, but platform-only routes remain blocked.',
        meta: admin.user.fullName || admin.user.phone || admin.user.id,
      },
    ],
  };
}

async function buildPlatformData(context, admin) {
  const [dashboard, issues] = await Promise.all([
    rpcList(context, admin.accessToken, 'get_operational_release_dashboard'),
    rpcList(context, admin.accessToken, 'get_operational_triage_issues'),
  ]);
  const releasePosture = humanizeHealth(worstHealth(dashboard));

  return {
    metrics: {
      frontendSurfaces: dashboard.length,
      backendServices: issues.length,
      releasePosture,
    },
    activity: dashboard.slice(0, 8).map((item) => ({
      title: item.label || item.service_key || 'Service',
      status: humanizeHealth(item.health_status),
      tone: toneForHealth(item.health_status),
      description: item.summary || 'Operational release signal available.',
      meta: shortDate(item.last_signal_at),
    })),
    queue: issues.slice(0, 8).map((issue) => ({
      title: issue.title || issue.issue_id || 'Triage issue',
      status: humanizeHealth(issue.severity),
      tone: toneForHealth(issue.severity),
      description: issue.detail || 'Operational triage item.',
      meta: issue.reference || shortDate(issue.last_seen_at),
    })),
  };
}

async function buildUsersData(context, admin, url) {
  const q = readTrimmedParam(url, 'q');
  const page = readPositiveInt(url, 'page', 1, { max: 500 });
  const limit = readPositiveInt(url, 'limit', 24, { min: 12, max: 50 });
  const offset = (page - 1) * limit;

  const userParams = new URLSearchParams();
  userParams.set(
    'select',
    'id,public_user_id,full_name,phone,country,language_code,momo_provider,is_admin,created_at,is_mock,mock_batch',
  );
  userParams.append('order', 'is_mock.desc');
  userParams.append('order', 'created_at.desc');
  userParams.set('limit', String(limit));
  userParams.set('offset', String(offset));

  const sanitizedQuery = sanitizeSearchTerm(q);
  if (sanitizedQuery) {
    userParams.set(
      'or',
      `(full_name.ilike.*${sanitizedQuery}*,phone.ilike.*${sanitizedQuery}*,public_user_id.ilike.*${sanitizedQuery}*)`,
    );
  }

  const [usersPage, roleAssignments, managedAccounts, recoveryQueueCount, legacyAdmins] =
    await Promise.all([
      restListPage(
        context,
        admin.accessToken,
        `/users?${userParams.toString()}`,
      ),
      rpcList(context, admin.accessToken, 'list_admin_role_assignments', {
        p_active_only: true,
      }),
      restCount(context, admin.accessToken, '/users?select=id'),
      restCount(
        context,
        admin.accessToken,
        '/users?select=id&or=(phone.is.null,full_name.is.null)',
      ),
      restList(
        context,
        admin.accessToken,
        '/users?select=id&is_admin=eq.true&limit=500',
      ),
    ]);

  const assignmentsByUser = new Map();
  for (const assignment of roleAssignments) {
    const userAssignments = assignmentsByUser.get(assignment.user_id) || [];
    userAssignments.push(assignment);
    assignmentsByUser.set(assignment.user_id, userAssignments);
  }

  const normalizedUsers = usersPage.rows.map((user) => {
    const assignments = assignmentsByUser.get(user.id) || [];
    const platformAssignment = assignments.find((assignment) => assignment.role === 'admin');
    const bankAssignments = assignments.filter((assignment) => assignment.role === 'bank');

    return {
      ...user,
      display_name: user.full_name || user.phone || user.public_user_id || user.id,
      platform_assignment_id: platformAssignment?.id || null,
      has_platform_access: user.is_admin === true || Boolean(platformAssignment),
      has_legacy_admin: user.is_admin === true && !platformAssignment,
      bank_assignment_count: bankAssignments.length,
    };
  });

  const adminAccounts = new Set(
    [
      ...roleAssignments.map((assignment) => assignment.user_id),
      ...legacyAdmins.map((user) => user.id),
    ].filter(Boolean),
  ).size;

  return {
    metrics: {
      managedAccounts,
      adminAccounts,
      recoveryQueue: recoveryQueueCount,
    },
    activity: normalizedUsers.slice(0, 8).map((user) => ({
      title: user.display_name,
      status: user.has_platform_access
        ? user.has_legacy_admin
          ? 'Legacy admin'
          : 'Platform admin'
        : user.bank_assignment_count > 0
          ? 'Bank admin'
          : 'User',
      tone: user.has_platform_access
        ? 'online'
        : user.bank_assignment_count > 0
          ? 'syncing'
          : user.is_mock
            ? 'offline'
            : 'online',
      description: user.phone
        ? `${user.phone}${user.bank_assignment_count ? ` · ${user.bank_assignment_count} bank workspace${user.bank_assignment_count > 1 ? 's' : ''}` : ''}`
        : 'Profile is missing a primary phone number.',
      meta: shortDate(user.created_at),
    })),
    users: normalizedUsers,
    pagination: buildPagination({
      page,
      limit,
      total: usersPage.total,
    }),
    filters: { q: q || '' },
  };
}

async function buildAppConfigData(context, admin, url) {
  const q = readTrimmedParam(url, 'q');
  const scope = readTrimmedParam(url, 'scope');
  const page = readPositiveInt(url, 'page', 1, { max: 500 });
  const limit = readPositiveInt(url, 'limit', 24, { min: 12, max: 50 });
  const offset = (page - 1) * limit;

  const params = new URLSearchParams();
  params.set('select', 'key,value,description,country,created_at,updated_at');
  params.append('order', 'updated_at.desc');
  params.append('order', 'key.asc');
  params.set('limit', String(limit));
  params.set('offset', String(offset));

  const sanitizedQuery = sanitizeSearchTerm(q);
  if (sanitizedQuery) {
    params.set(
      'or',
      `(key.ilike.*${sanitizedQuery}*,description.ilike.*${sanitizedQuery}*,value.ilike.*${sanitizedQuery}*)`,
    );
  }
  if (scope && scope.toLowerCase() !== 'platform') {
    params.set('country', `eq.${scope.toUpperCase()}`);
  } else if (scope.toLowerCase() === 'platform') {
    params.set('country', 'is.null');
  }

  const nowIso = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const [configsPage, routesCount, rolloutKeys, pendingChanges, configCatalog] =
    await Promise.all([
      restListPage(
        context,
        admin.accessToken,
        `/app_config?${params.toString()}`,
      ),
      restCount(
        context,
        admin.accessToken,
        '/partner_payment_routes?select=id',
      ),
      restCount(context, admin.accessToken, '/app_config?select=key'),
      restCount(
        context,
        admin.accessToken,
        `/app_config?select=key&updated_at=gte.${encodeURIComponent(nowIso)}`,
      ),
      restList(
        context,
        admin.accessToken,
        '/app_config?select=key,country&order=key.asc&limit=200',
      ),
    ]);

  const configs = configsPage.rows;
  const catalogKeys = Array.from(new Set(configCatalog.map((entry) => entry.key).filter(Boolean)));
  const catalogScopes = Array.from(
    new Set(
      configCatalog
        .map((entry) => (entry.country ? String(entry.country).toUpperCase() : 'platform'))
        .filter(Boolean),
    ),
  ).sort();

  return {
    metrics: {
      rolloutKeys,
      partnerRoutes: routesCount,
      pendingChanges,
    },
    activity: configs.slice(0, 8).map((entry) => ({
      title: entry.key || 'Config entry',
      status: entry.country ? String(entry.country).toUpperCase() : 'Platform',
      tone: entry.country ? 'syncing' : 'online',
      description: entry.description || entry.value || 'Runtime app configuration.',
      meta: shortDate(entry.updated_at || entry.created_at),
    })),
    configEntries: configs,
    configCatalog: {
      keys: catalogKeys,
      scopes: catalogScopes,
    },
    pagination: buildPagination({
      page,
      limit,
      total: configsPage.total,
    }),
    filters: {
      q: q || '',
      scope: scope || '',
    },
  };
}

async function buildOperationsData(context, admin) {
  const [dashboard, issues] = await Promise.all([
    rpcList(context, admin.accessToken, 'get_operational_release_dashboard'),
    rpcList(context, admin.accessToken, 'get_operational_triage_issues'),
  ]);

  return {
    metrics: {
      releaseHealth: humanizeHealth(worstHealth(dashboard)),
      pendingTriage: issues.length,
    },
    activity: dashboard.slice(0, 8).map((item) => ({
      title: item.label || item.service_key || 'Operational lane',
      status: humanizeHealth(item.health_status),
      tone: toneForHealth(item.health_status),
      description: item.summary || 'Operational release signal.',
      meta: shortDate(item.last_signal_at),
    })),
    notifications: issues.slice(0, 8).map((issue) => ({
      title: issue.title || issue.issue_id || 'Incident',
      status: humanizeHealth(issue.severity),
      tone: toneForHealth(issue.severity),
      description: issue.detail || 'Operational triage alert.',
      meta: issue.reference || shortDate(issue.last_seen_at),
    })),
  };
}

async function buildRolesData(context, admin) {
  const [assignments, candidateUsers, bankPartners] = await Promise.all([
    rpcList(context, admin.accessToken, 'list_admin_role_assignments', {
      p_active_only: true,
    }),
    restList(
      context,
      admin.accessToken,
      '/users?select=id,public_user_id,full_name,phone,is_admin,created_at&order=is_admin.desc&order=created_at.desc&limit=160',
    ),
    restList(
      context,
      admin.accessToken,
      '/partners?select=id,name,is_active&is_active=eq.true&order=name.asc&limit=160',
    ),
  ]);

  const platformAdmins = new Set(
    assignments.filter((assignment) => assignment.role === 'admin').map((assignment) => assignment.user_id),
  ).size;
  const bankAdmins = new Set(
    assignments.filter((assignment) => assignment.role === 'bank').map((assignment) => assignment.user_id),
  ).size;

  return {
    metrics: {
      platformAdmins,
      bankAdmins,
      pendingApprovals: assignments.length,
    },
    activity: assignments.slice(0, 8).map((assignment) => ({
      title: assignment.user_name || assignment.user_phone || assignment.user_id,
      status: assignment.role === 'bank' ? 'Bank' : 'Platform',
      tone: assignment.role === 'bank' ? 'syncing' : 'online',
      description: assignment.partner_name
        ? `Scoped to ${assignment.partner_name}.`
        : 'Global platform administration.',
      meta: shortDate(assignment.granted_at),
    })),
    roleAssignments: assignments,
    assignableUsers: candidateUsers.map((user) => ({
      id: user.id,
      display_name: user.full_name || user.phone || user.public_user_id || user.id,
      phone: user.phone || '',
      public_user_id: user.public_user_id || '',
      is_legacy_admin: user.is_admin === true,
      label: [user.full_name || user.phone || user.public_user_id || user.id, user.phone, user.id]
        .filter(Boolean)
        .join(' · '),
    })),
    bankPartners: bankPartners.map((partner) => ({
      id: partner.id,
      name: partner.name || partner.id,
    })),
  };
}

async function buildAnalyticsData(context, admin) {
  const analytics = toObject(
    await rpcObject(context, admin.accessToken, 'get_platform_analytics_summary'),
  );

  const eventDistribution = toObject(analytics.event_distribution);
  const roleDistribution = toObject(analytics.role_distribution);

  return {
    metrics: {
      totalUsers: analytics.total_users || 0,
      activeGroups: analytics.total_groups || 0,
      adminActions: analytics.audit_actions_7d || 0,
    },
    activity: [
      {
        title: 'User growth (7d)',
        status: `${analytics.signups_7d || 0}`,
        tone: 'online',
        description: 'New users created in the last seven days.',
        meta: `30d ${analytics.signups_30d || 0}`,
      },
      {
        title: 'Partner footprint',
        status: `${analytics.active_partners || 0} active`,
        tone: 'syncing',
        description: `${analytics.total_partners || 0} total partners in the COOL backend.`,
        meta: `roles ${Object.keys(roleDistribution).length}`,
      },
      {
        title: 'Audit distribution',
        status: `${analytics.audit_actions_7d || 0} / 7d`,
        tone: 'online',
        description: Object.entries(eventDistribution)
          .slice(0, 3)
          .map(([action, count]) => `${action}:${count}`)
          .join(' · ') || 'No recent audit events.',
        meta: `admins ${analytics.total_admins || 0}`,
      },
    ],
  };
}

async function buildAuditLogData(context, admin, url) {
  const q = readTrimmedParam(url, 'q');
  const action = readTrimmedParam(url, 'action');
  const table = readTrimmedParam(url, 'table');
  const page = readPositiveInt(url, 'page', 1, { max: 500 });
  const limit = readPositiveInt(url, 'limit', 20, { min: 10, max: 50 });
  const offset = (page - 1) * limit;

  const [logRows, actions24h, updates, deletes] = await Promise.all([
    rpcList(context, admin.accessToken, 'get_admin_audit_log', {
      p_limit: limit,
      p_offset: offset,
      ...(action ? { p_action: action } : {}),
      ...(q ? { p_query: q } : {}),
      ...(table ? { p_target_table: table } : {}),
    }),
    restCount(
      context,
      admin.accessToken,
      `/admin_audit_log?select=id&created_at=gte.${encodeURIComponent(
        new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(),
      )}`,
    ),
    restCount(
      context,
      admin.accessToken,
      '/admin_audit_log?select=id&action=eq.update',
    ),
    restCount(
      context,
      admin.accessToken,
      '/admin_audit_log?select=id&action=eq.delete',
    ),
  ]);

  const totalCount = Number(logRows[0]?.total_count || 0);
  const logEntries = logRows.map((entry) => {
    const clone = { ...entry };
    delete clone.total_count;
    return clone;
  });

  const targetTables = Array.from(
    new Set(
      [
        'app_config',
        'admin_role_assignments',
        'partners',
        'partner_services',
        'quick_actions',
        ...logEntries.map((entry) => entry.target_table).filter(Boolean),
      ],
    ),
  ).sort();

  return {
    metrics: {
      actions24h,
      updates,
      deletes,
    },
    activity: logEntries.slice(0, 12).map((entry) => ({
      title: entry.actor_name || entry.actor_phone || entry.actor_id || 'Admin action',
      status: humanizeHealth(entry.action),
      tone: toneForHealth(entry.action === 'delete' ? 'error' : entry.action === 'update' ? 'warning' : 'healthy'),
      description:
        entry.notes ||
        [entry.target_table, entry.target_id].filter(Boolean).join(' · ') ||
        'Tracked admin mutation.',
      meta: shortDate(entry.created_at),
    })),
    queue: [
      {
        title: totalCount ? `Showing ${Math.min(limit, logEntries.length)} of ${totalCount}` : 'No matching audit entries',
        status: action || table ? 'Filtered' : 'All actions',
        tone: action || table ? 'syncing' : 'online',
        description:
          q || action || table
            ? `Filters: ${[q && `query "${q}"`, action && `action ${action}`, table && `table ${table}`]
                .filter(Boolean)
                .join(' · ')}`
            : 'Recent admin evidence across config, roles, and platform changes.',
        meta: `Page ${page}`,
      },
    ],
    auditEntries: logEntries,
    pagination: buildPagination({
      page,
      limit,
      total: totalCount,
    }),
    filters: {
      q: q || '',
      action: action || '',
      table: table || '',
    },
    auditCatalog: {
      actions: ['create', 'update', 'delete', 'login', 'admin_action'],
      tables: targetTables,
    },
  };
}

async function buildGroupsData(context, admin) {
  const summary = toObject(await rpcObject(context, admin.accessToken, 'get_admin_groups_summary'));
  const groups = toArray(summary.groups);

  const routingExceptions = groups.filter(
    (group) => !group.momo_number || !group.invite_code,
  ).length;

  return {
    metrics: {
      totalGroups: summary.total_groups || groups.length,
      activeGroups: summary.active_groups || 0,
      routingExceptions,
    },
    activity: groups.slice(0, 8).map((group) => ({
      title: group.name || group.id || 'Group',
      status: humanizeHealth(group.visibility || group.type || 'group'),
      tone: group.momo_number ? 'online' : 'offline',
      description: `${group.member_count || 0} members · ${group.country || 'RW'}`,
      meta: shortDate(group.created_at),
    })),
  };
}

async function buildSavingsData(context, admin) {
  const detail = toObject(
    await rpcObject(context, admin.accessToken, 'admin_get_savings_groups_detail'),
  );
  const savingsGroups = toArray(detail.savings_groups);
  const communityGroups = toArray(detail.community_groups);

  return {
    metrics: {
      savingsMomoCode: detail.savings_momo_code || '',
      totalSavingsGroups: detail.total_savings_groups || 0,
      activeSavingsGroups: detail.active_savings_groups || 0,
      totalCommunityGroups: detail.total_community_groups || 0,
      totalMembersInSavings: detail.total_members_in_savings || 0,
      totalCollected: detail.total_collected || 0,
    },
    savingsGroups: savingsGroups.map((group) => ({
      id: group.id,
      name: group.name || 'Unnamed',
      description: group.description || '',
      targetAmount: group.target_amount || 0,
      monthlyContribution: group.monthly_contribution || 0,
      frequency: group.frequency || 'monthly',
      momoNumber: group.momo_number || '',
      inviteCode: group.invite_code || '',
      isClosed: group.is_closed === true,
      memberCount: group.member_count || 0,
      totalCollected: group.total_collected || 0,
      createdAt: group.created_at,
      members: toArray(group.members),
    })),
    communityGroups: communityGroups.slice(0, 20).map((group) => ({
      id: group.id,
      name: group.name || 'Unnamed',
      visibility: group.visibility || 'public',
      isClosed: group.is_closed === true,
      memberCount: group.member_count || 0,
      createdAt: group.created_at,
    })),
  };
}

async function rpcList(context, accessToken, rpcName, body = {}) {
  const result = await supabaseFetch(context, `/rest/v1/rpc/${rpcName}`, {
    method: 'POST',
    accessToken,
    body,
  });

  if (!result.response.ok) {
    throw new Error(resolveUpstreamMessage(result, `Failed to load ${rpcName}.`));
  }

  return toArray(result.data);
}

async function rpcObject(context, accessToken, rpcName, body = {}) {
  const result = await supabaseFetch(context, `/rest/v1/rpc/${rpcName}`, {
    method: 'POST',
    accessToken,
    body,
  });

  if (!result.response.ok) {
    throw new Error(resolveUpstreamMessage(result, `Failed to load ${rpcName}.`));
  }

  return result.data;
}

async function restList(context, accessToken, path) {
  const result = await supabaseFetch(context, `/rest/v1${path}`, {
    method: 'GET',
    accessToken,
    includeJsonContentType: false,
  });

  if (!result.response.ok) {
    throw new Error(resolveUpstreamMessage(result, `Failed to load ${path}.`));
  }

  return toArray(result.data);
}

async function restListPage(context, accessToken, path) {
  const result = await supabaseFetch(context, `/rest/v1${path}`, {
    method: 'GET',
    accessToken,
    includeJsonContentType: false,
    extraHeaders: { Prefer: 'count=exact' },
  });

  if (!result.response.ok) {
    throw new Error(resolveUpstreamMessage(result, `Failed to load ${path}.`));
  }

  return {
    rows: toArray(result.data),
    total: parseContentRangeTotal(result.response.headers.get('content-range')),
  };
}

async function restCount(context, accessToken, path) {
  const page = await restListPage(
    context,
    accessToken,
    `${path}${path.includes('?') ? '&' : '?'}limit=1&offset=0`,
  );
  return page.total;
}

function resolveUpstreamMessage(result, fallback) {
  const details =
    result?.data && typeof result.data === 'object' ? result.data : {};
  return details.message || details.error || details.error_description || fallback;
}

function parseContentRangeTotal(contentRange) {
  const match = /\/(\d+|\*)$/.exec(contentRange || '');
  if (!match || match[1] === '*') {
    return 0;
  }
  return Number(match[1]) || 0;
}

function readTrimmedParam(url, key) {
  return url?.searchParams?.get(key)?.trim() || '';
}

function readPositiveInt(url, key, fallback, { min = 1, max = 100 } = {}) {
  const raw = Number.parseInt(url?.searchParams?.get(key) || '', 10);
  if (!Number.isFinite(raw)) {
    return fallback;
  }
  return Math.min(max, Math.max(min, raw));
}

function buildPagination({ page, limit, total }) {
  const resolvedTotal = Math.max(0, Number(total) || 0);
  const totalPages = Math.max(1, Math.ceil(resolvedTotal / limit) || 1);
  return {
    page,
    limit,
    total: resolvedTotal,
    totalPages,
    hasPreviousPage: page > 1,
    hasNextPage: page < totalPages,
  };
}

function sanitizeSearchTerm(value) {
  return String(value || '')
    .replaceAll('*', '')
    .replaceAll('(', ' ')
    .replaceAll(')', ' ')
    .replaceAll(',', ' ')
    .trim();
}
