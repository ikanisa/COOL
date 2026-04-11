export function initializeInstallPromptCapture({
  state,
  settings,
  dbSet,
  trackEvent,
  showToast,
  updateShellState,
}) {
  window.addEventListener('beforeinstallprompt', async (event) => {
    event.preventDefault();
    state.deferredPrompt = event;
    await trackEvent('install_prompt_ready');
    updateShellState();
  });

  window.addEventListener('appinstalled', async () => {
    state.deferredPrompt = null;
    state.installEligible = false;
    await dbSet('settings', settings.installDismissedAt, null);
    window.localStorage.removeItem(settings.installDismissedAt);
    await trackEvent('install_success');
    showToast('COOL Admin is installed with cached shell support.');
    updateShellState();
  });
}

export function initializeBannerActions({
  state,
  settings,
  dbSet,
  trackEvent,
  showToast,
  updateShellState,
}) {
  document.querySelectorAll('[data-install-action]').forEach((button) => {
    button.addEventListener('click', async () => {
      if (state.deferredPrompt) {
        await state.deferredPrompt.prompt();
        const choice = await state.deferredPrompt.userChoice;
        await trackEvent('install_prompt_result', { outcome: choice.outcome });
        if (choice.outcome !== 'accepted') {
          await markInstallDismissed({ settings, dbSet });
        }
        state.deferredPrompt = null;
        updateShellState();
        return;
      }

      openIosInstallSheet();
      await trackEvent('install_instruction_opened', {
        platform: 'ios_safari',
      });
    });
  });

  document.querySelectorAll('[data-install-dismiss]').forEach((button) => {
    button.addEventListener('click', async () => {
      await markInstallDismissed({ settings, dbSet });
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
      showToast('Cached shell requested. Live admin data still needs connectivity.');
    });
  });
}

export function updateShellState({ state, settings, dbSet, trackEvent }) {
  const installBanner = document.querySelector('[data-install-banner]');
  const updateBanner = document.querySelector('[data-update-banner]');
  const dismissedAt = readDismissalState(settings);

  const installAvailable =
    state.installEligible &&
    !state.isStandalone &&
    !dismissedAt &&
    (Boolean(state.deferredPrompt) || state.isIosSafari);

  if (installBanner) {
    installBanner.hidden = !installAvailable || state.updateReady;
  }

  if (installAvailable && !state.installImpressionTracked) {
    state.installImpressionTracked = true;
    void markInstallImpression({ state, settings, dbSet, trackEvent });
  }

  if (updateBanner) {
    updateBanner.hidden = !state.updateReady;
  }

  document.querySelectorAll('[data-install-cta-label]').forEach((node) => {
    node.textContent = state.deferredPrompt ? 'Install COOL Admin' : 'How to install';
  });

  document.querySelectorAll('[data-install-platform]').forEach((node) => {
    node.textContent = state.deferredPrompt
      ? 'Chromium install prompt'
      : 'Safari Add to Home Screen';
  });
}

function openIosInstallSheet() {
  const dialog = document.querySelector('[data-ios-sheet]');
  if (dialog instanceof HTMLDialogElement) {
    dialog.showModal();
  }
}

function readDismissalState(settings) {
  const dismissedAt = window.localStorage.getItem(settings.installDismissedAt);
  if (!dismissedAt) {
    return null;
  }

  const age = Date.now() - new Date(dismissedAt).getTime();
  const dismissalWindowMs = 7 * 24 * 60 * 60 * 1000;
  if (Number.isNaN(age) || age > dismissalWindowMs) {
    window.localStorage.removeItem(settings.installDismissedAt);
    return null;
  }
  return dismissedAt;
}

async function markInstallDismissed({ settings, dbSet }) {
  const timestamp = new Date().toISOString();
  await dbSet('settings', settings.installDismissedAt, timestamp);
  window.localStorage.setItem(settings.installDismissedAt, timestamp);
}

async function markInstallImpression({ state, settings, dbSet, trackEvent }) {
  const impressionAt = new Date().toISOString();
  await dbSet('settings', settings.installImpressionAt, impressionAt);
  await trackEvent('install_prompt_impression', {
    prompt_type: state.deferredPrompt ? 'chromium' : 'ios_guided',
  });
}
