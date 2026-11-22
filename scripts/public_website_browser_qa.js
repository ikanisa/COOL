#!/usr/bin/env node
/* eslint-disable no-console */

const fs = require("fs");
const os = require("os");
const path = require("path");
const { chromeArguments, startDebugChrome } = require("./qa/browser/chrome_process.cjs");
const { waitForDevTools, connectDevTools, openTarget, navigate } = require("./qa/browser/chrome_devtools.cjs");
const { pngDimensions } = require("./qa/browser/png_dimensions.cjs");

const baseUrl = process.env.PUBLIC_WEBSITE_QA_URL || "http://127.0.0.1:4178/";
const outDir = path.resolve(process.env.PUBLIC_WEBSITE_QA_OUT || "output/public_website_evidence");
const screenshotDir = path.join(outDir, "screenshots");
const chromePath = process.env.PUBLIC_WEBSITE_CHROME_PATH || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const viewports = [
  { name: "mobile_390x844", width: 390, height: 844 },
  { name: "mobile_430x932", width: 430, height: 932 },
  { name: "tablet_768x1024", width: 768, height: 1024 },
  { name: "desktop_1440x1000", width: 1440, height: 1000 },
];

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function launchChrome() {
  if (!fs.existsSync(chromePath)) throw new Error(`Chrome not found: ${chromePath}`);
  let lastError;
  for (let attempt = 1; attempt <= 2; attempt += 1) {
    const profile = fs.mkdtempSync(path.join(os.tmpdir(), "collect-public-qa-"));
    const log = fs.createWriteStream(path.join(outDir, `browser_chrome_attempt_${attempt}.log`));
    let launch;
    try {
      launch = await startDebugChrome(chromePath, chromeArguments(profile, {
        headless: "--headless=new",
        extra: ["--disable-quic"],
      }), log);
      const browserWsUrl = await waitForDevTools(launch, 60_000);
      return { ...launch, browserWsUrl, profile };
    } catch (error) {
      lastError = error;
      if (launch) await launch.process.stop();
      else log.end();
      fs.rmSync(profile, { recursive: true, force: true });
    }
  }
  throw lastError;
}

async function closeChrome({ browserWsUrl, process, profile }) {
  let client;
  try {
    if (process.running) {
      client = await connectDevTools(browserWsUrl, { timeoutMs: 1000 });
      await client.send("Browser.close");
    }
  } catch {
    // Chromium can close the socket before acknowledging Browser.close.
  } finally {
    client?.close();
    await process.stop({ graceMs: 2000 });
    fs.rmSync(profile, { recursive: true, force: true });
  }
}

function captureDiagnostics() {
  const consoleMessages = [];
  const pageErrors = [];
  const documentStatuses = new Map();
  function onEvent({ method, params }) {
    if (method === "Runtime.consoleAPICalled") {
      const text = params.args.map((arg) => arg.value ?? arg.description ?? arg.type).join(" ");
      if (!/favicon/i.test(text)) consoleMessages.push({ type: params.type, text });
    }
    if (method === "Runtime.exceptionThrown") {
      pageErrors.push(params.exceptionDetails?.text || "Runtime exception thrown");
    }
    if (method === "Log.entryAdded") {
      const entry = params.entry;
      const url = entry.url || "";
      if (!/favicon/i.test(`${entry.text || ""} ${url}`)) {
        consoleMessages.push({ type: entry.level, text: entry.text, url });
      }
    }
    if (method === "Network.responseReceived" && params.type === "Document") {
      documentStatuses.set(params.loaderId, params.response.status);
    }
  }
  return { onEvent, consoleMessages, pageErrors, documentStatuses };
}

async function evaluate(cdp, expression) {
  const response = await cdp.send("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true, timeout: 15_000 });
  if (response.exceptionDetails) throw new Error(response.exceptionDetails.text || "Runtime.evaluate failed");
  return response.result.value;
}

async function screenshot(cdp, outputPath) {
  const result = await cdp.send("Page.captureScreenshot", { format: "png", fromSurface: true });
  fs.writeFileSync(outputPath, Buffer.from(result.data, "base64"));
}

function summarize(results) {
  return {
    status: results.some((result) => result.failures.length > 0) ? "fail" : "pass",
    evidenceDir: outDir,
    results: results.map((result) => ({
      viewport: result.viewport.name,
      failures: result.failures,
      wallMs: result.wallMs,
      timing: result.metrics.timing,
      screenshot: result.screenshot,
      menuScreenshot: result.menuScreenshot,
    })),
  };
}

(async () => {
  fs.mkdirSync(outDir, { recursive: true });
  fs.mkdirSync(screenshotDir, { recursive: true });
  const launch = await launchChrome();
  const results = [];
  try {
    for (const viewport of viewports) {
      const { onEvent, consoleMessages, pageErrors, documentStatuses } = captureDiagnostics();
      const cdp = await openTarget(launch.origin, { onEvent, allowLegacyGet: true });
      const started = Date.now();
      try {
        await cdp.send("Page.enable");
        await cdp.send("Runtime.enable");
        await cdp.send("Network.enable");
        await cdp.send("Log.enable").catch(() => {});
        await cdp.send("Emulation.setDeviceMetricsOverride", {
          width: viewport.width,
          height: viewport.height,
          deviceScaleFactor: 1,
          mobile: viewport.width < 800,
        });
        const [, navigation] = await Promise.all([
          cdp.waitFor("Page.loadEventFired", 15_000),
          navigate(cdp, baseUrl),
        ]);
        await sleep(200);
        const screenshotPath = path.join(screenshotDir, `${viewport.name}.png`);
        await screenshot(cdp, screenshotPath);
        const capturedPixels = pngDimensions(fs.readFileSync(screenshotPath), screenshotPath);

        let menuScreenshot = null;
        let mobileMenuOpen = viewport.width >= 800;
        if (viewport.width < 800) {
          await evaluate(cdp, `document.querySelector("[data-menu-button]")?.click(); true`);
          await sleep(100);
          menuScreenshot = path.join(screenshotDir, `${viewport.name}_menu.png`);
          await screenshot(cdp, menuScreenshot);
          mobileMenuOpen = await evaluate(cdp, `document.querySelector("[data-site-nav]")?.classList.contains("open") || false`);
          await evaluate(cdp, `document.querySelector("[data-menu-button]")?.click(); true`);
        }

        const metrics = await evaluate(cdp, `(() => {
          const rect = (selector) => {
            const element = document.querySelector(selector);
            if (!element) return null;
            const box = element.getBoundingClientRect();
            return { top: Math.round(box.top), bottom: Math.round(box.bottom), left: Math.round(box.left), right: Math.round(box.right), width: Math.round(box.width), height: Math.round(box.height) };
          };
          const accessibleName = (element) => (element.getAttribute("aria-label") || element.innerText || element.getAttribute("alt") || "").trim();
          const isLabeledControl = (input) => {
            if (input.type === "hidden") return true;
            if (input.getAttribute("aria-label") || input.getAttribute("aria-labelledby")) return true;
            if (input.id && document.querySelector(\`label[for="\${CSS.escape(input.id)}"]\`)) return true;
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
            emailFormPresent: Boolean(document.querySelector("input[type='email'], form input[name='email']")),
            creditReadinessExplainer: bodyText.includes("payments work. financial progress still does not.") && bodyText.includes("credit-readiness gap") && bodyText.includes("bank-ready loan files"),
            disclaimerLabelsAbsent: !bodyText.includes("currently available for android through the official collect by ikanisa google play listing") &&
              !bodyText.includes("ios availability is not currently advertised") &&
              !bodyText.includes("this website is published in english only") &&
              !bodyText.includes("how collect makes money") &&
              !bodyText.includes("public evidence and market context") &&
              !bodyText.includes("current public status") &&
              !bodyText.includes("no institution is presented here as a live collect partner yet") &&
              !bodyText.includes("no financial institution is presented on this website as a live collect partner"),
            missingAltCount: [...document.images].filter((image) => !image.hasAttribute("alt")).length,
            unnamedButtons: [...document.querySelectorAll("button")].filter((button) => !accessibleName(button)).length,
            unnamedLinksCount: [...document.querySelectorAll("a")].filter((link) => !accessibleName(link)).length,
            unlabeledInputs: [...document.querySelectorAll("input, textarea, select")].filter((input) => !isLabeledControl(input)).length,
            timing: navigation ? { domContentLoadedMs: Math.round(navigation.domContentLoadedEventEnd - navigation.startTime), loadMs: Math.round(navigation.loadEventEnd - navigation.startTime), transferSize: navigation.transferSize || 0, encodedBodySize: navigation.encodedBodySize || 0 } : null,
          };
        })()`);
        const wallMs = Date.now() - started;
        const checks = {
          http200: documentStatuses.get(navigation.loaderId) === 200,
          noConsoleErrors: consoleMessages.filter((message) => ["error", "warning"].includes(message.type)).length === 0 && pageErrors.length === 0,
          noHorizontalOverflow: !metrics.overflowX,
          hasH1: /Microsavings and group savings for daily earners/.test(metrics.h1),
          ctaInFirstViewport: metrics.primaryCta && metrics.primaryCta.top >= 0 && metrics.primaryCta.bottom <= viewport.height,
          productSignalInFirstViewport: metrics.productVisual && metrics.productVisual.top < viewport.height,
          mobileMenuOpens: mobileMenuOpen,
          hasPublicAppAndWhatsAppCtas: metrics.appDownloadLinkPresent && metrics.whatsappLinkCount >= 3 && !metrics.emailFormPresent,
          hasCreditExplainer: metrics.creditReadinessExplainer,
          disclaimerLabelsAbsent: metrics.disclaimerLabelsAbsent,
          accessibleNames: metrics.missingAltCount === 0 && metrics.unnamedButtons === 0 && metrics.unnamedLinksCount === 0 && metrics.unlabeledInputs === 0,
          localLoadUnder1500ms: wallMs <= 1500 || (metrics.timing && metrics.timing.loadMs <= 1500),
        };
        results.push({
          viewport,
          requested_viewport: { width: viewport.width, height: viewport.height },
          captured_pixels: capturedPixels,
          screenshot: screenshotPath,
          menuScreenshot,
          checks,
          failures: Object.entries(checks).filter(([, passed]) => !passed).map(([id]) => id),
          metrics,
          consoleMessages: consoleMessages,
          pageErrors: pageErrors,
          wallMs,
        });
      } finally {
        await cdp.close();
      }
    }
  } finally {
    await closeChrome(launch);
  }
  const summary = summarize(results);
  const report = { status: summary.status, checkedAt: new Date().toISOString(), baseUrl, results };
  fs.writeFileSync(path.join(outDir, "browser_visual_qa.json"), JSON.stringify(report, null, 2));
  console.log(JSON.stringify(summary, null, 2));
  process.exit(summary.status === "pass" ? 0 : 1);
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
