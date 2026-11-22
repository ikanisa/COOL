#!/usr/bin/env node
/* eslint-disable no-console */

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");
const { requireLoopbackOrigin } = require("./qa/public_browser_local_network.cjs");
const { launchPlaywright, withLoopbackPage } = require("./qa/browser/playwright_runner.cjs");
const { auditRoute } = require("./qa/browser/public_route_case.cjs");
const { auditGroupShareScenario } = require("./qa/browser/public_share_case.cjs");
const { hashFile, loadLongCapturePlan, captureLongPages } = require("./qa/browser/public_long_capture.cjs");

const baseUrl = process.env.PUBLIC_WEBSITE_QA_URL || "http://127.0.0.1:4178/";
requireLoopbackOrigin(baseUrl);
const blockedNetworkRequests = [];
const network = { baseUrl, denied: blockedNetworkRequests };
const capabilityContract = JSON.parse(execFileSync("ruby", [path.join(__dirname, "qa/public_capability_contract.rb")], { encoding: "utf8" }));
const buildDir = path.resolve(process.env.PUBLIC_BUILD_DIR || "build/public_web");
const outDir = path.resolve(process.env.PUBLIC_WEBSITE_QA_OUT || "output/public_website_route_rendered_qa");
const screenshotDir = path.join(outDir, "screenshots");
const playwrightCoreCandidates = [
  "/Volumes/PRO-G40/Temp/caches/npm/_npx/705bc6b22212b352/node_modules/playwright-core/index.js",
  "/Library/Frameworks/Python.framework/Versions/3.13/lib/python3.13/site-packages/playwright/driver/package/index.js",
  "/Volumes/PRO-G40/X CPA/firmos/node_modules/playwright-core/index.js",
].filter(Boolean);
const chromeCandidates = [
  path.join(process.env.HOME || "", "Library/Caches/ms-playwright/chromium-1223/chrome-mac-x64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing"),
  path.join(process.env.HOME || "", "Library/Caches/ms-playwright/chromium-1217/chrome-mac-x64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing"),
].filter(Boolean);
const viewports = [
  { name: "compact_320x740", width: 320, height: 740, isMobile: true, allowedGridColumns: [1] },
  { name: "mobile_390x844", width: 390, height: 844, isMobile: true, allowedGridColumns: [2] },
  { name: "tablet_834x1194", width: 834, height: 1194, isMobile: false, allowedGridColumns: [2, 3] },
  { name: "desktop_1440x1000", width: 1440, height: 1000, isMobile: false, allowedGridColumns: [2, 3] },
];
const shareId = "f0e5d2a1-9213-45cc-8e03-123456789abc";
const groupShareScenarios = [
  {name: "group_uuid", route: `/c/${shareId}`, canOpen: true},
  {name: "legacy_query_uuid", route: `/group-link/?slug=${shareId.toUpperCase()}`, canOpen: true},
  {name: "obsolete_slug", route: "/c/invalid%20code", canOpen: false},
  {name: "oversized_code", route: `/c/${"a".repeat(141)}`, canOpen: false},
];

function sitemapRoutes() {
  const xml = fs.readFileSync(path.join(buildDir, "sitemap.xml"), "utf8");
  const routes = [...xml.matchAll(/<loc>https:\/\/collect\.ikanisa\.com([^<]*)<\/loc>/g)]
    .map((match) => match[1] || "/");
  const registered = Object.keys(capabilityContract.routes).sort();
  if (JSON.stringify([...routes].sort()) !== JSON.stringify(registered)) {
    throw new Error("Public sitemap and capability route contract differ");
  }
  return routes;
}

const auditedSources = [
  "public_website_route_rendered_qa.js",
  "qa/public_browser_local_network.cjs",
  "qa/browser/playwright_runner.cjs",
  "qa/browser/png_dimensions.cjs",
  "qa/browser/public_long_capture.cjs",
  "qa/browser/public_route_case.cjs",
  "qa/browser/public_share_case.cjs",
  "qa/browser/rendered_page_evidence.cjs",
  "qa/browser/viewport_segments.cjs",
];

function scriptSources() {
  return Object.fromEntries(auditedSources.map(file => [file, hashFile(path.join(__dirname, file))]));
}

function verifyScriptSources(expected) {
  if (JSON.stringify(scriptSources()) !== JSON.stringify(expected)) {
    throw new Error("Public browser QA sources changed during the run");
  }
}

async function auditSite(browser) {
  const results = [];
  for (const route of sitemapRoutes()) {
    for (const viewport of viewports) {
      results.push(await withLoopbackPage(browser, viewport, network, page => auditRoute(page, route, viewport, {
        baseUrl, screenshotDir, capabilityContract,
      })));
    }
  }

  const version = JSON.parse(fs.readFileSync(path.join(buildDir, "version.json"), "utf8"));
  const publicOrigin = new URL(version.public_origin).origin;
  if (!publicOrigin.startsWith("https://")) throw new Error("Public share checks require a configured HTTPS origin");
  const shareHtml = fs.readFileSync(path.join(buildDir, "c", "index.html"), "utf8");
  const shareResults = [];
  for (const scenario of groupShareScenarios) {
    for (const viewport of viewports) {
      shareResults.push(await withLoopbackPage(browser, viewport, network, page => auditGroupShareScenario(page, scenario, viewport, {
        shareHtml, publicOrigin, baseUrl, shareId, screenshotDir,
      })));
    }
  }
  return { results, shareResults };
}

function writeLongCaptureReport(evidence, plan, results) {
  const report = {
    ...evidence,
    status: "pass",
    kind: "long_page_original_viewport_capture",
    design_authority: "revolut-design",
    scriptSha256: evidence.scriptSources["public_website_route_rendered_qa.js"],
    artifactFiles: plan.artifactFiles,
    artifactUnchanged: true,
    ...plan.receiptFields,
    results,
  };
  const reportPath = path.join(outDir, "long_page_capture.json");
  fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
  console.log(JSON.stringify({
    status: report.status,
    reportPath,
    longPageCount: results.length,
    screenshotCount: results.reduce((sum, row) => sum + row.longPageCapture.segments.length, 0),
  }, null, 2));
}

function writeRouteReport(evidence, { results, shareResults }) {
  const failures = [...results, ...shareResults]
    .flatMap(result => result.failures.map(failure => `${result.route} ${result.viewport}: ${failure}`));
  const report = {
    ...evidence,
    status: blockedNetworkRequests.length || failures.length ? "fail" : "pass",
    networkScope: "Local Chromium. The share page renders at its configured URL using only packaged HTML and assets from the loopback server. Clipboard actions use an in-memory fixture.",
    capabilityRegistrySha256: capabilityContract.registry_sha256,
    capabilityApproval: capabilityContract.approval,
    results,
    shareResults,
  };
  const reportPath = path.join(outDir, "route_rendered_qa.json");
  fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
  const screenshotCount = results.reduce((total, result) => total +
    [result.screenshot, result.fullPageScreenshot, result.menuScreenshot].filter(Boolean).length +
    (result.longPageCapture?.segments.length || 0), shareResults.length);
  console.log(JSON.stringify({ status: report.status, reportPath, screenshotCount, failures }, null, 2));
  process.exitCode = report.status === "pass" ? 0 : 1;
}

async function main() {
  // A follow-up repairs long pages of the same verified artifact without rerunning the site matrix.
  const reportFile = process.env.PUBLIC_WEBSITE_QA_LONG_CAPTURE_REPORT;
  const executionFile = process.env.PUBLIC_WEBSITE_QA_LONG_CAPTURE_EXECUTION;
  const plan = reportFile || executionFile ? loadLongCapturePlan(reportFile, executionFile, buildDir) : null;
  fs.mkdirSync(screenshotDir, { recursive: true });
  const sources = scriptSources();
  const { browser, modulePath, executablePath } = await launchPlaywright({
    moduleCandidates: playwrightCoreCandidates, chromeCandidates,
    args: ["--disable-background-networking", "--disable-component-update", "--no-first-run"],
  });
  const evidence = {
    baseUrl,
    buildDir,
    playwrightCore: modulePath,
    executablePath,
    scriptSources: sources,
    blockedNetworkRequests,
  };
  try {
    if (plan) {
      const results = await captureLongPages(browser, plan, { buildDir, viewports, network, screenshotDir });
      verifyScriptSources(sources);
      writeLongCaptureReport({ ...evidence, checkedAt: new Date().toISOString() }, plan, results);
    } else {
      const results = await auditSite(browser);
      verifyScriptSources(sources);
      writeRouteReport({ ...evidence, checkedAt: new Date().toISOString() }, results);
    }
  } finally {
    await browser.close();
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
