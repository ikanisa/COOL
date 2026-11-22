"use strict";

const path = require("node:path");
const { observePageErrors, readKeyboardFocus, hasVisibleKeyboardFocus, failedChecks } = require("./rendered_page_evidence.cjs");

async function auditGroupShareScenario(page, scenario, viewport, { shareHtml, publicOrigin, baseUrl, shareId, screenshotDir }) {
  const { consoleMessages, pageErrors } = observePageErrors(page);
  // Use the bundle's actual URL policy without contacting its public host.
  // Every response for the virtual origin comes from this exact local build.
  const url = new URL(scenario.route, publicOrigin).href;
  await page.addInitScript(() => {
    window.collectQaCopiedLinks = [];
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: {writeText: async value => { window.collectQaCopiedLinks.push(value); }},
    });
  });
  await page.route("**/*", async route => {
    const request = route.request();
    const target = new URL(request.url());
    if (target.origin !== publicOrigin) return route.fallback();
    if (request.method() !== "GET") return route.abort("blockedbyclient");
    if (request.resourceType() === "document") {
      if (target.href !== url) return route.abort("blockedbyclient");
      return route.fulfill({status: 200, contentType: "text/html", body: shareHtml});
    }
    const local = new URL(baseUrl);
    local.pathname = target.pathname;
    local.search = target.search;
    const response = await fetch(local, {redirect: "error"});
    return route.fulfill({
      status: response.status,
      contentType: response.headers.get("content-type") || "application/octet-stream",
      body: Buffer.from(await response.arrayBuffer()),
    });
  });

  const response = await page.goto(url, { waitUntil: "networkidle", timeout: 30_000 });
  await page.locator("h1").waitFor({ state: "visible", timeout: 10_000 });

  const keyboardFocus = await readKeyboardFocus(page, 7);

  const metrics = await page.evaluate(expectedId => {
    const openLink = document.querySelector("[data-collect-open-link]");
    // Measure the rendered hero action; the menu/header duplicate may be hidden.
    const installLink = document.querySelector(".hero-actions [data-collect-store-link]");
    const appStoreLink = document.querySelector('a[href="https://apps.apple.com/app/id6783960331"]');
    const playStoreLink = document.querySelector('a[href="https://play.google.com/store/apps/details?id=app.cool.mobile"]');
    const copyButton = document.querySelector("[data-collect-copy-link]");
    const status = document.querySelector("[data-share-status]");
    const bodyText = document.body.innerText;
    return {
      openHref: openLink?.getAttribute("href") || null,
      openIsButton: openLink instanceof HTMLButtonElement,
      openDisabled: openLink?.disabled,
      copyDisabled: copyButton?.disabled,
      installHref: installLink?.getAttribute("href") || "",
      hasExactStoreOptions: Boolean(appStoreLink && playStoreLink),
      visibleShareIdentifier: bodyText.toLowerCase().includes(expectedId),
      statusText: status?.textContent.trim() || "",
      hasValidityCopy: bodyText.includes("Use the account you intend to join with, and choose Join in the app."),
      noFalseJoinConfirmation: !/invitation (is|has been) valid|you (have )?joined/i.test(bodyText),
      actionRects: [openLink, installLink, copyButton].map((element) => {
        if (!element) return null;
        const rect = element.getBoundingClientRect();
        const style = getComputedStyle(element);
        return {
          text: element.textContent.trim(),
          width: Math.round(rect.width),
          height: Math.round(rect.height),
          display: style.display,
          visibility: style.visibility,
          opacity: style.opacity,
        };
      }),
      hasCopyAction: Boolean(copyButton),
      noHorizontalOverflow: Math.max(document.body.scrollWidth, document.documentElement.scrollWidth) <= window.innerWidth + 1,
      canonicalPath: document.querySelector("[data-share-canonical]")?.getAttribute("href") || "",
    };
  }, shareId);

  const copy = page.locator("[data-collect-copy-link]");
  if (scenario.canOpen) await copy.click({timeout: 3000});
  const copiedLinks = await page.evaluate(() => window.collectQaCopiedLinks);
  const expectedCopied = new URL(`/c/${shareId}`, publicOrigin).href;
  const checks = {
    rewriteServes200: Boolean(response && response.status() === 200),
    noConsoleErrors: consoleMessages.length === 0 && pageErrors.length === 0,
    noHorizontalOverflow: metrics.noHorizontalOverflow,
    joinRequiresAppConfirmation: metrics.hasValidityCopy && metrics.noFalseJoinConfirmation,
    invitationPrivateInPage: !metrics.visibleShareIdentifier && metrics.canonicalPath === new URL("/c/", publicOrigin).href,
    explicitNativeAction: metrics.openIsButton && metrics.openHref === null && metrics.openDisabled === !scenario.canOpen,
    copyAction: metrics.copyDisabled === !scenario.canOpen && (scenario.canOpen
      ? copiedLinks.length === 1 && copiedLinks[0] === expectedCopied
      : copiedLinks.length === 0),
    noAppFallback: metrics.installHref.includes("play.google.com") && metrics.hasExactStoreOptions && metrics.hasCopyAction &&
      metrics.actionRects.slice(1).every((rect) => rect && rect.width > 0 && rect.height >= 44 &&
        rect.display !== "none" && rect.visibility === "visible" && Number.parseFloat(rect.opacity) > 0),
    nativeActionVisible: Boolean(metrics.actionRects[0] && metrics.actionRects[0].width > 0 &&
      metrics.actionRects[0].height >= 44 && metrics.actionRects[0].display !== "none" &&
      metrics.actionRects[0].visibility === "visible" && Number.parseFloat(metrics.actionRects[0].opacity) > 0),
    invalidRecoveryMessage: scenario.canOpen || metrics.statusText ===
      "This group link cannot be used with this version of Collect. Ask the sender for a new link.",
    keyboardTraversal: keyboardFocus.length >= 5 && keyboardFocus[0]?.text === "Skip to content",
    visibleKeyboardFocus: hasVisibleKeyboardFocus(keyboardFocus),
  };

  await page.evaluate(() => {
    if (document.activeElement && typeof document.activeElement.blur === "function") {
      document.activeElement.blur();
    }
    window.scrollTo(0, 0);
  });
  await page.waitForTimeout(100);
  const screenshot = path.join(screenshotDir, `group_${scenario.name}_${viewport.name}.png`);
  await page.screenshot({ path: screenshot, fullPage: false });
  return {
    scenario: scenario.name,
    route: scenario.route,
    viewport: viewport.name,
    url,
    screenshot,
    checks,
    failures: failedChecks(checks),
    metrics,
    keyboardFocus,
    consoleMessages,
    pageErrors,
  };
}

module.exports = { auditGroupShareScenario };
