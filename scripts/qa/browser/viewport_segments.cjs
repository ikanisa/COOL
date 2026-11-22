"use strict";

const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const { pngDimensions } = require("./png_dimensions.cjs");

function routeName(route) {
  return route === "/" ? "home" : route.replace(/^\/|\/$/g, "").replace(/\//g, "_");
}

const longPageCaptureThreshold = 16_000;

async function captureOriginalViewportSegments(page, route, viewport, screenshotDir) {
  const documentHeight = await page.evaluate(() => Math.max(document.body.scrollHeight, document.documentElement.scrollHeight));
  const maximumScroll = Math.max(0, documentHeight - viewport.height);
  // Overlap keeps content obscured by the sticky header visible in an adjacent
  // original viewport. Each PNG comes directly from Chrome, without stitching.
  const step = viewport.height - 128;
  const positions = [];
  for (let y = 0; y < maximumScroll; y += step) positions.push(y);
  positions.push(maximumScroll);
  const segments = [];
  for (const [index, requestedScrollY] of positions.entries()) {
    await page.evaluate((y) => window.scrollTo(0, y), requestedScrollY);
    await page.waitForTimeout(100);
    await page.evaluate(() => Promise.all([...document.images]
      .filter((image) => {
        const box = image.getBoundingClientRect();
        return box.bottom > 0 && box.top < window.innerHeight;
      }).map((image) => image.decode())));
    const scroll = await page.evaluate(() => ({ x: window.scrollX, y: window.scrollY }));
    const target = path.join(screenshotDir,
      `${routeName(route)}_${viewport.name}_segment-${String(index + 1).padStart(3, "0")}_y${scroll.y}.png`);
    await page.screenshot({ path: target, fullPage: false });
    const png = fs.readFileSync(target);
    const { width, height } = pngDimensions(png, target);
    if (width !== viewport.width || height !== viewport.height) throw new Error(`Viewport PNG dimensions differ: ${target}`);
    segments.push({ path: target, sha256: crypto.createHash("sha256").update(png).digest("hex"),
      captureKind: "original_browser_viewport", fullPage: false, width, height,
      requestedScrollY, scrollX: scroll.x, scrollY: scroll.y,
      visibleDocumentInterval: [scroll.y, Math.min(documentHeight, scroll.y + height)] });
  }
  await page.evaluate(() => window.scrollTo(0, 0));
  const finalDocumentHeight = await page.evaluate(() => Math.max(document.body.scrollHeight, document.documentElement.scrollHeight));
  if (finalDocumentHeight !== documentHeight) throw new Error(`Document changed height during viewport capture: ${route}`);
  return { documentHeight, threshold: longPageCaptureThreshold, overlap: 128,
    originalPixelsOnly: true, stitched: false, segments };
}

module.exports = { routeName, longPageCaptureThreshold, captureOriginalViewportSegments };
