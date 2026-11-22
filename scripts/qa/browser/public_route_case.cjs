"use strict";

const path = require("node:path");
const { routeName, longPageCaptureThreshold, captureOriginalViewportSegments } = require("./viewport_segments.cjs");
const { observePageErrors, readKeyboardFocus, hasVisibleKeyboardFocus, openRenderedRoute, failedChecks } = require("./rendered_page_evidence.cjs");

const legalRoutes = new Set(["/privacy/", "/terms/", "/account-deletion/", "/data-deletion/"]);

async function auditRoute(page, route, viewport, { baseUrl, screenshotDir, capabilityContract }) {
  const { consoleMessages, pageErrors } = observePageErrors(page, { includeSourceUrl: true });
  const url = new URL(route, baseUrl).toString();
  const response = await openRenderedRoute(page, url);
  await page.waitForTimeout(150);

  const keyboardFocus = await readKeyboardFocus(page, 8, true);
  await page.evaluate(() => document.activeElement && document.activeElement.blur && document.activeElement.blur());

  let menuScreenshot = null;
  let mobileMenuOpen = true;
  let menuFocusContained = true;
  let menuEscapeRecovery = true;
  const usesMenu = viewport.width <= 1100;
  if (usesMenu) {
    await page.locator("[data-menu-button]").click({ timeout: 5_000 });
    await page.waitForTimeout(100);
    mobileMenuOpen = await page.locator("[data-site-nav]").evaluate((node) => node.classList.contains("open"));
    menuScreenshot = path.join(screenshotDir, `${routeName(route)}_${viewport.name}_menu.png`);
    await page.screenshot({ path: menuScreenshot, fullPage: false });
    menuFocusContained = await page.evaluate(() =>
      document.querySelector("[data-site-nav]").contains(document.activeElement) &&
      document.querySelector("main").inert &&
      document.querySelector("[data-menu-button]").getAttribute("aria-expanded") === "true"
    );
    const lastControl = page.locator("[data-site-nav] a[href], [data-site-nav] button").last();
    await lastControl.focus();
    await page.keyboard.press("Tab");
    menuFocusContained = menuFocusContained && await page.evaluate(() =>
      document.activeElement === document.querySelector("[data-menu-button]")
    );
    await page.keyboard.press("Shift+Tab");
    menuFocusContained = menuFocusContained && await lastControl.evaluate((node) => node === document.activeElement);
    await page.keyboard.press("Escape");
    menuEscapeRecovery = await page.evaluate(() =>
      !document.querySelector("[data-site-nav]").classList.contains("open") &&
      !document.querySelector("main").inert &&
      document.querySelector("[data-menu-button]").getAttribute("aria-expanded") === "false" &&
      document.activeElement === document.querySelector("[data-menu-button]")
    );
  }

  const screenshot = path.join(screenshotDir, `${routeName(route)}_${viewport.name}.png`);
  // Keyboard traversal can scroll deep into the page. A hero comparison must
  // capture the same initial scroll state as the source.
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.screenshot({ path: screenshot, fullPage: false });
  const documentHeight = await page.evaluate(() => Math.max(document.body.scrollHeight, document.documentElement.scrollHeight));
  let fullPageScreenshot = null;
  let longPageCapture = null;
  if (documentHeight > longPageCaptureThreshold) {
    longPageCapture = await captureOriginalViewportSegments(page, route, viewport, screenshotDir);
  } else {
    fullPageScreenshot = path.join(screenshotDir, `${routeName(route)}_${viewport.name}_full.png`);
    await page.screenshot({ path: fullPageScreenshot, fullPage: true });
  }

  const expectedCtas = capabilityContract.routes[route];
  if (!expectedCtas) throw new Error(`Unregistered capability route: ${route}`);
  const metrics = await page.evaluate(({ isLegalRoute, expectedCtas }) => {
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
      headingTextOverflows: [...document.querySelectorAll('h1, h2, h3')].flatMap((heading) => {
        const range = document.createRange();
        range.selectNodeContents(heading);
        const box = heading.getBoundingClientRect();
        const textRects = [...range.getClientRects()];
        const textLeft = Math.min(...textRects.map((rect) => rect.left));
        const textRight = Math.max(...textRects.map((rect) => rect.right));
        // Overflow-clipping ancestors can hide text without increasing the
        // document scroll width, so measure the actual text against its box.
        return textLeft < box.left - 1 || textRight > box.right + 1
          ? [{ text: heading.textContent.trim(), left: box.left, right: box.right, textLeft, textRight }]
          : [];
      }),
      heroDevice: rect(".hero-device, .hero-editorial"),
      heroPhoto: rect(".hero .service-photo img"),
      heroArtworkLoaded: [...document.querySelectorAll('.hero img')].every((image) => image.complete && image.naturalWidth > 0),
      decorativeControlsAbsent: document.querySelectorAll('.phone-shell, .phone-screen, .phone-tabs').length === 0,
      appMediaTruthful: [...document.querySelectorAll('.app-capture')].every((figure) => {
        const image = figure.querySelector('img');
        if (!image || !image.getAttribute('src').startsWith('/assets/app-screens/')) return false;
        const box = image.getBoundingClientRect();
        return image.complete && image.naturalWidth >= 500 &&
          Math.abs(box.width / box.height - image.naturalWidth / image.naturalHeight) < 0.02 &&
          figure.textContent.includes('Example data');
      }),
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
      capabilityActions: Object.fromEntries(["cta-app", "cta-group", "cta-touch"].map((role) => {
        const links = [...document.querySelectorAll(`a.${role}`)];
        const expected = expectedCtas[role];
        return [role, { count: links.length, expected: expected || null,
          matches: expected ? links.length >= 2 && links.every((link) =>
            (link.getAttribute("aria-label") || link.textContent).trim() === expected.label &&
            link.textContent.trim() === expected.label && link.getAttribute("href") === expected.href)
            : links.length === 0,
          actual: links.map((link) => ({ label: link.textContent.trim(), href: link.getAttribute("href") })) }];
      })),
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
      editorialLabelFlow: [...document.querySelectorAll(
        '.story-grid > article > strong, .story-grid > article > h3'
      )].map((label) => ({
        text: label.textContent.trim(),
        display: getComputedStyle(label).display,
        marginBottom: Number.parseFloat(getComputedStyle(label).marginBottom),
      })),
      legalHeadingSpacing: [...document.querySelectorAll('.legal-section > h2')]
        .map((heading) => Number.parseFloat(getComputedStyle(heading).marginBottom)),
      editorialLinkFlow: [...document.querySelectorAll('.story-grid a')]
        .map((link) => {
          const preceding = document.createRange();
          preceding.selectNodeContents(link.parentElement);
          preceding.setEndBefore(link);
          const boxes = [...preceding.getClientRects()]
            .filter((box) => box.width > 0 && box.height > 0);
          const bounds = link.getBoundingClientRect();
          return {
            text: link.textContent.trim(),
            href: link.getAttribute('href'),
            display: getComputedStyle(link).display,
            marginTop: Number.parseFloat(getComputedStyle(link).marginTop),
            height: bounds.height,
            precedingContentGap: boxes.length
              ? bounds.top - Math.max(...boxes.map((box) => box.bottom))
              : null,
          };
        }),
      supportedGroupPadding: [...document.querySelectorAll('.supported-group-card')]
        .map((card) => {
          const style = getComputedStyle(card);
          return ['paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft']
            .map((side) => Number.parseFloat(style[side]));
        }),
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
          contained: cards.every((card) => card.scrollWidth <= card.clientWidth + 1 && card.scrollHeight <= card.clientHeight + 1),
          nonOverlapping: cards.every((card, index) => cards.slice(index + 1).every((other) => {
            const a = card.getBoundingClientRect(), b = other.getBoundingClientRect();
            return a.right <= b.left + 1 || b.right <= a.left + 1 || a.bottom <= b.top + 1 || b.bottom <= a.top + 1;
          })),
        };
      }),
      isLegalRoute,
    };
  }, { isLegalRoute: legalRoutes.has(route), expectedCtas });

  const presentCompactGrids = metrics.compactCardGrids.filter((grid) => grid.present && grid.cardCount >= 3);

  const checks = {
    http200: Boolean(response && response.status() >= 200 && response.status() < 300),
    noConsoleErrors: consoleMessages.length === 0 && pageErrors.length === 0,
    noHorizontalOverflow: Math.max(metrics.bodyScrollWidth, metrics.documentScrollWidth) <= metrics.viewportWidth + 1,
    headingTextFits: metrics.headingTextOverflows.length === 0,
    hasTitleAndH1: metrics.title.length > 0 && metrics.h1.length > 0,
    capabilityActionsPresent: Object.values(metrics.capabilityActions).every((role) => role.matches),
    retiredSectionsAbsent: metrics.retiredSectionsAbsent,
    disclaimerLabelsAbsent: metrics.disclaimerLabelsAbsent,
    routeClassPresent: metrics.bodyClass.includes(`route-${route === "/" ? "home" : routeName(route).replace(/_/g, "-")}`),
    mobileMenuOpens: !usesMenu || mobileMenuOpen,
    responsiveMenuFocusContained: !usesMenu || menuFocusContained,
    responsiveMenuEscapeRecovery: !usesMenu || menuEscapeRecovery,
    mobileHeroVisualUsable: metrics.heroArtworkLoaded && (!viewport.isMobile || (metrics.heroDevice && metrics.heroDevice.top < viewport.height &&
      (metrics.heroPhoto
        ? metrics.heroPhoto.width >= viewport.width - 41 && Math.abs(metrics.heroPhoto.width / metrics.heroPhoto.height - 1.5) < 0.02
        : metrics.heroDevice.height >= 220))),
    decorativeControlsAbsent: metrics.decorativeControlsAbsent,
    appMediaTruthful: metrics.appMediaTruthful,
    editorialLabelsSeparateFromDescriptions: metrics.editorialLabelFlow.every(
      (label) => label.display === 'block' && label.marginBottom >= 12
    ),
    legalHeadingsKeepSectionSpacing: metrics.legalHeadingSpacing.every(
      (spacing) => spacing >= 16
    ),
    editorialLinksKeepOwnRow:
      (route !== '/' || metrics.editorialLinkFlow.length >= 3) &&
      metrics.editorialLinkFlow.every((link) =>
        link.display === 'flex' && link.marginTop >= 12 && link.height >= 44 &&
        (link.precedingContentGap === null || link.precedingContentGap >= 11.5)
      ),
    supportedGroupCardsKeepInsets: metrics.supportedGroupPadding.every(
      (padding) => padding.every((side) => side >= 16)
    ),
    compactCardGridLayout: presentCompactGrids.every((grid) => {
      // The selected Revolut cohort uses neutral editorial panels. Validate
      // readable geometry, not the retired requirement for multicolour tiles.
      return (viewport.isMobile ? grid.columns === 1 : viewport.allowedGridColumns.includes(grid.columns)) &&
        grid.contained && grid.nonOverlapping;
    }),
    legalLayoutPresent: !metrics.isLegalRoute || metrics.legalLayoutPresent,
    footerTapTargets: !viewport.isMobile || metrics.footerRects.every((box) => box.height >= 40),
    keyboardTraversal: keyboardFocus.length >= 5 && keyboardFocus.some((item) => ["Skip to content", "Jya ku bikubiyemo"].includes(item.text)),
    visibleKeyboardFocus: hasVisibleKeyboardFocus(keyboardFocus),
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
    fullPageScreenshot,
    longPageCapture,
    menuScreenshot,
    checks,
    failures: failedChecks(checks),
    metrics,
    keyboardFocus,
    consoleMessages,
    pageErrors,
  };
}

module.exports = { auditRoute };
