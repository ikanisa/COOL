#!/usr/bin/env node
/* eslint-disable no-console */

const { spawn } = require("child_process");
const fs = require("fs");
const net = require("net");
const os = require("os");
const path = require("path");

const baseUrl = process.env.PUBLIC_WEBSITE_QA_URL || "http://127.0.0.1:4178/";
const outDir = path.resolve(process.env.PUBLIC_WEBSITE_QA_OUT || "docs/release/collect_public_website_evidence_2026-06-22");
const screenshotDir = path.join(outDir, "screenshots");
const chromePath = process.env.PUBLIC_WEBSITE_CHROME_PATH || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const viewports = [
  { name: "mobile_390x844", width: 390, height: 844 },
  { name: "mobile_430x932", width: 430, height: 932 },
  { name: "tablet_768x1024", width: 768, height: 1024 },
  { name: "desktop_1440x1000", width: 1440, height: 1000 },
];

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function freePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.unref();
    server.on("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      server.close(() => resolve(address.port));
    });
  });
}

async function fetchJson(url, options = {}) {
  let response;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), options.timeoutMs || 2_000);
  try {
    response = await fetch(url, { ...options, signal: controller.signal });
  } catch (error) {
    throw new Error(`${options.method || "GET"} ${url} failed: ${error.message}`);
  } finally {
    clearTimeout(timeout);
  }
  if (!response.ok) throw new Error(`${options.method || "GET"} ${url} returned HTTP ${response.status}`);
  return response.json();
}

async function waitForDevTools(baseUrl) {
  let lastError;
  const deadline = Date.now() + 60_000;
  while (Date.now() < deadline) {
    try {
      return await fetchJson(`${baseUrl}/json/version`);
    } catch (error) {
      lastError = error;
      await sleep(250);
    }
  }
  throw lastError || new Error("Chrome DevTools endpoint did not start");
}

async function createTarget(baseUrl) {
  const encoded = encodeURIComponent("about:blank");
  try {
    return await fetchJson(`${baseUrl}/json/new?${encoded}`, { method: "PUT" });
  } catch (_) {
    return fetchJson(`${baseUrl}/json/new?${encoded}`);
  }
}

class CdpClient {
  constructor(wsUrl) {
    this.wsUrl = wsUrl;
    this.nextId = 1;
    this.pending = new Map();
    this.waiters = new Map();
    this.consoleMessages = [];
    this.pageErrors = [];
  }

  connect() {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error(`Timed out connecting to ${this.wsUrl}`)), 15_000);
      this.ws = new WebSocket(this.wsUrl);
      this.ws.addEventListener("open", () => {
        clearTimeout(timeout);
        resolve();
      });
      this.ws.addEventListener("error", (event) => {
        clearTimeout(timeout);
        reject(new Error(String(event.message || event.type)));
      });
      this.ws.addEventListener("message", (event) => this.handleMessage(event.data));
    });
  }

  handleMessage(raw) {
    const message = JSON.parse(String(raw));
    if (message.id && this.pending.has(message.id)) {
      const { resolve, reject } = this.pending.get(message.id);
      this.pending.delete(message.id);
      message.error ? reject(new Error(message.error.message || JSON.stringify(message.error))) : resolve(message.result || {});
      return;
    }
    if (message.method === "Runtime.consoleAPICalled") {
      const text = message.params.args.map((arg) => arg.value ?? arg.description ?? arg.type).join(" ");
      if (!/favicon/i.test(text)) this.consoleMessages.push({ type: message.params.type, text });
    }
    if (message.method === "Runtime.exceptionThrown") {
      this.pageErrors.push(message.params.exceptionDetails?.text || "Runtime exception thrown");
    }
    if (message.method === "Log.entryAdded") {
      const entry = message.params.entry;
      if (!/favicon/i.test(entry.text || "")) this.consoleMessages.push({ type: entry.level, text: entry.text });
    }
    const waiters = this.waiters.get(message.method);
    if (waiters) {
      for (const waiter of waiters.splice(0)) {
        clearTimeout(waiter.timeout);
        waiter.resolve(message.params || {});
      }
    }
  }

  send(method, params = {}, timeoutMs = 15_000) {
    const id = this.nextId++;
    this.ws.send(JSON.stringify({ id, method, params }));
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`Timed out sending ${method}`));
      }, timeoutMs);
      this.pending.set(id, {
        resolve: (value) => {
          clearTimeout(timeout);
          resolve(value);
        },
        reject: (error) => {
          clearTimeout(timeout);
          reject(error);
        },
      });
    });
  }

  waitFor(method, timeoutMs) {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error(`Timed out waiting for ${method}`)), timeoutMs);
      const waiters = this.waiters.get(method) || [];
      waiters.push({ resolve, timeout });
      this.waiters.set(method, waiters);
    });
  }

  close() {
    if (this.ws) this.ws.close();
  }
}

async function launchChrome() {
  if (!fs.existsSync(chromePath)) throw new Error(`Chrome not found: ${chromePath}`);
  let lastError;
  for (let attempt = 1; attempt <= 2; attempt += 1) {
    const remotePort = await freePort();
    const remoteBaseUrl = `http://127.0.0.1:${remotePort}`;
    const profile = fs.mkdtempSync(path.join(os.tmpdir(), "collect-public-qa-"));
    const log = fs.createWriteStream(path.join(outDir, `browser_chrome_attempt_${attempt}.log`));
    const chrome = spawn(chromePath, [
      "--headless=new",
      "--force-device-scale-factor=1",
      "--disable-gpu",
      "--disable-background-networking",
      "--disable-component-update",
      "--disable-sync",
      "--disable-dev-shm-usage",
      "--no-sandbox",
      "--no-first-run",
      "--no-default-browser-check",
      `--user-data-dir=${profile}`,
      "--remote-debugging-address=127.0.0.1",
      `--remote-debugging-port=${remotePort}`,
      "about:blank",
    ], { stdio: ["ignore", "pipe", "pipe"] });
    chrome.stdout.pipe(log);
    chrome.stderr.pipe(log);
    try {
      const version = await waitForDevTools(remoteBaseUrl);
      return { browserWsUrl: version.webSocketDebuggerUrl, chrome, profile, remoteBaseUrl };
    } catch (error) {
      lastError = error;
      chrome.stdout.unpipe(log);
      chrome.stderr.unpipe(log);
      log.end();
      if (chrome.exitCode === null && chrome.signalCode === null) {
        chrome.kill("SIGTERM");
        await Promise.race([new Promise((resolve) => chrome.once("exit", resolve)), sleep(1_000)]);
      }
      if (chrome.exitCode === null && chrome.signalCode === null) {
        chrome.kill("SIGKILL");
        await Promise.race([new Promise((resolve) => chrome.once("exit", resolve)), sleep(1_000)]);
      }
      fs.rmSync(profile, { recursive: true, force: true });
    }
  }
  throw lastError || new Error("Chrome did not start");
}

async function closeChrome(browserWsUrl, chrome, profile) {
  if (browserWsUrl && chrome.exitCode === null && chrome.signalCode === null) {
    const browser = new CdpClient(browserWsUrl);
    await browser.connect()
      .then(() => Promise.race([browser.send("Browser.close", {}, 1_000), sleep(1_000)]))
      .catch(() => {});
    browser.close();
    await Promise.race([new Promise((resolve) => chrome.once("exit", resolve)), sleep(2000)]);
  }
  if (chrome.exitCode === null && chrome.signalCode === null) {
    chrome.kill("SIGTERM");
    await Promise.race([new Promise((resolve) => chrome.once("exit", resolve)), sleep(1000)]);
  }
  if (chrome.exitCode === null && chrome.signalCode === null) {
    chrome.kill("SIGKILL");
    await Promise.race([new Promise((resolve) => chrome.once("exit", resolve)), sleep(1000)]);
  }
  fs.rmSync(profile, { recursive: true, force: true });
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
  const { browserWsUrl, chrome, profile, remoteBaseUrl } = await launchChrome();
  const results = [];
  try {
    for (const viewport of viewports) {
      const target = await createTarget(remoteBaseUrl);
      const cdp = new CdpClient(target.webSocketDebuggerUrl);
      await cdp.connect();
      const started = Date.now();
      try {
        await cdp.send("Page.enable");
        await cdp.send("Runtime.enable");
        await cdp.send("Log.enable").catch(() => {});
        await cdp.send("Emulation.setDeviceMetricsOverride", {
          width: viewport.width,
          height: viewport.height,
          deviceScaleFactor: 1,
          mobile: viewport.width < 800,
        });
        const loadPromise = cdp.waitFor("Page.loadEventFired", 15_000);
        await cdp.send("Page.navigate", { url: baseUrl });
        await loadPromise;
        await sleep(200);
        const screenshotPath = path.join(screenshotDir, `${viewport.name}.png`);
        await screenshot(cdp, screenshotPath);

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
            formPresent: Boolean(document.querySelector(".lead-form")),
            formEmailInput: Boolean(document.querySelector("input[type='email']")),
            creditExplainer: bodyText.includes("how credit-readiness works"),
            noApprovalPromise: bodyText.includes("final credit decisions remain with the provider"),
            missingAltCount: [...document.images].filter((image) => !image.hasAttribute("alt")).length,
            unnamedButtons: [...document.querySelectorAll("button")].filter((button) => !accessibleName(button)).length,
            unnamedLinksCount: [...document.querySelectorAll("a")].filter((link) => !accessibleName(link)).length,
            unlabeledInputs: [...document.querySelectorAll("input, textarea, select")].filter((input) => !isLabeledControl(input)).length,
            timing: navigation ? { domContentLoadedMs: Math.round(navigation.domContentLoadedEventEnd - navigation.startTime), loadMs: Math.round(navigation.loadEventEnd - navigation.startTime), transferSize: navigation.transferSize || 0, encodedBodySize: navigation.encodedBodySize || 0 } : null,
          };
        })()`);
        const wallMs = Date.now() - started;
        const checks = {
          http200: true,
          noConsoleErrors: cdp.consoleMessages.filter((message) => ["error", "warning"].includes(message.type)).length === 0 && cdp.pageErrors.length === 0,
          noHorizontalOverflow: !metrics.overflowX,
          hasH1: /Credit-ready/.test(metrics.h1),
          ctaInFirstViewport: metrics.primaryCta && metrics.primaryCta.top >= 0 && metrics.primaryCta.bottom <= viewport.height,
          productSignalInFirstViewport: metrics.productVisual && metrics.productVisual.top < viewport.height,
          mobileMenuOpens: mobileMenuOpen,
          hasSelfServeForm: metrics.formPresent && metrics.formEmailInput,
          hasCreditExplainer: metrics.creditExplainer && metrics.noApprovalPromise,
          accessibleNames: metrics.missingAltCount === 0 && metrics.unnamedButtons === 0 && metrics.unnamedLinksCount === 0 && metrics.unlabeledInputs === 0,
          localLoadUnder1500ms: wallMs <= 1500 || (metrics.timing && metrics.timing.loadMs <= 1500),
        };
        results.push({
          viewport,
          screenshot: screenshotPath,
          menuScreenshot,
          checks,
          failures: Object.entries(checks).filter(([, passed]) => !passed).map(([id]) => id),
          metrics,
          consoleMessages: cdp.consoleMessages,
          pageErrors: cdp.pageErrors,
          wallMs,
        });
      } finally {
        cdp.close();
      }
    }
  } finally {
    await closeChrome(browserWsUrl, chrome, profile);
  }
  const report = { checkedAt: new Date().toISOString(), baseUrl, results };
  fs.writeFileSync(path.join(outDir, "browser_visual_qa.json"), JSON.stringify(report, null, 2));
  const summary = summarize(results);
  console.log(JSON.stringify(summary, null, 2));
  process.exit(summary.status === "pass" ? 0 : 1);
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
