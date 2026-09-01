#!/usr/bin/env node
/* eslint-disable no-console */

const fs = require("fs");
const path = require("path");

const baseUrl = process.env.PUBLIC_WEBSITE_QA_URL || "http://127.0.0.1:4178/";
const buildDir = path.resolve(process.env.PUBLIC_BUILD_DIR || "build/public_web");
const outDir = path.resolve(process.env.PUBLIC_WEBSITE_QA_OUT || "output/public_website_route_rendered_qa");
const screenshotDir = path.join(outDir, "screenshots");
const playwrightCoreCandidates = [
  process.env.PLAYWRIGHT_CORE_PATH,
  "/Volumes/PRO-G40/Temp/caches/npm/_npx/705bc6b22212b352/node_modules/playwright-core/index.js",
  "/Library/Frameworks/Python.framework/Versions/3.13/lib/python3.13/site-packages/playwright/driver/package/index.js",
  "/Volumes/PRO-G40/X CPA/firmos/node_modules/playwright-core/index.js",
].filter(Boolean);
const chromeCandidates = [
  process.env.PUBLIC_WEBSITE_CHROME_PATH,
  path.join(process.env.HOME || "", "Library/Caches/ms-playwright/chromium-1223/chrome-mac-x64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing"),
  path.join(process.env.HOME || "", "Library/Caches/ms-playwright/chromium-1217/chrome-mac-x64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing"),
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
].filter(Boolean);
const viewports = [
  { name: "mobile_390x844", width: 390, height: 844, isMobile: true, allowedGridColumns: [2] },
  { name: "tablet_834x1194", width: 834, height: 1194, isMobile: false, allowedGridColumns: [2, 3] },
  { name: "desktop_1440x1000", width: 1440, height: 1000, isMobile: false, allowedGridColumns: [3] },
];
const legalRoutes = new Set(["/privacy/", "/terms/", "/account-deletion/", "/data-deletion/"]);
const groupShareScenarios = [
  {
    name: "valid_syntax",
    route: "/c/production-link-audit",
    nativeHref: "collect://group/production-link-audit",
    codeText: "Group link: production-link-audit",
    disabled: false,
  },
  {
    name: "expired_or_revoked_safe",
    route: "/c/expired-link-audit",
    nativeHref: "collect://group/expired-link-audit",
    codeText: "Group link: expired-link-audit",
    disabled: false,
  },
  {
    name: "invalid_syntax",
    route: "/c/INVALID%20CODE",
    nativeHref: null,
    codeText: "This group link is invalid.",
    disabled: true,
  },
  {
    name: "oversized_code",
    route: `/c/${"a".repeat(141)}`,
    nativeHref: null,
    codeText: "This group link is invalid.",
    disabled: true,
  },
];

function findExisting(candidates, label) {
  const found = candidates.find((candidate) => candidate && fs.existsSync(candidate));
  if (!found) throw new Error(`No usable ${label} found. Checked: ${candidates.join(", ")}`);
  return found;
}

async function loadPlaywright() {
  const modulePath = findExisting(playwrightCoreCandidates, "playwright-core module");
  const loaded = await import(`file://${modulePath}`);
  return { modulePath, playwright: loaded.default || loaded };
}

function sitemapRoutes() {
  const sitemapPath = path.join(buildDir, "sitemap.xml");
  const xml = fs.readFileSync(sitemapPath, "utf8");
  return [...xml.matchAll(/<loc>https:\/\/collect\.ikanisa\.com([^<]*)<\/loc>/g)]
    .map((match) => match[1] || "/")
    .filter((route) => route === "/" || route.endsWith("/"));
}

function routeName(route) {
  return route === "/" ? "home" : route.replace(/^\/|\/$/g, "").replace(/\//g, "_");
}

async function auditRoute(page, route, viewport) {
  const consoleMessages = [];
  const pageErrors = [];
  page.on("console", (message) => {
    const sourceUrl = message.location().url || "";
    if (["error", "warning"].includes(message.type()) && !/favicon/i.test(`${message.text()} ${sourceUrl}`)) {
      consoleMessages.push({ type: message.type(), text: message.text(), url: sourceUrl });
    }
  });
  page.on("pageerror", (error) => pageErrors.push(error.message));

  const url = new URL(route, baseUrl).toString();
  const response = await page.goto(url, { waitUntil: "domcontentloaded", timeout: 30_000 });
  await page.locator("h1").waitFor({ state: "visible", timeout: 10_000 });
  await page.waitForTimeout(150);

  const keyboardFocus = [];
  for (let index = 0; index < 8; index += 1) {
    await page.keyboard.press("Tab");
    keyboardFocus.push(await page.evaluate(() => {
      const active = document.activeElement;
      if (!active || active === document.body) return null;
      return {
        tag: active.tagName.toLowerCase(),
        text: (active.getAttribute("aria-label") || active.textContent || active.getAttribute("alt") || "").trim().replace(/\s+/g, " ").slice(0, 80),
        href: active.getAttribute("href") || "",
        focusVisible: active.matches(":focus-visible"),
        outlineStyle: getComputedStyle(active).outlineStyle,
        outlineWidth: getComputedStyle(active).outlineWidth,
        boxShadow: getComputedStyle(active).boxShadow,
      };
    }));
  }
  await page.evaluate(() => document.activeElement && document.activeElement.blur && document.activeElement.blur());

  let menuScreenshot = null;
  let mobileMenuOpen = true;
  if (viewport.isMobile) {
    await page.locator("[data-menu-button]").click({ timeout: 5_000 });
    await page.waitForTimeout(100);
    mobileMenuOpen = await page.locator("[data-site-nav]").evaluate((node) => node.classList.contains("open"));
    menuScreenshot = path.join(screenshotDir, `${routeName(route)}_${viewport.name}_menu.png`);
    await page.screenshot({ path: menuScreenshot, fullPage: false });
    await page.locator("[data-menu-button]").click({ timeout: 5_000 });
  }

  const screenshot = path.join(screenshotDir, `${routeName(route)}_${viewport.name}.png`);
  await page.screenshot({ path: screenshot, fullPage: false });

  const metrics = await page.evaluate((isLegalRoute) => {
    const rect = (selector) => {
      const element = document.querySelector(selector);
      if (!element) return null;
      const box = element.getBoundingClientRect();
      return {
        top: Math.round(box.top),
        bottom: Math.round(box.bottom),
        width: Math.round(box.width),
        height: Math.round(box.height),
      };
    };
    const accessibleName = (element) => (element.getAttribute("aria-label") || element.textContent || element.getAttribute("alt") || "").trim();
    const linkTextCount = (label) => [...document.querySelectorAll("a")]
      .filter((link) => link.textContent.trim() === label).length;
    const footerRects = [...document.querySelectorAll(".site-footer a")]
      .map((link) => {
        const box = link.getBoundingClientRect();
        return { width: Math.round(box.width), height: Math.round(box.height), text: link.textContent.trim() };
      });
    const bodyText = document.body.innerText;
    return {
      locale: document.documentElement.lang || "en",
      title: document.title,
      h1: document.querySelector("h1")?.innerText.trim() || "",
      bodyClass: document.body.className,
      bodyScrollWidth: document.body.scrollWidth,
      documentScrollWidth: document.documentElement.scrollWidth,
      viewportWidth: window.innerWidth,
      heroDevice: rect(".hero-device"),
      hero: rect(".hero"),
      legalLayoutPresent: Boolean(document.querySelector(".legal-layout .legal-main")),
      legalTocPresent: Boolean(document.querySelector(".legal-toc")),
      landmarkCounts: {
        header: document.querySelectorAll("header").length,
        main: document.querySelectorAll("main").length,
        footer: document.querySelectorAll("footer").length,
        nav: document.querySelectorAll("nav[aria-label]").length,
      },
      accessibleNames: {
        missingAlt: [...document.images].filter((image) => !image.hasAttribute("alt")).length,
        unnamedButtons: [...document.querySelectorAll("button")].filter((button) => !accessibleName(button)).length,
        unnamedLinks: [...document.querySelectorAll("a")].filter((link) => !accessibleName(link)).length,
      },
      ctaCounts: {
        getApp: linkTextCount("Get the App"),
        createGroupSaving: linkTextCount("Create Group Saving"),
        getInTouch: linkTextCount("Get in Touch"),
        rwGetApp: linkTextCount("Shyira porogaramu kuri telefoni"),
        rwCreateGroup: linkTextCount("Tangiza itsinda ryo kuzigama"),
        rwGetInTouch: linkTextCount("Tuvugishe"),
      },
      retiredSectionsAbsent: !bodyText.includes("Questions visitors ask") &&
        !bodyText.includes("thousands of users") &&
        !bodyText.includes("approved partner names"),
      disclaimerLabelsAbsent: !bodyText.includes("Currently available for Android through the official Collect by IKANISA Google Play listing") &&
        !bodyText.includes("iOS availability is not currently advertised") &&
        !bodyText.includes("This website is published in English only") &&
        !bodyText.includes("How Collect makes money") &&
        !bodyText.includes("Public evidence and market context") &&
        !bodyText.includes("Current public status") &&
        !bodyText.includes("No institution is presented here as a live Collect partner yet.") &&
        !bodyText.includes("No financial institution is presented on this website as a live Collect partner"),
      footerRects,
      compactCardGrids: [
        ".problem-list.compact",
        ".use-case-grid",
        ".craas-service-grid",
        ".infographic-grid",
        ".story-grid",
        ".content-grid",
        ".journey-rail",
        ".insurance-step-grid",
        ".partner-metric-grid",
        ".partner-engine-grid",
        ".partner-market-grid",
        ".partner-operating-grid",
      ].map((selector) => {
        const grid = document.querySelector(selector);
        if (!grid) return { selector, present: false };
        const cards = [...grid.querySelectorAll("article, .section-card, .infographic-step")];
        const columns = getComputedStyle(grid).gridTemplateColumns
          .split(" ")
          .filter((column) => column && column !== "none").length;
        const backgrounds = cards.map((card) => {
          const style = getComputedStyle(card);
          return style.backgroundImage && style.backgroundImage !== "none" ? style.backgroundImage : style.backgroundColor;
        });
        const textColors = cards.map((card) => getComputedStyle(card).color);
        const heights = cards.map((card) => Math.round(card.getBoundingClientRect().height));
        return {
          selector,
          present: true,
          cardCount: cards.length,
          columns,
          uniqueBackgrounds: new Set(backgrounds).size,
          plainWhiteCards: backgrounds.filter((value) => /255,\s*255,\s*255|255,\s*253,\s*251|rgba\(255,\s*255,\s*255/i.test(value)).length,
          allWhiteText: textColors.every((value) => /255,\s*253,\s*251|255,\s*255,\s*255/i.test(value)),
          minHeight: Math.min(...heights),
          maxHeight: Math.max(...heights),
        };
      }),
      isLegalRoute,
    };
  }, legalRoutes.has(route));

  const compactGridSelectors = new Set([".problem-list.compact", ".use-case-grid", ".craas-service-grid"]);
  const editorialGridSelectors = new Set([".content-grid", ".partner-engine-grid", ".partner-operating-grid"]);
  const presentCompactGrids = metrics.compactCardGrids.filter((grid) => grid.present && grid.cardCount >= 3);

  const checks = {
    http200: Boolean(response && response.status() >= 200 && response.status() < 300),
    noConsoleErrors: consoleMessages.length === 0 && pageErrors.length === 0,
    noHorizontalOverflow: Math.max(metrics.bodyScrollWidth, metrics.documentScrollWidth) <= metrics.viewportWidth + 1,
    hasTitleAndH1: metrics.title.length > 0 && metrics.h1.length > 0,
    ctaTrioPresent: metrics.locale === "rw"
      ? metrics.ctaCounts.rwGetApp >= 2 && metrics.ctaCounts.rwCreateGroup >= 2 && metrics.ctaCounts.rwGetInTouch >= 2
      : metrics.ctaCounts.getApp >= 2 && metrics.ctaCounts.createGroupSaving >= 2 && metrics.ctaCounts.getInTouch >= 2,
    retiredSectionsAbsent: metrics.retiredSectionsAbsent,
    disclaimerLabelsAbsent: metrics.disclaimerLabelsAbsent,
    routeClassPresent: metrics.bodyClass.includes(`route-${route === "/" ? "home" : routeName(route).replace(/_/g, "-")}`),
    mobileMenuOpens: !viewport.isMobile || mobileMenuOpen,
    mobileProductPreviewUsable: !viewport.isMobile || (metrics.heroDevice && metrics.heroDevice.height >= 220 && metrics.heroDevice.top < viewport.height),
    compactCardGridLayout: presentCompactGrids.every((grid) => {
      const maxAllowedHeight = grid.selector === ".content-grid" ? 900 : (editorialGridSelectors.has(grid.selector) ? 760 : (compactGridSelectors.has(grid.selector) ? 180 : 320));
      return viewport.allowedGridColumns.includes(grid.columns) &&
        grid.uniqueBackgrounds >= 2 &&
        grid.plainWhiteCards === 0 &&
        grid.maxHeight <= maxAllowedHeight;
    }),
    legalLayoutPresent: !metrics.isLegalRoute || metrics.legalLayoutPresent,
    footerTapTargets: !viewport.isMobile || metrics.footerRects.every((box) => box.height >= 40),
    keyboardTraversal: keyboardFocus.filter(Boolean).length >= 5 && keyboardFocus.some((item) => item && ["Skip to content", "Jya ku bikubiyemo"].includes(item.text)),
    visibleKeyboardFocus: keyboardFocus.filter(Boolean).length >= 5 &&
      keyboardFocus.filter(Boolean).every((item) =>
        item.focusVisible &&
        (
          (item.outlineStyle !== "none" && Number.parseFloat(item.outlineWidth) >= 2) ||
          item.boxShadow !== "none"
        )
      ),
    screenReaderSmoke: metrics.landmarkCounts.header === 1 &&
      metrics.landmarkCounts.main === 1 &&
      metrics.landmarkCounts.footer === 1 &&
      metrics.landmarkCounts.nav >= 2 &&
      metrics.accessibleNames.missingAlt === 0 &&
      metrics.accessibleNames.unnamedButtons === 0 &&
      metrics.accessibleNames.unnamedLinks === 0,
  };

  return {
    route,
    viewport: viewport.name,
    url,
    screenshot,
    menuScreenshot,
    checks,
    failures: Object.entries(checks).filter(([, passed]) => !passed).map(([id]) => id),
    metrics,
    keyboardFocus: keyboardFocus.filter(Boolean),
    consoleMessages,
    pageErrors,
  };
}

async function auditGroupShareScenario(page, scenario, viewport, shareHtml) {
  const consoleMessages = [];
  const pageErrors = [];
  page.on("console", (message) => {
    if (["error", "warning"].includes(message.type()) && !/favicon/i.test(message.text())) {
      consoleMessages.push({ type: message.type(), text: message.text() });
    }
  });
  page.on("pageerror", (error) => pageErrors.push(error.message));
  await page.route("**/c/**", async (route) => {
    if (route.request().resourceType() === "document") {
      await route.fulfill({ status: 200, contentType: "text/html", body: shareHtml });
    } else {
      await route.continue();
    }
  });

  const url = new URL(scenario.route, baseUrl).toString();
  const response = await page.goto(url, { waitUntil: "networkidle", timeout: 30_000 });
  await page.locator("h1").waitFor({ state: "visible", timeout: 10_000 });

  const keyboardFocus = [];
  for (let index = 0; index < 7; index += 1) {
    await page.keyboard.press("Tab");
    keyboardFocus.push(await page.evaluate(() => {
      const active = document.activeElement;
      if (!active || active === document.body) return null;
      const style = getComputedStyle(active);
      return {
        text: (active.getAttribute("aria-label") || active.textContent || "").trim().replace(/\s+/g, " ").slice(0, 80),
        focusVisible: active.matches(":focus-visible"),
        outlineStyle: style.outlineStyle,
        outlineWidth: style.outlineWidth,
        boxShadow: style.boxShadow,
      };
    }));
  }

  const metrics = await page.evaluate(() => {
    const openLink = document.querySelector("[data-collect-open-link]");
    const installLink = document.querySelector("[data-collect-store-link]");
    const appStoreLink = document.querySelector('a[href="https://apps.apple.com/app/id6783960331"]');
    const playStoreLink = document.querySelector('a[href="https://play.google.com/store/apps/details?id=app.cool.mobile"]');
    const copyButton = document.querySelector("[data-collect-copy-link]");
    const code = document.querySelector("[data-share-code]");
    const status = document.querySelector("[data-share-status]");
    const bodyText = document.body.innerText;
    return {
      openHref: openLink?.getAttribute("href") || null,
      openDisabled: openLink?.getAttribute("aria-disabled") === "true",
      installHref: installLink?.getAttribute("href") || "",
      hasExactStoreOptions: Boolean(appStoreLink && playStoreLink),
      codeText: code?.textContent.trim() || "",
      statusText: status?.textContent.trim() || "",
      hasValidityCopy: bodyText.includes("Expired, revoked or invalid links cannot join a group."),
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
  });

  const presentFocus = keyboardFocus.filter(Boolean);
  const checks = {
    rewriteServes200: Boolean(response && response.status() === 200),
    noConsoleErrors: consoleMessages.length === 0 && pageErrors.length === 0,
    noHorizontalOverflow: metrics.noHorizontalOverflow,
    failClosedValidityCopy: metrics.hasValidityCopy && metrics.noFalseJoinConfirmation,
    scenarioCode: metrics.codeText === scenario.codeText,
    nativeAction: scenario.nativeHref === null
      ? metrics.openHref === null && metrics.openDisabled === scenario.disabled
      : metrics.openHref === scenario.nativeHref && metrics.openDisabled === scenario.disabled,
    noAppFallback: metrics.installHref.includes("play.google.com") && metrics.hasExactStoreOptions && metrics.hasCopyAction &&
      metrics.actionRects.slice(1).every((rect) => rect && rect.width > 0 && rect.height >= 44 &&
        rect.display !== "none" && rect.visibility === "visible" && Number.parseFloat(rect.opacity) > 0),
    nativeActionVisible: Boolean(metrics.actionRects[0] && metrics.actionRects[0].width > 0 &&
      metrics.actionRects[0].height >= 44 && metrics.actionRects[0].display !== "none" &&
      metrics.actionRects[0].visibility === "visible" && Number.parseFloat(metrics.actionRects[0].opacity) > 0),
    exactCanonicalPath: metrics.canonicalPath.endsWith(scenario.route.replace("%20", "%20")),
    invalidRecoveryMessage: !scenario.disabled || metrics.statusText === "Ask the group member to share a new link.",
    keyboardTraversal: presentFocus.length >= 5 && presentFocus[0]?.text === "Skip to content",
    visibleKeyboardFocus: presentFocus.length >= 5 && presentFocus.every((item) =>
      item.focusVisible && (
        (item.outlineStyle !== "none" && Number.parseFloat(item.outlineWidth) >= 2) ||
        item.boxShadow !== "none"
      )),
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
    failures: Object.entries(checks).filter(([, passed]) => !passed).map(([id]) => id),
    metrics,
    keyboardFocus: presentFocus,
    consoleMessages,
    pageErrors,
  };
}

(async () => {
  fs.mkdirSync(screenshotDir, { recursive: true });
  const { modulePath, playwright } = await loadPlaywright();
  const executablePath = findExisting(chromeCandidates, "Chromium/Chrome executable");
  const browser = await playwright.chromium.launch({ executablePath, headless: true });
  const results = [];
  const shareResults = [];
  try {
    for (const route of sitemapRoutes()) {
      for (const viewport of viewports) {
        const page = await browser.newPage({
          viewport: { width: viewport.width, height: viewport.height },
          deviceScaleFactor: 1,
          isMobile: viewport.isMobile,
        });
        try {
          results.push(await auditRoute(page, route, viewport));
        } finally {
          await page.close();
        }
      }
    }
    const shareHtml = fs.readFileSync(path.join(buildDir, "c", "index.html"), "utf8");
    for (const scenario of groupShareScenarios) {
      for (const viewport of viewports) {
        const page = await browser.newPage({
          viewport: { width: viewport.width, height: viewport.height },
          deviceScaleFactor: 1,
          isMobile: viewport.isMobile,
        });
        try {
          shareResults.push(await auditGroupShareScenario(page, scenario, viewport, shareHtml));
        } finally {
          await page.close();
        }
      }
    }
  } finally {
    await browser.close();
  }

  const report = {
    checkedAt: new Date().toISOString(),
    baseUrl,
    buildDir,
    playwrightCore: modulePath,
    executablePath,
    status: [...results, ...shareResults].some((result) => result.failures.length > 0) ? "fail" : "pass",
    results,
    shareResults,
  };
  const reportPath = path.join(outDir, "route_rendered_qa.json");
  fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
  console.log(JSON.stringify({
    status: report.status,
    reportPath,
    screenshotCount: results.filter((result) => result.screenshot).length +
      results.filter((result) => result.menuScreenshot).length + shareResults.length,
    failures: [...results, ...shareResults]
      .flatMap((result) => result.failures.map((failure) => `${result.route} ${result.viewport}: ${failure}`)),
  }, null, 2));
  process.exit(report.status === "pass" ? 0 : 1);
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
