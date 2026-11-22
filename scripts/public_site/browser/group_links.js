  const groupQueryPaths = new Set(['/c', '/c/', '/c/index.html', '/group-link', '/group-link/', '/group-link/index.html']);
  const shareGroupCodePattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

  function groupCodeForAddress(address, expectedOrigin) {
    if (address.protocol !== 'https:' || address.origin !== expectedOrigin ||
        address.username || address.password || address.href.includes('#')) {
      return null;
    }

    const params = [...address.searchParams.entries()].map(([key, value]) => [key.toLowerCase(), value]);
    if (params.some(([key]) => key === 'code' || key === 'group')) return null;
    const slugs = params.filter(([key]) => key === 'slug');
    let candidate;
    if (groupQueryPaths.has(address.pathname.toLowerCase())) {
      if (slugs.length !== 1) return null;
      candidate = slugs[0][1];
    } else {
      const parts = address.pathname.split('/');
      if (parts.length !== 3 || parts[0] !== '' || parts[1].toLowerCase() !== 'c' || slugs.length) {
        return null;
      }
      try {
        candidate = decodeURIComponent(parts[2]);
      } catch (_) {
        return null;
      }
    }

    const slug = candidate.toLowerCase();
    // Match the version and variant accepted by the native join validator.
    return candidate === candidate.trim() && slug.length === 36 && shareGroupCodePattern.test(slug)
      ? slug
      : null;
  }

  function bindGroupShareLinks(expectedOrigin) {
    const openLink = document.querySelector('[data-collect-open-link]');
    const copyButton = document.querySelector('[data-collect-copy-link]');
    const status = document.querySelector('[data-share-status]');

    // An earlier template may still carry its native destination in an href.
    if (!openLink || openLink.tagName !== 'BUTTON') {
      if (openLink) {
        openLink.removeAttribute('href');
        openLink.setAttribute('aria-disabled', 'true');
        openLink.addEventListener('click', (event) => event.preventDefault());
      }
      if (copyButton) copyButton.disabled = true;
      if (status) status.textContent = 'Reopen the original link after installing Collect.';
      return;
    }

    const address = new URL(window.location.href);
    const slug = groupCodeForAddress(address, expectedOrigin);
    if (!slug) {
      if (status) status.textContent = 'This group link cannot be used with this version of Collect. Ask the sender for a new link.';
      return;
    }

    const stillCurrent = () => {
      if (window.location.href === address.href) return true;
      openLink.disabled = true;
      if (copyButton) copyButton.disabled = true;
      if (status) status.textContent = 'The link changed. Open the current link again.';
      return false;
    };
    openLink.disabled = false;
    openLink.addEventListener('click', () => {
      if (stillCurrent()) window.location.assign('collect://group/' + encodeURIComponent(slug));
    });
    if (!copyButton) return;

    copyButton.disabled = false;
    copyButton.addEventListener('click', async () => {
      if (!stillCurrent()) return;
      try {
        const canonical = new URL('/c/' + encodeURIComponent(slug), address.origin).href;
        await navigator.clipboard.writeText(canonical);
        if (window.location.href === address.href && status) status.textContent = 'Link copied.';
      } catch (_) {
        if (window.location.href === address.href && status) {
          status.textContent = 'Return to the original message to open the link again.';
        }
      }
    });
  }
