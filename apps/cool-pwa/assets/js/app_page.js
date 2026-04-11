export function initializeShareButtons({
  recordSuccessMoment,
  trackEvent,
  showToast,
}) {
  document.querySelectorAll('[data-share-button]').forEach((button) => {
    button.addEventListener('click', async () => {
      const title = button.getAttribute('data-share-title') ?? document.title;
      const text = button.getAttribute('data-share-text') ?? '';
      const url = new URL(
        button.getAttribute('data-share-url') ?? window.location.href,
        window.location.origin,
      ).toString();

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

export function initializeShareTargetView({ dbPutRecord, trackEvent }) {
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
  void trackEvent('share_target_received', {
    has_url: Boolean(url),
    has_text: Boolean(text),
  });

  const container = document.querySelector('[data-share-target]');
  if (container) {
    container.innerHTML = `
      <div class="list-item">
        <div class="list-item-header">
          <strong>${escapeHtml(title || 'Shared content')}</strong>
          <span class="status-pill online">Saved</span>
        </div>
        <p>${escapeHtml(text || 'No text shared.')}</p>
        ${
      url
        ? `<a class="action-link" href="${escapeAttribute(url)}">${escapeHtml(url)}</a>`
        : ''
    }
      </div>
    `;
  }
}

export function initializeQuickActions({
  recordSuccessMoment,
  showToast,
  updateShellState,
}) {
  document.querySelectorAll('[data-success-moment]').forEach((button) => {
    button.addEventListener('click', async () => {
      const reason = button.getAttribute('data-success-moment') ?? 'cta_click';
      await recordSuccessMoment(reason);
      showToast('Progress saved. COOL is ready to install.');
      updateShellState();
    });
  });
}

export function initializeScrollPersistence(settings) {
  const storageKey = `${settings.scrollPrefix}${window.location.pathname}`;
  const saved = Number(sessionStorage.getItem(storageKey) ?? 0);
  if (saved > 0) {
    window.scrollTo(0, saved);
  }

  window.addEventListener('beforeunload', () => {
    sessionStorage.setItem(storageKey, String(window.scrollY));
  });
}

export function initializeRouteNavigation() {
  document.querySelectorAll('[data-route-link]').forEach((link) => {
    const href = new URL(link.href).pathname;
    if (href === window.location.pathname) {
      link.setAttribute('aria-current', 'page');
    }
  });
}

export async function fetchStaticRouteData({ routeData, route = document.body.dataset.route ?? 'index' }) {
  const dataUrl = routeData[route];
  if (!dataUrl) {
    return null;
  }

  const response = await fetch(dataUrl, { cache: 'no-store' });
  return await response.json();
}

export function applyPageData(data) {
  if (!data || typeof data !== 'object') {
    return;
  }

  bindMetricValues(data);
  bindCollection('activity-feed', data.activity ?? []);
  bindCollection('queue-feed', data.queue ?? []);
  bindCollection('notification-feed', data.notifications ?? []);
}

export async function populatePageData({ routeData, route, showToast }) {
  try {
    const data = await fetchStaticRouteData({ routeData, route });
    applyPageData(data);
    return data;
  } catch (error) {
    console.error('Route data load failed.', error);
    showToast('Offline data is being used.');
    return null;
  }
}

export function observeWebVitals(trackEvent) {
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
    inpObserver.observe({
      type: 'event',
      buffered: true,
      durationThreshold: 16,
    });
  }

  window.addEventListener(
    'visibilitychange',
    () => {
      if (document.visibilityState !== 'hidden') {
        return;
      }

      const navEntry = performance.getEntriesByType('navigation')[0];
      const paintEntries = performance.getEntriesByType('paint');
      const fcp =
        paintEntries.find(
          (entry) => entry.name === 'first-contentful-paint',
        )?.startTime ?? 0;
      const ttfb = navEntry?.responseStart ?? 0;

      void trackEvent('web_vitals_reported', {
        lcp: Math.round(largestLcp),
        cls: Number(clsValue.toFixed(3)),
        inp: Math.round(maxInp),
        fcp: Math.round(fcp),
        ttfb: Math.round(ttfb),
      });
    },
    { once: true },
  );
}

export function showToast(message) {
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

function bindMetricValues(data) {
  document.querySelectorAll('[data-metric]').forEach((node) => {
    const key = node.getAttribute('data-metric');
    if (!key) {
      return;
    }
    const value = key
      .split('.')
      .reduce((current, part) => current?.[part], data);
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

  list.innerHTML = items
    .map(
      (item) => `
    <li class="list-item">
      <div class="list-item-header">
        <strong>${escapeHtml(item.title ?? 'Untitled')}</strong>
        <span class="status-pill ${escapeAttribute(item.tone ?? 'online')}">${escapeHtml(item.status ?? 'Ready')}</span>
      </div>
      <p>${escapeHtml(item.description ?? '')}</p>
      ${item.meta ? `<span class="meta mono">${escapeHtml(item.meta)}</span>` : ''}
    </li>
  `,
    )
    .join('');
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
