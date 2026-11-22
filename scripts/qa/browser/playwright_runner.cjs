"use strict";

const { existsSync } = require("node:fs");
const { join, resolve } = require("node:path");
const { pathToFileURL } = require("node:url");
const { installLocalNetworkFence } = require("../public_browser_local_network.cjs");

const installedPlaywright = join(__dirname, "../../../admin-web/node_modules/playwright-core/index.js");
const defaultChrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

function findExisting(candidates, label) {
  const usable = candidates.filter(Boolean);
  const found = usable.find(candidate => existsSync(candidate));
  if (!found) throw new Error(`No usable ${label} found. Checked: ${usable.join(", ")}`);
  return resolve(found);
}

async function launchPlaywright({ moduleCandidates = [], chromeCandidates = [], args = [], installedFirst = true } = {}) {
  const modulePath = findExisting([
    process.env.PLAYWRIGHT_CORE_PATH,
    ...(installedFirst ? [installedPlaywright, ...moduleCandidates] : [...moduleCandidates, installedPlaywright]),
  ], "playwright-core module");
  const loaded = await import(pathToFileURL(modulePath).href);
  const playwright = loaded.default || loaded;
  const executablePath = findExisting([
    process.env.PUBLIC_WEBSITE_CHROME_PATH, ...chromeCandidates, defaultChrome,
  ], "Chromium/Chrome executable");
  const browser = await playwright.chromium.launch({ executablePath, headless: true, args });
  return { browser, modulePath, executablePath };
}

async function withPage(browser, options, audit, network) {
  const page = await browser.newPage(network ? {...options, serviceWorkers: "block"} : options);
  try {
    if (network) await installLocalNetworkFence(page, network.baseUrl, network.denied);
    return await audit(page);
  } finally {
    await page.close();
  }
}

function withLoopbackPage(browser, viewport, network, audit) {
  return withPage(browser, {
    viewport: { width: viewport.width, height: viewport.height },
    deviceScaleFactor: 1,
    isMobile: viewport.isMobile,
  }, audit, network);
}

module.exports = { launchPlaywright, withPage, withLoopbackPage };
