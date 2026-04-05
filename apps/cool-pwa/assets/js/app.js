import {
  dbAdd,
  dbCount,
  dbDelete,
  dbGet,
  dbGetAll,
  dbPutRecord,
  dbSet,
} from './idb.js';

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
  isStandalone: window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone === true,
  isIosSafari: /iPad|iPhone|iPod/.test(window.navigator.userAgent) ||
    (window.navigator.platform === 'MacIntel' && window.navigator.maxTouchPoints > 1)
      ? /Safari/i.test(window.navigator.userAgent) && !/CriOS|FxiOS|EdgiOS|Chrome|Android/i.test(window.navigator.userAgent)
      : false,
  installImpressionTracked: false,
};

document.addEventListener('DOMContentLoaded', () => {
  void initializeApp();
});

async function initializeApp() {
  await recordVisit();
  await initializeTheme();
  initializeInstallPromptCapture();
  await registerServiceWorker();
  initializeConnectivityIndicators();
  initializeBannerActions();
  initializeShareButtons();
  initializeQueueForms();
  initializeNotificationControls();
  initializePasskeyControls();
  initializeShareTargetView();
  initializeQuickActions();
  initializeScrollPersistence();
  initializeRouteNavigation();
  await populatePageData();
  await refreshDerivedUi();
  observeWebVitals();
  updateShellState();
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
  const effectiveTheme = storedTheme === 'light' || storedTheme === 'dark'
    ? storedTheme
    : (systemDark ? 'dark' : 'light');

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

function initializeInstallPromptCapture() {
  window.addEventListener('beforeinstallprompt', async (event) => {
    event.preventDefault();
    state.deferredPrompt = event;
    await trackEvent('install_prompt_ready');
    updateShellState();
  });

  window.addEventListener('appinstalled', async () => {
    state.deferredPrompt = null;
    state.installEligible = false;
    await dbSet('settings', SETTINGS.installDismissedAt, null);
    window.localStorage.removeItem(SETTINGS.installDismissedAt);
    await trackEvent('install_success');
    showToast('COOL is installed and ready offline.');
    updateShellState();
  });
}

async function registerServiceWorker() {
  if (!('serviceWorker' in navigator)) {
    return;
  }

  try {
    const registration = await navigator.serviceWorker.register('/service-worker.js');
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
        if (worker.state === 'installed' && navigator.serviceWorker.controller) {
          state.updateReady = true;
          void trackEvent('service_worker_update_ready');
          updateShellState();
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
        await updateBadge(data.count ?? 0);
      }
    });

    navigator.serviceWorker.addEventListener('controllerchange', () => {
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

function initializeBannerActions() {
  document.querySelectorAll('[data-install-action]').forEach((button) => {
    button.addEventListener('click', async () => {
      if (state.deferredPrompt) {
        await state.deferredPrompt.prompt();
        const choice = await state.deferredPrompt.userChoice;
        await trackEvent('install_prompt_result', { outcome: choice.outcome });
        if (choice.outcome !== 'accepted') {
          await markInstallDismissed();
        }
        state.deferredPrompt = null;
        updateShellState();
        return;
      }

      openIosInstallSheet();
      await trackEvent('install_instruction_opened', { platform: 'ios_safari' });
    });
  });

  document.querySelectorAll('[data-install-dismiss]').forEach((button) => {
    button.addEventListener('click', async () => {
      await markInstallDismissed();
      updateShellState();
    });
  });

  document.querySelectorAll('[data-update-action]').forEach((button) => {
    button.addEventListener('click', () => {
      state.registration?.waiting?.postMessage({ type: 'SKIP_WAITING' });
    });
  });

  document.querySelectorAll('[data-download-offline]').forEach((button) => {
    button.addEventListener('click', () => {
      state.registration?.active?.postMessage({ type: 'DOWNLOAD_OFFLINE' });
      void trackEvent('offline_download_requested');
      showToast('Offline pack requested.');
    });
  });
}

function initializeShareButtons() {
  document.querySelectorAll('[data-share-button]').forEach((button) => {
    button.addEventListener('click', async () => {
      const title = button.getAttribute('data-share-title') ?? document.title;
      const text = button.getAttribute('data-share-text') ?? '';
      const url = new URL(button.getAttribute('data-share-url') ?? window.location.href, window.location.origin).toString();

      try {
        if (navigator.share) {
          await navigator.share({ title, text, url });
        } else {
          await navigator.clipboard.writeText(url);
          showToast('Link copied for sharing.');
        }
        await recordSuccessMoment('share_action');
        await trackEvent('share_action', { title, url });
      } catch (error) {
        if (String(error).includes('AbortError')) {
          return;
        }
        showToast('Share failed. Try copying the link.');
      }
    });
  });
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
    await updateBadge(0);
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

function initializeNotificationControls() {
  document.querySelectorAll('[data-enable-notifications]').forEach((button) => {
    button.addEventListener('click', async () => {
      if (!('Notification' in window)) {
        showToast('This browser does not support notifications.');
        return;
      }

      if (Notification.permission === 'granted') {
        showToast('Notifications are already enabled.');
        await updateNotificationStatus();
        return;
      }

      await trackEvent('notification_permission_requested');
      const permission = await Notification.requestPermission();
      await trackEvent('notification_permission_result', { permission });

      if (permission === 'granted') {
        await recordSuccessMoment('notifications_enabled');
        showToast('Notifications enabled.');
        await updateNotificationStatus();
      } else {
        showToast('Notifications remain disabled.');
      }
    });
  });

  document.querySelectorAll('[data-demo-notification]').forEach((button) => {
    button.addEventListener('click', async () => {
      const notification = {
        title: 'COOL sync completed',
        body: 'Your queued finance updates are now secure and current.',
        tag: 'cool-demo-sync',
        icon: '/assets/icons/Icon-192.png',
        badge: '/assets/icons/Icon-192.png',
        data: { route: '/notifications/' },
        actions: [
          { action: 'open-notifications', title: 'View alerts' },
          { action: 'open-home', title: 'Go home' },
        ],
      };

      await dbPutRecord('notifications', {
        id: crypto.randomUUID(),
        createdAt: new Date().toISOString(),
        title: notification.title,
        body: notification.body,
        unread: true,
      });
      await refreshDerivedUi();

      if (Notification.permission === 'granted' && state.registration) {
        try {
          await state.registration.showNotification(notification.title, notification);
          await trackEvent('demo_notification_shown');
          return;
        } catch (error) {
          await trackEvent('demo_notification_display_failed', { message: String(error) });
        }
      }

      await trackEvent('demo_notification_saved_in_app', {
        permission: 'Notification' in window ? Notification.permission : 'unsupported',
        registrationReady: Boolean(state.registration),
      });
      showToast('Alert saved in-app. Enable notifications for system delivery.');
    });
  });

  if (window.location.pathname.startsWith('/notifications')) {
    void markNotificationsRead();
  }

  void updateNotificationStatus();
}

async function updateNotificationStatus() {
  document.querySelectorAll('[data-notification-status]').forEach((node) => {
    if (!('Notification' in window)) {
      node.textContent = 'Unsupported';
      node.className = 'status-pill error';
      return;
    }
    const permission = Notification.permission;
    node.textContent = permission === 'granted'
      ? 'Enabled'
      : permission === 'denied'
        ? 'Blocked'
        : 'Not enabled';
    node.className = `status-pill ${permission === 'granted' ? 'online' : permission === 'denied' ? 'error' : 'offline'}`;
  });
}

async function markNotificationsRead() {
  const notifications = await dbGetAll('notifications');
  const unread = notifications.filter((entry) => entry.unread);
  await Promise.all(unread.map((entry) => dbPutRecord('notifications', { ...entry, unread: false })));
  await updateBadge(0);
}

async function updateBadge(explicitCount = null) {
  const count = explicitCount ?? (await dbGetAll('notifications')).filter((entry) => entry.unread).length;
  if ('setAppBadge' in navigator) {
    if (count > 0) {
      await navigator.setAppBadge(count);
    } else {
      await navigator.clearAppBadge();
    }
  }

  document.querySelectorAll('[data-badge-count]').forEach((node) => {
    node.textContent = String(count);
  });
}

function initializePasskeyControls() {
  document.querySelectorAll('[data-passkey-register]').forEach((button) => {
    button.addEventListener('click', async () => {
      const statusNode = document.querySelector('[data-passkey-status]');
      try {
        const result = await registerPasskey();
        statusNode.textContent = `Passkey registered for ${result.label}.`;
        await trackEvent('passkey_registered');
        await recordSuccessMoment('passkey_registered');
      } catch (error) {
        statusNode.textContent = `Passkey setup failed: ${String(error)}`;
      }
    });
  });

  document.querySelectorAll('[data-passkey-auth]').forEach((button) => {
    button.addEventListener('click', async () => {
      const statusNode = document.querySelector('[data-passkey-status]');
      try {
        const result = await verifyPasskey();
        statusNode.textContent = `Verified with ${result.label}.`;
        await dbSet('settings', SETTINGS.passkeyLastVerifiedAt, new Date().toISOString());
        await trackEvent('passkey_verified');
      } catch (error) {
        statusNode.textContent = `Verification failed: ${String(error)}`;
      }
    });
  });
}

async function registerPasskey() {
  if (!window.PublicKeyCredential || !navigator.credentials?.create) {
    throw new Error('Passkeys are unavailable in this browser.');
  }

  const label = document.querySelector('[data-passkey-name]')?.value?.trim() || 'COOL member';
  const userId = crypto.getRandomValues(new Uint8Array(16));
  const challenge = crypto.getRandomValues(new Uint8Array(32));
  const credential = await navigator.credentials.create({
    publicKey: {
      rp: { name: 'COOL PWA', id: window.location.hostname },
      user: {
        id: userId,
        name: `${label.toLowerCase().replace(/\s+/g, '.')}@cool.app`,
        displayName: label,
      },
      challenge,
      pubKeyCredParams: [
        { type: 'public-key', alg: -7 },
        { type: 'public-key', alg: -257 },
      ],
      timeout: 60_000,
      authenticatorSelection: {
        residentKey: 'preferred',
        userVerification: 'preferred',
      },
      attestation: 'none',
    },
  });

  if (!credential) {
    throw new Error('Browser did not return a credential.');
  }

  const record = {
    id: credential.id,
    rawId: bufferToBase64url(credential.rawId),
    label,
    registeredAt: new Date().toISOString(),
  };
  await dbPutRecord('passkeys', record);
  return record;
}

async function verifyPasskey() {
  const credentials = await dbGetAll('passkeys');
  if (!credentials.length) {
    throw new Error('No passkey is registered yet.');
  }

  const challenge = crypto.getRandomValues(new Uint8Array(32));
  const assertion = await navigator.credentials.get({
    publicKey: {
      challenge,
      userVerification: 'preferred',
      allowCredentials: credentials.map((entry) => ({
        type: 'public-key',
        id: base64urlToBuffer(entry.rawId),
      })),
      timeout: 60_000,
    },
  });

  if (!assertion) {
    throw new Error('Verification was cancelled.');
  }

  const match = credentials.find((entry) => entry.id === assertion.id) ?? credentials[0];
  return match;
}

function initializeShareTargetView() {
  if (!window.location.pathname.startsWith('/share')) {
    return;
  }

  const params = new URLSearchParams(window.location.search);
  const title = params.get('title') ?? '';
  const text = params.get('text') ?? '';
  const url = params.get('url') ?? '';

  if (!title && !text && !url) {
    return;
  }

  const entry = {
    id: crypto.randomUUID(),
    title,
    text,
    url,
    createdAt: new Date().toISOString(),
  };
  void dbPutRecord('shares', entry);
  void trackEvent('share_target_received', { has_url: Boolean(url), has_text: Boolean(text) });

  const container = document.querySelector('[data-share-target]');
  if (container) {
    container.innerHTML = `
      <div class="list-item">
        <div class="list-item-header">
          <strong>${escapeHtml(title || 'Shared content')}</strong>
          <span class="status-pill online">Saved</span>
        </div>
        <p>${escapeHtml(text || 'No text shared.')}</p>
        ${url ? `<a class="action-link" href="${escapeAttribute(url)}">${escapeHtml(url)}</a>` : ''}
      </div>
    `;
  }
}

function initializeQuickActions() {
  document.querySelectorAll('[data-success-moment]').forEach((button) => {
    button.addEventListener('click', async () => {
      const reason = button.getAttribute('data-success-moment') ?? 'cta_click';
      await recordSuccessMoment(reason);
      showToast('Progress saved. COOL is ready to install.');
      updateShellState();
    });
  });
}

function initializeScrollPersistence() {
  const storageKey = `${SETTINGS.scrollPrefix}${window.location.pathname}`;
  const saved = Number(sessionStorage.getItem(storageKey) ?? 0);
  if (saved > 0) {
    window.scrollTo(0, saved);
  }

  window.addEventListener('beforeunload', () => {
    sessionStorage.setItem(storageKey, String(window.scrollY));
  });
}

function initializeRouteNavigation() {
  document.querySelectorAll('[data-route-link]').forEach((link) => {
    const href = new URL(link.href).pathname;
    if (href === window.location.pathname) {
      link.setAttribute('aria-current', 'page');
    }
  });
}

async function populatePageData() {
  const route = document.body.dataset.route ?? 'index';
  const dataUrl = ROUTE_DATA[route];
  if (!dataUrl) {
    return;
  }

  try {
    const response = await fetch(dataUrl, { cache: 'no-store' });
    const data = await response.json();
    bindMetricValues(data);
    bindCollection('activity-feed', data.activity ?? []);
    bindCollection('queue-feed', data.queue ?? []);
    bindCollection('notification-feed', data.notifications ?? []);
  } catch (error) {
    console.error('Route data load failed.', error);
    showToast('Offline data is being used.');
  }
}

function bindMetricValues(data) {
  document.querySelectorAll('[data-metric]').forEach((node) => {
    const key = node.getAttribute('data-metric');
    if (!key) {
      return;
    }
    const value = key.split('.').reduce((current, part) => current?.[part], data);
    if (value !== undefined && value !== null) {
      node.textContent = String(value);
    }
  });
}

function bindCollection(id, items) {
  const list = document.getElementById(id);
  if (!list || !Array.isArray(items) || items.length === 0) {
    return;
  }

  list.innerHTML = items.map((item) => `
    <li class="list-item">
      <div class="list-item-header">
        <strong>${escapeHtml(item.title ?? 'Untitled')}</strong>
        <span class="status-pill ${escapeAttribute(item.tone ?? 'online')}">${escapeHtml(item.status ?? 'Ready')}</span>
      </div>
      <p>${escapeHtml(item.description ?? '')}</p>
      ${item.meta ? `<span class="meta mono">${escapeHtml(item.meta)}</span>` : ''}
    </li>
  `).join('');
}

async function refreshDerivedUi() {
  const visits = Number(await dbGet('settings', SETTINGS.visits) ?? 0);
  const successMoments = Number(await dbGet('settings', SETTINGS.successMoments) ?? 0);
  const queued = (await dbGetAll('queue')).filter((entry) => entry.status === 'pending').length;
  const unreadNotifications = (await dbGetAll('notifications')).filter((entry) => entry.unread).length;
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

  await updateBadge(unreadNotifications);
  updateShellState();
}

async function recordSuccessMoment(reason) {
  const next = Number(await dbGet('settings', SETTINGS.successMoments) ?? 0) + 1;
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

  const analyticsEndpoint = document.querySelector('meta[name="analytics-endpoint"]')?.content?.trim();
  if (analyticsEndpoint && navigator.sendBeacon) {
    navigator.sendBeacon(analyticsEndpoint, JSON.stringify(payload));
  }
}

function updateShellState() {
  const installBanner = document.querySelector('[data-install-banner]');
  const updateBanner = document.querySelector('[data-update-banner]');
  const dismissedAt = readDismissalState();

  const installAvailable = state.installEligible &&
    !state.isStandalone &&
    !dismissedAt &&
    (Boolean(state.deferredPrompt) || state.isIosSafari);

  if (installBanner) {
    installBanner.hidden = !installAvailable || state.updateReady;
  }

  if (installAvailable && !state.installImpressionTracked) {
    state.installImpressionTracked = true;
    void markInstallImpression();
  }

  if (updateBanner) {
    updateBanner.hidden = !state.updateReady;
  }

  document.querySelectorAll('[data-install-cta-label]').forEach((node) => {
    node.textContent = state.deferredPrompt ? 'Install COOL' : 'How to install';
  });

  document.querySelectorAll('[data-install-platform]').forEach((node) => {
    node.textContent = state.deferredPrompt ? 'Chromium install prompt' : 'Safari Add to Home Screen';
  });
}

function openIosInstallSheet() {
  const dialog = document.querySelector('[data-ios-sheet]');
  if (dialog instanceof HTMLDialogElement) {
    dialog.showModal();
  }
}

function readDismissalState() {
  const dismissedAt = window.localStorage.getItem(SETTINGS.installDismissedAt);
  if (!dismissedAt) {
    return null;
  }

  const age = Date.now() - new Date(dismissedAt).getTime();
  const dismissalWindowMs = 7 * 24 * 60 * 60 * 1000;
  if (Number.isNaN(age) || age > dismissalWindowMs) {
    window.localStorage.removeItem(SETTINGS.installDismissedAt);
    return null;
  }
  return dismissedAt;
}

async function markInstallDismissed() {
  const timestamp = new Date().toISOString();
  await dbSet('settings', SETTINGS.installDismissedAt, timestamp);
  window.localStorage.setItem(SETTINGS.installDismissedAt, timestamp);
}

async function markInstallImpression() {
  const impressionAt = new Date().toISOString();
  await dbSet('settings', SETTINGS.installImpressionAt, impressionAt);
  await trackEvent('install_prompt_impression', {
    prompt_type: state.deferredPrompt ? 'chromium' : 'ios_guided',
  });
}

function bufferToBase64url(buffer) {
  return btoa(String.fromCharCode(...new Uint8Array(buffer)))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '');
}

function base64urlToBuffer(value) {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  const padded = normalized.padEnd(
    normalized.length + ((4 - normalized.length % 4) % 4),
    '=',
  );
  const binary = atob(padded);
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

function observeWebVitals() {
  let clsValue = 0;
  let largestLcp = 0;
  let maxInp = 0;

  if ('PerformanceObserver' in window) {
    const clsObserver = new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) {
        if (!entry.hadRecentInput) {
          clsValue += entry.value;
        }
      }
    });
    clsObserver.observe({ type: 'layout-shift', buffered: true });

    const lcpObserver = new PerformanceObserver((list) => {
      const entries = list.getEntries();
      const last = entries.at(-1);
      if (last) {
        largestLcp = last.startTime;
      }
    });
    lcpObserver.observe({ type: 'largest-contentful-paint', buffered: true });

    const inpObserver = new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) {
        maxInp = Math.max(maxInp, entry.duration);
      }
    });
    inpObserver.observe({ type: 'event', buffered: true, durationThreshold: 16 });
  }

  window.addEventListener('visibilitychange', () => {
    if (document.visibilityState !== 'hidden') {
      return;
    }

    const navEntry = performance.getEntriesByType('navigation')[0];
    const paintEntries = performance.getEntriesByType('paint');
    const fcp = paintEntries.find((entry) => entry.name === 'first-contentful-paint')?.startTime ?? 0;
    const ttfb = navEntry?.responseStart ?? 0;

    void trackEvent('web_vitals_reported', {
      lcp: Math.round(largestLcp),
      cls: Number(clsValue.toFixed(3)),
      inp: Math.round(maxInp),
      fcp: Math.round(fcp),
      ttfb: Math.round(ttfb),
    });
  }, { once: true });
}

function showToast(message) {
  const stack = document.querySelector('[data-toast-stack]');
  if (!stack) {
    return;
  }

  const toast = document.createElement('div');
  toast.className = 'toast';
  toast.textContent = message;
  stack.appendChild(toast);

  window.setTimeout(() => {
    toast.remove();
  }, 4200);
}

function escapeHtml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function escapeAttribute(value) {
  return escapeHtml(value).replaceAll('`', '&#096;');
}
