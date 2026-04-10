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
import { initializePasskeyControls } from './app_passkeys.js';
import {
  initializeQuickActions,
  initializeRouteNavigation,
  initializeScrollPersistence,
  initializeShareButtons,
  initializeShareTargetView,
  observeWebVitals,
  populatePageData,
  showToast,
} from './app_page.js';

const SETTINGS = {
  theme: 'theme',
  visits: 'visits',
  successMoments: 'success_moments',
  installDismissedAt: 'install_dismissed_at',
  installImpressionAt: 'install_impression_at',
  scrollPrefix: 'scroll:',
  lastOnlineAt: 'last_online_at',
  badgeClearedAt: 'badge_cleared_at',
  passkeyLastVerifiedAt: 'passkey_last_verified_at',
};

const ROUTE_DATA = {
  index: '/data/home.json',
  home: '/data/home.json',
  groups: '/data/groups.json',
  momo: '/data/momo.json',
  profile: '/data/profile.json',
  admin: '/data/admin.json',
  notifications: '/data/notifications.json',
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
};

document.addEventListener('DOMContentLoaded', () => {
  void initializeApp();
});

async function initializeApp() {
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
  initializePasskeyControls({
    settings: SETTINGS,
    dbGetAll,
    dbPutRecord,
    dbSet,
    trackEvent,
    recordSuccessMoment,
  });
  initializeShareTargetView({ dbPutRecord, trackEvent });
  initializeQuickActions({
    recordSuccessMoment,
    showToast,
    updateShellState: refreshInstallShell,
  });
  initializeScrollPersistence(SETTINGS);
  initializeRouteNavigation();
  await populatePageData({ routeData: ROUTE_DATA, showToast });
  await refreshDerivedUi();
  observeWebVitals(trackEvent);
  refreshInstallShell();
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
        showToast('Queued work synced successfully.');
      }

      if (data.type === 'SHARE_TARGET_RECEIVED') {
        showToast('Shared content saved to COOL.');
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

      showToast('Action saved. COOL will sync it safely.');
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
      if (!item.endpoint.startsWith('demo://')) {
        const response = await fetch(item.endpoint, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(item.payload),
        });
        if (!response.ok) {
          throw new Error(`HTTP ${response.status}`);
        }
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
  const payload = {
    id: crypto.randomUUID(),
    name,
    detail,
    path: window.location.pathname,
    online: navigator.onLine,
    ts: new Date().toISOString(),
  };

  window.dataLayer = window.dataLayer || [];
  window.dataLayer.push(payload);
  await dbAdd('events', payload);

  const analyticsEndpoint = document
    .querySelector('meta[name="analytics-endpoint"]')
    ?.content?.trim();
  if (analyticsEndpoint && navigator.sendBeacon) {
    navigator.sendBeacon(analyticsEndpoint, JSON.stringify(payload));
  }
}
