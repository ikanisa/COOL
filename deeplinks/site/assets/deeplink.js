(function () {
  var STORE_LINKS = window.COOL_STORE_LINKS || {};
  var PLAY_STORE_URL =
    STORE_LINKS.playStoreUrl ||
    "https://play.google.com/store/apps/details?id=app.cool.mobile";
  var IOS_DOWNLOAD_URL =
    STORE_LINKS.appStoreUrl ||
    STORE_LINKS.iosFallbackUrl ||
    "https://cool.app/download-ios/";
  var path = window.location.pathname || "/";
  var query = window.location.search || "";
  var hash = window.location.hash || "";
  var route = path.replace(/^\/+/, "");
  var deepLink = "cool://" + route + query + hash;

  var isAndroid = /android/i.test(navigator.userAgent);
  var isIos = /iphone|ipad|ipod/i.test(navigator.userAgent);
  var title = document.getElementById("title");
  var description = document.getElementById("description");
  var pathEl = document.getElementById("path");
  var openApp = document.getElementById("open-app");
  var storeLink = document.getElementById("store-link");
  var appOpenAttempted = false;
  var pageHidden = false;

  if (pathEl) {
    pathEl.textContent = path + query + hash;
  }

  if (title) {
    if (path.indexOf("/basket") === 0) {
      title.textContent = "Open Basket in Cool";
    } else if (path.indexOf("/invite/") === 0) {
      title.textContent = "Open Group Invite in Cool";
    }
  }

  if (openApp) {
    openApp.href = deepLink;
  }

  var storeUrl = PLAY_STORE_URL;
  if (isIos) {
    storeUrl = IOS_DOWNLOAD_URL;
  }

  if (storeLink) {
    storeLink.href = storeUrl;
    storeLink.textContent = isIos ? "Open iPhone Install Info" : "Open Google Play";
  }

  if (description && !(isAndroid || isIos)) {
    description.textContent =
      "Open this link on your phone to continue in the app, or install Cool from the store.";
    return;
  }

  function markHidden() {
    pageHidden = true;
  }

  document.addEventListener("visibilitychange", function () {
    if (document.visibilityState === "hidden") {
      markHidden();
    }
  });
  window.addEventListener("pagehide", markHidden);
  window.addEventListener("blur", markHidden);

  setTimeout(function () {
    appOpenAttempted = true;
    window.location.href = deepLink;
  }, 60);

  setTimeout(function () {
    if (!appOpenAttempted || pageHidden) {
      return;
    }
    window.location.href = storeUrl;
  }, 1800);
})();
