  function bindAppShareLinks(storeUrl, mobile, appleAppStoreId) {
    const segments = window.location.pathname.split('/').filter(Boolean);
    const search = new URLSearchParams(window.location.search);
    const inviteId = segments.length === 2 && segments[0].toLowerCase() === 'invite'
      ? segments[1]
      : search.get('publicId');
    const safeInviteId = inviteId && /^[A-Za-z0-9_-]{1,64}$/.test(inviteId) ? inviteId : null;
    const openLink = document.querySelector('[data-collect-open-link]');
    const heading = document.querySelector('[data-share-heading]');
    const status = document.querySelector('[data-share-status]');
    const canonical = document.querySelector('[data-share-canonical]');
    const ogUrl = document.querySelector('[data-share-og-url]');
    const smartBanner = document.querySelector('[data-share-smart-banner]');
    const copyButton = document.querySelector('[data-collect-copy-link]');

    if (safeInviteId) {
      if (openLink) openLink.href = 'collect://invite/' + encodeURIComponent(safeInviteId);
      if (heading) heading.textContent = 'Join someone you know on Collect';
    } else if (openLink) {
      openLink.href = 'collect://app';
    }

    const exactPath = safeInviteId ? '/invite/' + encodeURIComponent(safeInviteId) : window.location.pathname;
    const exactUrl = window.location.origin + exactPath;
    if (canonical) canonical.href = exactUrl;
    if (ogUrl) ogUrl.content = exactUrl;
    if (smartBanner) smartBanner.content = 'app-id=' + appleAppStoreId + ', app-argument=' + exactUrl;

    if (openLink && mobile && openLink.hasAttribute('href')) {
      openLink.addEventListener('click', () => {
        const startedAt = Date.now();
        window.setTimeout(() => {
          const stillHere = document.visibilityState === 'visible' && Date.now() - startedAt < 3000;
          if (stillHere) window.location.assign(storeUrl);
        }, 1400);
      });
    }

    if (copyButton) {
      copyButton.addEventListener('click', async () => {
        try {
          await navigator.clipboard.writeText(exactUrl);
          if (status) status.textContent = 'Link copied.';
        } catch (_) {
          if (status) status.textContent = 'Copy the link from your browser address bar.';
        }
      });
    }
  }
