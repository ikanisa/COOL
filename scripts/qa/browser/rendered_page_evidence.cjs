"use strict";

function observePageErrors(page, { includeSourceUrl = false } = {}) {
  const consoleMessages = [];
  const pageErrors = [];
  page.on("console", (message) => {
    const type = message.type();
    const text = message.text();
    const url = includeSourceUrl ? message.location().url || "" : "";
    if (!["error", "warning"].includes(type) || /favicon/i.test(`${text} ${url}`)) return;
    consoleMessages.push(includeSourceUrl ? { type, text, url } : { type, text });
  });
  page.on("pageerror", (error) => pageErrors.push(error.message));
  return { consoleMessages, pageErrors };
}

async function readKeyboardFocus(page, count, includeTargetDetails = false) {
  const focus = [];
  for (let index = 0; index < count; index += 1) {
    await page.keyboard.press("Tab");
    const item = await page.evaluate((includeTargetDetails) => {
      const active = document.activeElement;
      if (!active || active === document.body) return null;
      const style = getComputedStyle(active);
      const label = active.getAttribute("aria-label") || active.textContent ||
        (includeTargetDetails ? active.getAttribute("alt") : "") || "";
      return {
        ...(includeTargetDetails ? { tag: active.tagName.toLowerCase() } : {}),
        text: label.trim().replace(/\s+/g, " ").slice(0, 80),
        ...(includeTargetDetails ? { href: active.getAttribute("href") || "" } : {}),
        focusVisible: active.matches(":focus-visible"),
        outlineStyle: style.outlineStyle,
        outlineWidth: style.outlineWidth,
        boxShadow: style.boxShadow,
      };
    }, includeTargetDetails);
    if (item) focus.push(item);
  }
  return focus;
}

function hasVisibleKeyboardFocus(focus) {
  return focus.length >= 5 && focus.every((item) =>
    item.focusVisible && (
      (item.outlineStyle !== "none" && Number.parseFloat(item.outlineWidth) >= 2) ||
      item.boxShadow !== "none"
    ));
}

async function openRenderedRoute(page, url) {
  const response = await page.goto(url, { waitUntil: "domcontentloaded", timeout: 30_000 });
  await page.locator("h1").waitFor({ state: "visible", timeout: 10_000 });
  await page.evaluate(() => document.fonts.ready);
  await page.evaluate(() => Promise.all([...document.querySelectorAll(".hero img")].map(image => image.decode())));
  return response;
}

function failedChecks(checks) {
  return Object.keys(checks).filter((id) => !checks[id]);
}

module.exports = { observePageErrors, readKeyboardFocus, hasVisibleKeyboardFocus, openRenderedRoute, failedChecks };
