import {
  dbAdd,
  dbCount,
  dbGet,
  dbGetAll,
  dbPutRecord,
  dbSet,
} from './idb.js';
import {
  initializeInstallPromptCapture,
  initializeBannerActions,
  updateShellState,
} from './app_install.js';
import {
  initializeNotificationControls,
  updateBadge,
} from './app_notifications.js';
import {
  applyPageData,
  initializeQuickActions,
  initializeRouteNavigation,
  initializeScrollPersistence,
  initializeShareButtons,
  initializeShareTargetView,
  observeWebVitals,
  populatePageData,
  showToast,
} from './app_page.js';
import {
  clearAdminSession,
  fetchAdminRouteData,
  getAdminSessionState,
  mutateAdmin,
  sendAdminOtp,
  verifyAdminOtp,
} from './admin_api.js';
import {
  clearRouteRestriction,
  renderAuditLogPanel,
  renderAppConfigPanel,
  renderAuthGate,
  renderRolesPanel,
  renderRouteRestriction,
  renderSessionToolbar,
  renderUsersPanel,
} from './admin_views.js';

const SETTINGS = {
  theme: 'theme',
  visits: 'visits',
  successMoments: 'success_moments',
  installDismissedAt: 'install_dismissed_at',
  installImpressionAt: 'install_impression_at',
  scrollPrefix: 'scroll:',
  lastOnlineAt: 'last_online_at',
  badgeClearedAt: 'badge_cleared_at',
};

// Only these routes support live interactive mutations.
// Other routes render as read-only preview with a banner.
const MVP_LIVE_ROUTES = new Set([
  'index',
  'admin',
  'platform',
  'users',
  'app-config',
  'roles',
  'audit-log',
]);

const ROUTE_DATA = {
  index: '/data/admin.json',
  groups: '/data/groups.json',
  admin: '/data/admin.json',
  platform: '/data/platform.json',
  users: '/data/users.json',
  'app-config': '/data/app-config.json',
  operations: '/data/operations.json',
  roles: '/data/roles.json',
  analytics: '/data/analytics.json',
  'audit-log': '/data/audit-log.json',
};

const state = {
  registration: null,
  deferredPrompt: null,
  installEligible: false,
  updateReady: false,
  isStandalone:
    window.matchMedia('(display-mode: standalone)').matches ||
    window.navigator.standalone === true,
  isIosSafari: /iPad|iPhone|iPod/.test(window.navigator.userAgent) ||
      (window.navigator.platform === 'MacIntel' &&
          window.navigator.maxTouchPoints > 1)
    ? /Safari/i.test(window.navigator.userAgent) &&
      !/CriOS|FxiOS|EdgiOS|Chrome|Android/i.test(window.navigator.userAgent)
    : false,
  installImpressionTracked: false,
  admin: {
    live: false,
    authenticated: false,
    authorized: false,
    user: null,
    access: null,
  },
  authFlow: {
    step: 'phone',
    phone: '',
    isLoading: false,
    error: null,
    errorCode: null,
  },
  routeData: null,
};

document.addEventListener('DOMContentLoaded', () => {
  void initializeApp();
});

async function initializeApp() {
  const route = document.body.dataset.route ?? 'index';
  await recordVisit();
  await initializeTheme();
  initializeInstallPromptCapture({
    state,
    settings: SETTINGS,
    dbSet,
    trackEvent,
    showToast,
    updateShellState: refreshInstallShell,
  });
  await registerServiceWorker();
  initializeConnectivityIndicators();
  initializeBannerActions({
    state,
    settings: SETTINGS,
    dbSet,
    trackEvent,
    showToast,
    updateShellState: refreshInstallShell,
  });
  initializeShareButtons({ recordSuccessMoment, trackEvent, showToast });
  initializeQueueForms();
  initializeNotificationControls({
    state,
    dbGetAll,
    dbPutRecord,
    trackEvent,
    recordSuccessMoment,
    refreshDerivedUi,
    showToast,
  });
  initializeShareTargetView({ dbPutRecord, trackEvent });
  initializeQuickActions({
    recordSuccessMoment,
    showToast,
    updateShellState: refreshInstallShell,
  });
  initializeScrollPersistence(SETTINGS);
  initializeRouteNavigation();
  await initializeAdminExperience(route);
  await refreshDerivedUi();
  observeWebVitals(trackEvent);
  refreshInstallShell();
}

async function initializeAdminExperience(route) {
  state.admin = await getAdminSessionState();
  renderAdminShell();

  // Static local preview — show demo data
  if (!state.admin.live) {
    state.routeData = await populatePageData({ routeData: ROUTE_DATA, route, showToast });
    bindRouteEnhancements(route, state.routeData, { interactive: false });
    return;
  }

  if (!state.admin.authorized) {
    state.routeData = null;
    clearRouteRestriction();
    bindRouteEnhancements(route, null, { interactive: false });
    return;
  }

  // Determine if this route supports live mutations
  const isLiveRoute = MVP_LIVE_ROUTES.has(route);

  let liveData;
  try {
    liveData = await fetchAdminRouteData(route);
  } catch (err) {
    console.error('Live admin route load failed.', err);
    // In production: show explicit error state instead of falling back to demo data
    renderMaintenanceState(
      'COOL Admin is experiencing an issue.',
      'The admin API did not respond. Retry shortly or contact the platform team.',
    );
    await trackEvent('admin_route_load_error', { route, message: String(err) });
    return;
  }

  if (!liveData || liveData?.unavailable) {
    renderMaintenanceState(
      'Admin data unavailable.',
      'The admin API for this route is not responding. Data may be stale.',
    );
    await trackEvent('admin_route_unavailable', { route });
    return;
  }

  if (liveData?.unauthorized) {
    await handleAdminSignOut({
      preservePhone: state.authFlow.phone,
      suppressReload: true,
    });
    return;
  }

  if (liveData?.forbidden) {
    state.routeData = null;
    renderRouteRestriction(liveData.message);
    bindRouteEnhancements(route, null, { interactive: false });
    return;
  }

  clearRouteRestriction();
  document.querySelector('[data-maintenance-banner]')?.remove();
  if (isLiveRoute) {
    document.querySelector('[data-read-only-banner]')?.remove();
  }
  applyPageData(liveData);
  state.routeData = liveData;

  if (!isLiveRoute) {
    renderReadOnlyBanner();
  }

  bindRouteEnhancements(route, liveData, { interactive: isLiveRoute });
}

function renderMaintenanceState(title, message) {
  const main = document.getElementById('main');
  if (!main) {
    return;
  }
  main.querySelector('[data-maintenance-banner]')?.remove();
  const banner = document.createElement('section');
  banner.className = 'section-header';
  banner.setAttribute('data-maintenance-banner', '');
  banner.innerHTML = `
    <div class="metric-card card" style="border-left:4px solid var(--accent-error,#ef4444)">
      <span class="metric-label">${title}</span>
      <div class="metric-meta">${message}</div>
      <div class="button-row" style="margin-top:var(--space-3,12px)">
        <button class="button" type="button" onclick="window.location.reload()">Retry</button>
      </div>
    </div>`;
  main.prepend(banner);
}

function renderReadOnlyBanner() {
  const main = document.getElementById('main');
  if (!main) {
    return;
  }
  main.querySelector('[data-read-only-banner]')?.remove();
  const banner = document.createElement('div');
  banner.className = 'metric-card card';
  banner.setAttribute('data-read-only-banner', '');
  banner.style.cssText = 'border-left:4px solid var(--accent-warning,#f59e0b);margin-bottom:var(--space-4,16px)';
  banner.innerHTML = `
    <span class="metric-label">Read-only preview</span>
    <div class="metric-meta">This route shows live data but does not support mutations in the current MVP. Interactive controls are disabled.</div>`;
  main.prepend(banner);
}

function renderAdminShell() {
  renderSessionToolbar({
    authState: state.admin,
    onSignOut: handleAdminSignOut,
  });
  renderAuthGate({
    authState: state.admin,
    otpState: state.authFlow,
    onSendCode: handleAdminSendCode,
    onVerifyCode: handleAdminVerifyCode,
    onSignOut: handleAdminSignOut,
  });
}

async function handleAdminSendCode(phone) {
  state.authFlow = {
    step: 'phone',
    phone,
    isLoading: true,
    error: null,
    errorCode: null,
  };
  renderAdminShell();

  try {
    await sendAdminOtp(phone);
    state.authFlow = {
      step: 'code',
      phone,
      isLoading: false,
      error: null,
      errorCode: null,
    };
    showToast('If the number is authorized, a verification code will arrive shortly.');
  } catch (error) {
    const message = String(error?.message || error);
    let errorCode = null;
    try {
      if (error?.code) {
        errorCode = error.code;
      }
    } catch (_) {}

    state.authFlow = {
      step: 'phone',
      phone,
      isLoading: false,
      error: message,
      errorCode,
    };
  }

  renderAdminShell();
}

async function handleAdminVerifyCode(code) {
  state.authFlow = {
    ...state.authFlow,
    isLoading: true,
    error: null,
  };
  renderAdminShell();

  try {
    await verifyAdminOtp(state.authFlow.phone, code);
    state.authFlow = {
      step: 'phone',
      phone: state.authFlow.phone,
      isLoading: false,
      error: null,
      errorCode: null,
    };
    await initializeAdminExperience(document.body.dataset.route ?? 'index');
    showToast('COOL Admin is live with your authenticated session.');
  } catch (error) {
    state.authFlow = {
      ...state.authFlow,
      isLoading: false,
      error: String(error?.message || error),
      errorCode: error?.code || null,
    };
    renderAdminShell();
  }
}

async function handleAdminSignOut({ preservePhone = false, suppressReload = false } = {}) {
  const phone = preservePhone && typeof preservePhone === 'string'
    ? preservePhone
    : preservePhone
      ? state.authFlow.phone
      : '';

  await clearAdminSession();
  state.authFlow = {
    step: 'phone',
    phone,
    isLoading: false,
    error: null,
    errorCode: null,
  };

  if (!suppressReload) {
    window.location.reload();
    return;
  }

  state.admin = await getAdminSessionState();
  renderAdminShell();
}

function bindRouteEnhancements(route, data, { interactive } = { interactive: false }) {
  switch (route) {
    case 'users':
      renderUsersPanel({
        data,
        onFilterChange: (filters) => updateRouteQueryAndReload(route, filters),
        onPageChange: (page) => updateRouteQueryAndReload(route, { page }),
        onTogglePlatformAccess: interactive
          ? async (user) => {
              try {
                await mutateAdmin('toggle_user_platform_access', {
                  userId: user.id,
                  enabled: !user.has_platform_access,
                  assignmentId: user.platform_assignment_id,
                  notes: user.has_platform_access
                    ? 'Revoked from COOL Admin PWA.'
                    : 'Granted from COOL Admin PWA.',
                });
                await initializeAdminExperience(route);
                showToast(
                  user.has_platform_access
                    ? 'Platform access revoked.'
                    : 'Platform access granted.',
                );
              } catch (error) {
                await handleAdminMutationError('toggle_user_platform_access', error, {
                  route,
                  userId: user.id,
                });
              }
            }
          : null,
      });
      break;
    case 'app-config':
      renderAppConfigPanel({
        data,
        onFilterChange: (filters) => updateRouteQueryAndReload(route, filters),
        onPageChange: (page) => updateRouteQueryAndReload(route, { page }),
        onSaveConfig: interactive
          ? async (payload) => {
              try {
                await mutateAdmin('upsert_app_config', payload);
                await initializeAdminExperience(route);
                showToast(`Saved config key ${payload.key}.`);
              } catch (error) {
                await handleAdminMutationError('upsert_app_config', error, {
                  route,
                  key: payload.key,
                });
              }
            }
          : null,
      });
      break;
    case 'roles':
      renderRolesPanel({
        data,
        onAssignRole: interactive
          ? async (payload) => {
              try {
                await mutateAdmin('assign_role', payload);
                await initializeAdminExperience(route);
                showToast(`Assigned ${payload.role} access.`);
              } catch (error) {
                await handleAdminMutationError('assign_role', error, {
                  route,
                  role: payload.role,
                  targetUserId: payload.targetUserId,
                });
              }
            }
          : null,
        onRevokeRole: interactive
          ? async ({ assignmentId }) => {
              try {
                await mutateAdmin('revoke_role', {
                  assignmentId,
                  notes: 'Revoked from COOL Admin PWA.',
                });
                await initializeAdminExperience(route);
                showToast('Role assignment revoked.');
              } catch (error) {
                await handleAdminMutationError('revoke_role', error, {
                  route,
                  assignmentId,
                });
              }
            }
          : null,
      });
      break;
    case 'audit-log':
      renderAuditLogPanel({
        data,
        onFilterChange: (filters) => updateRouteQueryAndReload(route, filters),
        onPageChange: (page) => updateRouteQueryAndReload(route, { page }),
      });
      break;
    default:
      break;
  }
}

async function updateRouteQueryAndReload(route, updates = {}) {
  const params = new URLSearchParams(window.location.search);
  Object.entries(updates).forEach(([key, value]) => {
    const normalized = typeof value === 'string' ? value.trim() : value;
    if (
      normalized === '' ||
      normalized === null ||
      normalized === undefined ||
      normalized === false
    ) {
      params.delete(key);
      return;
    }
    params.set(key, String(normalized));
  });

  const next = `${window.location.pathname}${params.toString() ? `?${params}` : ''}`;
  window.history.replaceState({}, '', next);
  await initializeAdminExperience(route);
}

async function handleAdminMutationError(action, error, detail = {}) {
  const message = String(error?.message || error || 'Admin action failed.');
  showToast(message);
  await trackEvent('admin_mutation_error', {
    action,
    ...detail,
    message,
    code: error?.code || null,
  });
}

function refreshInstallShell() {
  updateShellState({
    state,
    settings: SETTINGS,
    dbSet,
    trackEvent,
  });
}

async function recordVisit() {
  const visits = Number(await dbGet('settings', SETTINGS.visits) ?? 0) + 1;
  await dbSet('settings', SETTINGS.visits, visits);
  await trackEvent('visit_recorded', { visits });
}

async function initializeTheme() {
  const html = document.documentElement;
  const storedTheme = await dbGet('settings', SETTINGS.theme);
  const systemDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
  const effectiveTheme =
    storedTheme === 'light' || storedTheme === 'dark'
      ? storedTheme
      : systemDark
        ? 'dark'
        : 'light';

  html.dataset.theme = effectiveTheme;
  document.querySelectorAll('[data-theme-toggle]').forEach((button) => {
    button.addEventListener('click', async () => {
      const nextTheme = html.dataset.theme === 'dark' ? 'light' : 'dark';
      html.dataset.theme = nextTheme;
      await dbSet('settings', SETTINGS.theme, nextTheme);
      await trackEvent('theme_changed', { theme: nextTheme });
    });
  });
}

async function registerServiceWorker() {
  if (!('serviceWorker' in navigator)) {
    return;
  }

  try {
    const hadControllerBeforeRegister = Boolean(navigator.serviceWorker.controller);
    let handledControllerChange = false;
    const registration = await navigator.serviceWorker.register(
      '/service-worker.js',
    );
    state.registration = registration;

    if ('periodicSync' in registration) {
      try {
        await registration.periodicSync.register('cool-content-refresh', {
          minInterval: 24 * 60 * 60 * 1000,
        });
      } catch (_) {
        // Periodic background sync remains best-effort.
      }
    }

    registration.addEventListener('updatefound', () => {
      const worker = registration.installing;
      if (!worker) {
        return;
      }
      worker.addEventListener('statechange', () => {
        if (
          worker.state === 'installed' &&
          navigator.serviceWorker.controller
        ) {
          state.updateReady = true;
          void trackEvent('service_worker_update_ready');
          refreshInstallShell();
        }
      });
    });

    navigator.serviceWorker.addEventListener('message', async (event) => {
      const { data } = event;
      if (!data || typeof data !== 'object') {
        return;
      }

      if (data.type === 'SYNC_COMPLETE') {
        await trackEvent('sync_complete', data.detail ?? {});
      showToast('Queued admin work synced successfully.');
      }

      if (data.type === 'SHARE_TARGET_RECEIVED') {
        showToast('Shared content saved to the admin console.');
      }

      if (data.type === 'QUEUE_COUNT') {
        await updateBadge({ dbGetAll }, data.count ?? 0);
      }
    });

    navigator.serviceWorker.addEventListener('controllerchange', () => {
      if (handledControllerChange) {
        return;
      }
      if (!hadControllerBeforeRegister && !state.updateReady) {
        return;
      }
      handledControllerChange = true;
      state.updateReady = false;
      window.location.reload();
    });
  } catch (error) {
    console.error('Service worker registration failed.', error);
    await trackEvent('service_worker_error', { message: String(error) });
  }
}

function initializeConnectivityIndicators() {
  const updateConnectivity = async () => {
    const online = navigator.onLine;
    document.body.classList.toggle('is-offline', !online);
    document.querySelectorAll('[data-online-indicator]').forEach((node) => {
      node.textContent = online ? 'Online' : 'Offline';
      node.classList.toggle('online', online);
      node.classList.toggle('offline', !online);
    });

    if (online) {
      await dbSet('settings', SETTINGS.lastOnlineAt, new Date().toISOString());
      await flushQueuedActions('online');
    }
  };

  window.addEventListener('online', () => void updateConnectivity());
  window.addEventListener('offline', () => void updateConnectivity());
  void updateConnectivity();
}

function initializeQueueForms() {
  document.querySelectorAll('[data-queue-form]').forEach((formNode) => {
    formNode.addEventListener('submit', async (event) => {
      event.preventDefault();
      const form = event.currentTarget;
      const formData = new FormData(form);
      const payload = Object.fromEntries(formData.entries());
      const queueItem = {
        id: crypto.randomUUID(),
        type: form.getAttribute('data-queue-type') ?? 'generic_action',
        endpoint: form.getAttribute('data-endpoint') ?? 'demo://local',
        createdAt: new Date().toISOString(),
        path: window.location.pathname,
        payload,
        status: 'pending',
      };

      await dbPutRecord('queue', queueItem);
      await persistDraft(form.id || queueItem.type, payload);
      await recordSuccessMoment('queued_action');
      await trackEvent('queue_action_enqueued', {
        type: queueItem.type,
        endpoint: queueItem.endpoint,
      });

      if ('sync' in (state.registration ?? {})) {
        try {
          await state.registration.sync.register('cool-sync');
        } catch (_) {
          // Foreground flush handles unsupported or denied sync registration.
        }
      }

      showToast('Action saved. COOL Admin will sync it safely.');
      form.reset();
      await flushQueuedActions('foreground');
      await refreshDerivedUi();
    });

    void restoreDraft(formNode);
  });
}

async function restoreDraft(form) {
  if (!form.id) {
    return;
  }

  const draft = await dbGet('drafts', form.id);
  if (!draft) {
    return;
  }

  for (const [key, value] of Object.entries(draft)) {
    const input = form.elements.namedItem(key);
    if (input && 'value' in input) {
      input.value = value;
    }
  }
}

async function persistDraft(key, payload) {
  await dbSet('drafts', key, payload);
}

async function flushQueuedActions(reason) {
  if (!navigator.onLine) {
    return;
  }

  const queue = await dbGetAll('queue');
  const pending = queue.filter((entry) => entry.status === 'pending');
  if (!pending.length) {
    await updateBadge({ dbGetAll }, 0);
    return;
  }

  let synced = 0;
  let failed = 0;

  for (const item of pending) {
    try {
      if (item.endpoint.startsWith('demo://')) {
        // Skip demo endpoints — do not auto-mark as synced in production
        continue;
      }

      const response = await fetch(item.endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'same-origin',
        body: JSON.stringify(item.payload),
      });
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }

      item.status = 'synced';
      item.syncedAt = new Date().toISOString();
      item.syncReason = reason;
      await dbPutRecord('queue', item);
      synced++;
    } catch (error) {
      item.status = 'pending';
      item.lastError = String(error);
      item.lastAttemptAt = new Date().toISOString();
      await dbPutRecord('queue', item);
      failed++;
    }
  }

  await trackEvent('queue_flush', { reason, synced, failed });
  await refreshDerivedUi();
}

async function refreshDerivedUi() {
  const visits = Number(await dbGet('settings', SETTINGS.visits) ?? 0);
  const successMoments = Number(
    await dbGet('settings', SETTINGS.successMoments) ?? 0,
  );
  const queued = (await dbGetAll('queue')).filter(
    (entry) => entry.status === 'pending',
  ).length;
  const unreadNotifications = (await dbGetAll('notifications')).filter(
    (entry) => entry.unread,
  ).length;
  const shares = await dbCount('shares');

  state.installEligible = visits >= 2 || successMoments >= 1;

  document.querySelectorAll('[data-setting="visits"]').forEach((node) => {
    node.textContent = String(visits);
  });
  document.querySelectorAll('[data-setting="successes"]').forEach((node) => {
    node.textContent = String(successMoments);
  });
  document.querySelectorAll('[data-setting="queued"]').forEach((node) => {
    node.textContent = String(queued);
  });
  document.querySelectorAll('[data-setting="notifications"]').forEach((node) => {
    node.textContent = String(unreadNotifications);
  });
  document.querySelectorAll('[data-setting="shares"]').forEach((node) => {
    node.textContent = String(shares);
  });

  await updateBadge({ dbGetAll }, unreadNotifications);
  refreshInstallShell();
}

async function recordSuccessMoment(reason) {
  const next =
    Number(await dbGet('settings', SETTINGS.successMoments) ?? 0) + 1;
  await dbSet('settings', SETTINGS.successMoments, next);
  await trackEvent('success_moment_recorded', { reason, count: next });
}

async function trackEvent(name, detail = {}) {
  const appVersion = document
    .querySelector('meta[name="app-version"]')
    ?.content?.trim() || 'unknown';

  const payload = {
    id: crypto.randomUUID(),
    name,
    detail,
    path: window.location.pathname,
    online: navigator.onLine,
    ts: new Date().toISOString(),
    version: appVersion,
  };

  window.dataLayer = window.dataLayer || [];
  window.dataLayer.push(payload);
  await dbAdd('events', payload);

  const analyticsEndpoint = document
    .querySelector('meta[name="analytics-endpoint"]')
    ?.content?.trim() || '/api/admin/telemetry';
  if (analyticsEndpoint && navigator.sendBeacon) {
    navigator.sendBeacon(analyticsEndpoint, JSON.stringify(payload));
  }
}

// ── Browser error reporting ──────────────────────────────────
window.addEventListener('error', (event) => {
  void trackEvent('browser_error', {
    message: event.message,
    filename: event.filename,
    lineno: event.lineno,
    colno: event.colno,
  });
});

window.addEventListener('unhandledrejection', (event) => {
  void trackEvent('unhandled_rejection', {
    reason: String(event.reason),
  });
});
