(() => {
  const state = {
    canPromptInstall: false,
    isStandalone: false,
    isIosSafari: false,
    updateAvailable: false,
    hasServiceWorker: 'serviceWorker' in navigator,
    registrationReady: false,
    isInstalled: false,
  };

  let deferredPrompt = null;
  let registration = null;

  const isiOSDevice = () => {
    const platform = navigator.platform || '';
    const userAgent = navigator.userAgent || '';
    const touchMac = platform === 'MacIntel' && navigator.maxTouchPoints > 1;
    return /iPad|iPhone|iPod/.test(userAgent) || touchMac;
  };

  const isSafari = () => {
    const userAgent = navigator.userAgent || '';
    return /Safari/i.test(userAgent) && !/CriOS|FxiOS|EdgiOS|Chrome|Android/i.test(userAgent);
  };

  const isStandalone = () => {
    const displayModeStandalone =
      typeof window.matchMedia === 'function' &&
      window.matchMedia('(display-mode: standalone)').matches;
    const navigatorStandalone = navigator.standalone === true;
    return displayModeStandalone || navigatorStandalone;
  };

  const snapshot = () => {
    state.canPromptInstall = deferredPrompt != null;
    state.isStandalone = isStandalone();
    state.isIosSafari = isiOSDevice() && isSafari();
    return { ...state };
  };

  const emit = () => {
    window.dispatchEvent(
      new CustomEvent('cool-pwa-statechange', { detail: snapshot() }),
    );
  };

  window.coolPwa = {
    getState() {
      return snapshot();
    },
    async promptInstall() {
      if (!deferredPrompt) {
        return { outcome: 'unavailable' };
      }

      const promptEvent = deferredPrompt;
      deferredPrompt = null;
      emit();

      await promptEvent.prompt();
      const choice = await promptEvent.userChoice;
      if (choice?.outcome !== 'accepted') {
        deferredPrompt = promptEvent;
      }
      emit();

      return { outcome: choice?.outcome || 'dismissed' };
    },
    async activateUpdate() {
      if (!registration?.waiting) {
        return false;
      }
      registration.waiting.postMessage({ type: 'SKIP_WAITING' });
      return true;
    },
    async downloadOffline() {
      if (!navigator.serviceWorker?.controller) {
        return false;
      }
      navigator.serviceWorker.controller.postMessage('downloadOffline');
      return true;
    },
  };

  window.addEventListener('beforeinstallprompt', (event) => {
    event.preventDefault();
    deferredPrompt = event;
    emit();
  });

  window.addEventListener('appinstalled', () => {
    deferredPrompt = null;
    state.isInstalled = true;
    emit();
  });

  if (typeof window.matchMedia === 'function') {
    const displayMode = window.matchMedia('(display-mode: standalone)');
    if (typeof displayMode.addEventListener === 'function') {
      displayMode.addEventListener('change', emit);
    } else if (typeof displayMode.addListener === 'function') {
      displayMode.addListener(emit);
    }
  }

  const watchRegistration = (swRegistration) => {
    registration = swRegistration;
    state.registrationReady = true;
    state.updateAvailable = Boolean(swRegistration.waiting);
    emit();

    swRegistration.addEventListener('updatefound', () => {
      const installing = swRegistration.installing;
      if (!installing) {
        return;
      }
      installing.addEventListener('statechange', () => {
        if (
          installing.state === 'installed' &&
          navigator.serviceWorker.controller
        ) {
          state.updateAvailable = true;
          emit();
        }
      });
    });
  };

  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.ready
      .then((swRegistration) => {
        watchRegistration(swRegistration);
      })
      .catch(() => {
        emit();
      });

    navigator.serviceWorker.addEventListener('controllerchange', () => {
      state.updateAvailable = false;
      emit();
      window.location.reload();
    });
  }

  if (document.readyState === 'complete') {
    emit();
  } else {
    window.addEventListener('load', emit, { once: true });
  }
})();
