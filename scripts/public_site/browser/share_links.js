  const shareLanding = document.querySelector('[data-share-landing]');
  const shareKind = shareLanding?.dataset.shareLanding;
  if (shareKind === 'group' || shareKind === 'app') {
    const userAgent = navigator.userAgent || '';
    const platform = navigator.userAgentData?.platform || navigator.platform || '';
    const isIPadOS = platform === 'MacIntel' && navigator.maxTouchPoints > 1;
    const isIOS = /iPad|iPhone|iPod/i.test(userAgent) || isIPadOS;
    const isAndroid = /Android/i.test(userAgent);
    const storeUrl = isIOS ? publicSite.appleAppStoreUrl : publicSite.googlePlayUrl;
    const storeLabel = isIOS ? 'Get on the App Store' : isAndroid ? 'Get it on Google Play' : 'Get Collect';
    const storeName = isIOS ? 'Get Collect on the Apple App Store' :
      isAndroid ? 'Get Collect on Google Play' : 'Get Collect for this device';

    document.querySelectorAll('[data-collect-store-link]').forEach((link) => {
      link.href = storeUrl;
      link.textContent = storeLabel;
      link.setAttribute('aria-label', storeName);
    });

    if (shareKind === 'group') bindGroupShareLinks(publicSite.publicOrigin);
    else bindAppShareLinks(storeUrl, isIOS || isAndroid, publicSite.appleAppStoreId);
  }
