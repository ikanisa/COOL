#!/usr/bin/env node
/* eslint-disable no-console */

const fs = require("fs");
const path = require("path");

const baseUrl = process.env.PUBLIC_WEBSITE_QA_URL || "https://collect.ikanisa.com/";
const outDir = path.resolve(process.env.PUBLIC_WEBSITE_QA_OUT || "output/public_website_evidence");
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
  { name: "mobile_390x844", width: 390, height: 844, isMobile: true },
  { name: "mobile_430x932", width: 430, height: 932, isMobile: true },
  { name: "tablet_768x1024", width: 768, height: 1024, isMobile: true },
  { name: "desktop_1440x1000", width: 1440, height: 1000, isMobile: false },
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

async function auditPage(page, viewport) {
  const consoleMessages = [];
  const pageErrors = [];
  page.on("console", (message) => {
    if (["error", "warning"].includes(message.type()) && !/favicon/i.test(message.text())) {
      consoleMessages.push({ type: message.type(), text: message.text() });
    }
  });
  page.on("pageerror", (error) => pageErrors.push(error.message));

  const response = await page.goto(baseUrl, { waitUntil: "domcontentloaded", timeout: 30_000 });
  await page.locator("h1").waitFor({ state: "visible", timeout: 10_000 });
  await page.waitForTimeout(200);

  const screenshot = path.join(screenshotDir, `${viewport.name}.png`);
  await page.screenshot({ path: screenshot, fullPage: false });

  let menuScreenshot = null;
  let mobileMenuOpen = true;
  if (viewport.width < 800) {
    await page.locator("[data-menu-button]").click({ timeout: 5_000 });
    await page.waitForTimeout(100);
    mobileMenuOpen = await page.locator("[data-site-nav]").evaluate((node) => node.classList.contains("open"));
    menuScreenshot = path.join(screenshotDir, `${viewport.name}_menu.png`);
    await page.screenshot({ path: menuScreenshot, fullPage: false });
    await page.locator("[data-menu-button]").click({ timeout: 5_000 });
  }

  const metrics = await page.evaluate(() => {
    const rect = (selector) => {
      const element = document.querySelector(selector);
      if (!element) return null;
      const box = element.getBoundingClientRect();
      return {
        top: Math.round(box.top),
        bottom: Math.round(box.bottom),
        left: Math.round(box.left),
        right: Math.round(box.right),
        width: Math.round(box.width),
        height: Math.round(box.height),
      };
    };
    const accessibleName = (element) => (element.getAttribute("aria-label") || element.innerText || element.getAttribute("alt") || "").trim();
    const isLabeledControl = (input) => {
      if (input.type === "hidden") return true;
      if (input.getAttribute("aria-label") || input.getAttribute("aria-labelledby")) return true;
      if (input.id && document.querySelector(`label[for="${CSS.escape(input.id)}"]`)) return true;
      return Boolean(input.closest("label"));
    };
    const navigation = performance.getEntriesByType("navigation")[0];
    const bodyText = document.body.innerText.toLowerCase();
    return {
      title: document.title,
      h1: document.querySelector("h1")?.innerText || "",
      lang: document.documentElement.lang,
      bodyScrollWidth: document.body.scrollWidth,
      documentScrollWidth: document.documentElement.scrollWidth,
      overflowX: Math.max(document.body.scrollWidth, document.documentElement.scrollWidth) > window.innerWidth + 1,
      header: rect(".site-header"),
      hero: rect(".hero"),
      h1Rect: rect("h1"),
      primaryCta: rect(".hero-actions .button.primary"),
      productVisual: rect(".hero-device"),
      whatsappLinkCount: document.querySelectorAll("a[href^='https://wa.me/']").length,
      appDownloadLinkPresent: Boolean(document.querySelector("a[href='https://play.google.com/store/apps/details?id=app.cool.mobile']")),
      emailSupportPresent: Boolean(document.querySelector("input[type='email'], a[href^='mailto:']")),
      supportFileExplainer: bodyText.includes("prepare better support files for financial-service review"),
      providerDecisionBoundary: bodyText.includes("final credit decisions remain with the provider"),
      missingAltCount: [...document.images].filter((image) => !image.hasAttribute("alt")).length,
      unnamedButtons: [...document.querySelectorAll("button")].filter((button) => !accessibleName(button)).length,
      unnamedLinksCount: [...document.querySelectorAll("a")].filter((link) => !accessibleName(link)).length,
      unlabeledInputs: [...document.querySelectorAll("input, textarea, select")].filter((input) => !isLabeledControl(input)).length,
      timing: navigation ? {
        domContentLoadedMs: Math.round(navigation.domContentLoadedEventEnd - navigation.startTime),
        loadMs: Math.round(navigation.loadEventEnd - navigation.startTime),
        transferSize: navigation.transferSize || 0,
        encodedBodySize: navigation.encodedBodySize || 0,
      } : null,
    };
  });

  const checks = {
    http200: Boolean(response && response.status() >= 200 && response.status() < 300),
    noConsoleErrors: consoleMessages.length === 0 && pageErrors.length === 0,
    noHorizontalOverflow: !metrics.overflowX,
    hasH1: /Clearer records for savings groups/.test(metrics.h1),
    ctaInFirstViewport: metrics.primaryCta && metrics.primaryCta.top >= 0 && metrics.primaryCta.bottom <= viewport.height,
    productSignalInFirstViewport: metrics.productVisual && metrics.productVisual.top < viewport.height,
    mobileMenuOpens: mobileMenuOpen,
    hasPublicAppAndWhatsAppCtas: metrics.appDownloadLinkPresent && metrics.whatsappLinkCount >= 3 && !metrics.emailSupportPresent,
    hasCreditExplainer: metrics.supportFileExplainer && metrics.providerDecisionBoundary,
    accessibleNames: metrics.missingAltCount === 0 && metrics.unnamedButtons === 0 && metrics.unnamedLinksCount === 0 && metrics.unlabeledInputs === 0,
    localLoadUnder1500ms: metrics.timing && metrics.timing.loadMs <= 1500,
  };

  return {
    viewport: viewport.name,
    dimensions: { width: viewport.width, height: viewport.height },
    screenshot,
    menuScreenshot,
    checks,
    failures: Object.entries(checks).filter(([, passed]) => !passed).map(([id]) => id),
    metrics,
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
  try {
    for (const viewport of viewports) {
      const page = await browser.newPage({
        viewport: { width: viewport.width, height: viewport.height },
        deviceScaleFactor: 1,
        isMobile: viewport.isMobile,
      });
      try {
        results.push(await auditPage(page, viewport));
      } finally {
        await page.close();
      }
    }
  } finally {
    await browser.close();
  }

  const report = {
    checkedAt: new Date().toISOString(),
    baseUrl,
    playwrightCore: modulePath,
    executablePath,
    status: results.some((result) => result.failures.length > 0) ? "fail" : "pass",
    results,
  };
  fs.writeFileSync(path.join(outDir, "browser_visual_qa.json"), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({
    status: report.status,
    evidenceDir: outDir,
    screenshots: results.map((result) => result.screenshot),
    failures: results.flatMap((result) => result.failures.map((failure) => `${result.viewport}:${failure}`)),
  }, null, 2));
  process.exit(report.status === "pass" ? 0 : 1);
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
