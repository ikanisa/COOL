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
    const data = await buildRouteData(context, route, admin);
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

async function buildRouteData(context, route, admin) {
  switch (route) {
    case 'admin':
    case 'index':
      return buildWorkspaceData(admin);
    case 'platform':
      return await buildPlatformData(context, admin);
    case 'users':
      return await buildUsersData(context, admin);
    case 'app-config':
      return await buildAppConfigData(context, admin);
    case 'operations':
      return await buildOperationsData(context, admin);
    case 'roles':
      return await buildRolesData(context, admin);
    case 'analytics':
      return await buildAnalyticsData(context, admin);
    case 'audit-log':
      return await buildAuditLogData(context, admin);
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

async function buildUsersData(context, admin) {
  const [users, roleAssignments] = await Promise.all([
    restList(
      context,
      admin.accessToken,
      '/users?select=id,public_user_id,full_name,phone,country,language_code,momo_provider,is_admin,created_at,is_mock,mock_batch&order=is_mock.desc&order=created_at.desc',
    ),
    rpcList(context, admin.accessToken, 'list_admin_role_assignments', {
      p_active_only: true,
    }),
  ]);

  const assignmentsByUser = new Map();
  for (const assignment of roleAssignments) {
    const userAssignments = assignmentsByUser.get(assignment.user_id) || [];
    userAssignments.push(assignment);
    assignmentsByUser.set(assignment.user_id, userAssignments);
  }

  const normalizedUsers = users.map((user) => {
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
    normalizedUsers
      .filter((user) => user.has_platform_access || user.bank_assignment_count > 0)
      .map((user) => user.id),
  ).size;

  return {
    metrics: {
      managedAccounts: normalizedUsers.length,
      adminAccounts,
      recoveryQueue: normalizedUsers.filter((user) => !user.phone || !user.full_name).length,
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
  };
}

async function buildAppConfigData(context, admin) {
  const [configs, routes] = await Promise.all([
    restList(
      context,
      admin.accessToken,
      '/app_config?select=key,value,description,country,created_at,updated_at&order=key.asc',
    ),
    restList(
      context,
      admin.accessToken,
      '/partner_payment_routes?select=id,status,updated_at,reconciliation_label&order=updated_at.desc',
    ),
  ]);

  const updatedRecently = configs.filter((entry) => {
    const updatedAt = entry.updated_at ? Date.parse(entry.updated_at) : Number.NaN;
    return Number.isFinite(updatedAt) && updatedAt >= Date.now() - 24 * 60 * 60 * 1000;
  }).length;

  return {
    metrics: {
      rolloutKeys: configs.length,
      partnerRoutes: routes.length,
      pendingChanges: updatedRecently,
    },
    activity: configs.slice(0, 8).map((entry) => ({
      title: entry.key || 'Config entry',
      status: entry.country ? String(entry.country).toUpperCase() : 'Platform',
      tone: entry.country ? 'syncing' : 'online',
      description: entry.description || entry.value || 'Runtime app configuration.',
      meta: shortDate(entry.updated_at || entry.created_at),
    })),
    configEntries: configs,
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
  const assignments = await rpcList(context, admin.accessToken, 'list_admin_role_assignments', {
    p_active_only: true,
  });

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

async function buildAuditLogData(context, admin) {
  const logEntries = await rpcList(context, admin.accessToken, 'get_admin_audit_log', {
    p_limit: 30,
    p_offset: 0,
  });

  const actions24h = logEntries.filter((entry) => {
    const createdAt = entry.created_at ? Date.parse(entry.created_at) : Number.NaN;
    return Number.isFinite(createdAt) && createdAt >= Date.now() - 24 * 60 * 60 * 1000;
  }).length;

  return {
    metrics: {
      actions24h,
      updates: logEntries.filter((entry) => entry.action === 'update').length,
      deletes: logEntries.filter((entry) => entry.action === 'delete').length,
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

function resolveUpstreamMessage(result, fallback) {
  const details =
    result?.data && typeof result.data === 'object' ? result.data : {};
  return details.message || details.error || details.error_description || fallback;
}
