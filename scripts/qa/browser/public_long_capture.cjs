"use strict";

const { createHash } = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { withLoopbackPage } = require("./playwright_runner.cjs");
const { pngDimensions } = require("./png_dimensions.cjs");
const { openRenderedRoute } = require("./rendered_page_evidence.cjs");
const { captureOriginalViewportSegments, longPageCaptureThreshold } = require("./viewport_segments.cjs");

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function hashFile(file) {
  return sha256(fs.readFileSync(file));
}

function relativeArtifactFiles(directory, prefix = "") {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const relative = prefix + entry.name;
    if (entry.isDirectory()) return relativeArtifactFiles(path.join(directory, entry.name), relative + "/");
    if (!entry.isFile()) throw new Error(`Invalid public artifact file: ${relative}`);
    return [relative];
  });
}

function requireBuildIdentity(buildDir, artifactFiles) {
  const paths = relativeArtifactFiles(buildDir).sort();
  if (!paths.length || JSON.stringify(paths) !== JSON.stringify(Object.keys(artifactFiles).sort()) ||
      paths.some((file) => hashFile(path.join(buildDir, file)) !== artifactFiles[file])) {
    throw new Error("Build bytes differ from prior QA receipt");
  }
}

function loadLongCapturePlan(reportFile, executionFile, buildDir) {
  if (!reportFile || !executionFile) throw new Error("Long capture requires both prior QA and artifact execution receipts");
  const reportBytes = fs.readFileSync(reportFile);
  const executionBytes = fs.readFileSync(executionFile);
  const prior = JSON.parse(reportBytes);
  const execution = JSON.parse(executionBytes);
  if (prior.status !== "pass" || !execution.artifact_unchanged ||
      path.resolve(prior.buildDir) !== buildDir || !Array.isArray(prior.results) || !Array.isArray(prior.shareResults)) {
    throw new Error("Prior unchanged-build QA did not pass");
  }
  const artifactFiles = execution.artifact_files;
  requireBuildIdentity(buildDir, artifactFiles);
  return {
    prior,
    artifactFiles,
    receiptFields: {
      priorAssertionsReport: path.resolve(reportFile),
      priorAssertionsReportSha256: sha256(reportBytes),
      priorExecution: path.resolve(executionFile),
      priorExecutionSha256: sha256(executionBytes),
      priorRouteAssertionCount: prior.results.length,
      priorShareAssertionCount: prior.shareResults.length,
    },
  };
}

async function captureLongPages(browser, plan, { buildDir, viewports, network, screenshotDir }) {
  const results = [];
  for (const row of plan.prior.results) {
    if (!row.fullPageScreenshot) continue;
    const previousPng = fs.readFileSync(row.fullPageScreenshot);
    if (pngDimensions(previousPng, row.fullPageScreenshot).height <= longPageCaptureThreshold) continue;
    const viewport = viewports.find(item => item.name === row.viewport);
    if (!viewport) throw new Error(`Unknown viewport: ${row.viewport}`);
    const capture = await withLoopbackPage(browser, viewport, network, async (page) => {
      const response = await openRenderedRoute(page, new URL(row.route, network.baseUrl).toString());
      if (!response || response.status() !== 200) throw new Error(`Long page did not return HTTP200: ${row.route}`);
      return captureOriginalViewportSegments(page, row.route, viewport, screenshotDir);
    });
    results.push({
      route: row.route,
      viewport: row.viewport,
      supersededFullPageScreenshot: row.fullPageScreenshot,
      supersededFullPageSha256: sha256(previousPng),
      fullPageScreenshot: null,
      longPageCapture: capture,
    });
    console.log(`Original viewport capture ${row.route} ${row.viewport}: ${capture.segments.length} segments`);
  }
  requireBuildIdentity(buildDir, plan.artifactFiles);
  if (network.denied.length) throw new Error("Blocked network request during long capture");
  return results;
}

module.exports = { hashFile, loadLongCapturePlan, captureLongPages };
