#!/usr/bin/env node
import { mkdir, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join, resolve } from 'node:path';

const [targetUrl, evidenceDirArgument] = process.argv.slice(2);

if (!targetUrl || !evidenceDirArgument) {
  console.error('usage: admin_pwa_browser_qa.mjs <url> <evidence-dir>');
  process.exit(2);
}

const evidenceDir = resolve(evidenceDirArgument);
const screenshotDir = join(evidenceDir, 'screenshots');
const playwrightCandidates = [
  process.env.PLAYWRIGHT_CORE_PATH,
  '/Volumes/PRO-G40/Temp/caches/npm/_npx/705bc6b22212b352/node_modules/playwright-core/index.js',
  '/Volumes/PRO-G40/X CPA/firmos/node_modules/playwright-core/index.js',
].filter(Boolean);
const chromeCandidates = [
  process.env.ADMIN_PWA_CHROME,
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/Applications/Chromium.app/Contents/MacOS/Chromium',
].filter(Boolean);
const allViewports = [
  { name: 'compact_390x844', width: 390, height: 844, compact: true },
  { name: 'tablet_834x1194', width: 834, height: 1194, compact: true },
  { name: 'desktop_1440x900', width: 1440, height: 900, compact: false },
];
const allRoutes = [
  {
    path: '/admin/login',
    expectsNavigation: false,
    minimumSemanticsCount: 8,
    minimumAccessibilityNodes: 8,
    minimumKeyboardStops: 1,
    requiredLabels: [
      'WhatsApp phone\nRW',
      '+250 7XX XXX XXX',
      'Send admin WhatsApp OTP',
    ],
    requiredInteractiveNames: ['+250 7XX XXX XXX', 'Send WhatsApp OTP'],
  },
  {
    path: '/admin/denied',
    expectsNavigation: false,
    minimumSemanticsCount: 8,
    minimumAccessibilityNodes: 8,
    minimumKeyboardStops: 1,
    requiredLabels: [
      'Admin access recovery actions',
    ],
    requiredInteractiveNames: ['Return to operations', 'Admin sign-in'],
  },
  {
    path: '/admin',
    requiredLabels: [
      'Collect admin workspace',
      'Overview admin section',
    ],
  },
  {
    path: '/admin/groups',
    requiredLabels: [
      'Collect admin workspace',
      'Search',
      'Admin records table, 25 rows',
    ],
  },
  {
    path: '/admin/groups/collection-1',
    requiredLabels: [
      'Collect admin workspace',
      'Groups admin section',
      'Group operations profile detail panel',
    ],
  },
  {
    path: '/admin/members',
    requiredLabels: [
      'Collect admin workspace',
      'Members admin section',
      'Search',
      'Admin records table, 25 rows',
    ],
  },
  {
    path: '/admin/members/user-1',
    requiredLabels: [
      'Collect admin workspace',
      'Members admin section',
      'Member support profile detail panel',
    ],
  },
  {
    path: '/admin/payment-intents',
    requiredLabels: [
      'Collect admin workspace',
      'Payment intents admin section',
      'Search',
      'Admin records table, 25 rows',
    ],
  },
  {
    path: '/admin/payment-intents/admin-row-1',
    requiredLabels: [
      'Collect admin workspace',
      'Payment intents admin section',
      'Payment intent review detail panel',
    ],
  },
  {
    path: '/admin/payment-events',
    requiredLabels: [
      'Collect admin workspace',
      'Search',
      'Admin records table, 25 rows',
    ],
  },
  {
    path: '/admin/payment-events/event-1',
    requiredLabels: [
      'Collect admin workspace',
      'SMS parsing admin section',
      'SMS payment event review detail panel',
    ],
  },
  {
    path: '/admin/allocations',
    requiredLabels: [
      'Collect admin workspace',
      'Allocations admin section',
      'Search',
      'Admin records table, 25 rows',
    ],
  },
  {
    path: '/admin/exceptions',
    requiredLabels: [
      'Collect admin workspace',
      'Exceptions admin section',
      'Search',
      'Admin records table, 25 rows',
    ],
  },
  {
    path: '/admin/ledger',
    requiredLabels: [
      'Collect admin workspace',
      'Ledger admin section',
      'Search',
      'Admin records table, 25 rows',
    ],
  },
  {
    path: '/admin/receivers',
    requiredLabels: [
      'Collect admin workspace',
      'Receivers admin section',
      'Search',
      'Admin records table, 25 rows',
    ],
  },
  {
    path: '/admin/receivers/receiver-1',
    requiredLabels: [
      'Collect admin workspace',
      'Receivers admin section',
      'Receiver route review detail panel',
    ],
  },
  {
    path: '/admin/sms',
    requiredLabels: [
      'Collect admin workspace',
      'SMS admin section',
      'Search',
      'Admin records table, 25 rows',
    ],
  },
  {
    path: '/admin/sms/sms-1',
    requiredLabels: [
      'Collect admin workspace',
      'SMS admin section',
      'SMS metadata review detail panel',
    ],
  },
  {
    path: '/admin/audit-logs',
    requiredLabels: [
      'Collect admin workspace',
      'Audit logs admin section',
      'Search',
      'Admin records table, 25 rows',
    ],
  },
  {
    path: '/admin/settings',
    requiredLabels: [
      'Collect admin workspace',
      'Settings admin section',
      'Search',
      'Admin records table, 25 rows',
    ],
  },
  {
    path: '/admin/feature-flags',
    requiredLabels: [
      'Collect admin workspace',
      'Feature flags admin section',
      'Search',
      'Admin records table, 25 rows',
    ],
  },
  {
    path: '/admin/system-health',
    requiredLabels: [
      'Collect admin workspace',
      'System health admin section',
      'System health detail panel',
    ],
  },
  {
    path: '/admin/admin-users',
    requiredLabels: [
      'Collect admin workspace',
      'Admin users admin section',
      'Search',
      'Admin records table, 25 rows',
    ],
  },
];
const viewports = process.env.ADMIN_PWA_BROWSER_QA_VIEWPORT
  ? allViewports.filter(
      ({ name }) => name === process.env.ADMIN_PWA_BROWSER_QA_VIEWPORT,
    )
  : allViewports;
const routes = process.env.ADMIN_PWA_BROWSER_QA_ROUTE
  ? allRoutes.filter(
      ({ path }) => path === process.env.ADMIN_PWA_BROWSER_QA_ROUTE,
    )
  : allRoutes;
if (viewports.length === 0 || routes.length === 0) {
  throw new Error('Admin browser QA route or viewport filter matched nothing.');
}
const interactiveRoles = new Set([
  'button',
  'checkbox',
  'combobox',
  'link',
  'menuitem',
  'radio',
  'searchbox',
  'slider',
  'switch',
  'tab',
  'textbox',
]);

function findExisting(candidates, label) {
  const value = candidates.find((candidate) => existsSync(candidate));
  if (!value) {
    throw new Error(`No usable ${label} found. Checked: ${candidates.join(', ')}`);
  }
  return value;
}

async function loadPlaywright() {
  const modulePath = findExisting(
    playwrightCandidates,
    'playwright-core module',
  );
  const loaded = await import(`file://${modulePath}`);
  return { modulePath, playwright: loaded.default || loaded };
}

function routeName(path) {
  return path === '/admin'
    ? 'overview'
    : path.replace(/^\/|\/$/g, '').replaceAll('/', '_');
}

async function enableFlutterSemantics(page) {
  await page.waitForFunction(
    () =>
      document.querySelector('flt-semantics-placeholder') ||
      document.querySelectorAll('flt-semantics').length > 0,
    null,
    { timeout: 15_000 },
  );
  await page.evaluate(() => {
    const placeholder = document.querySelector('flt-semantics-placeholder');
    placeholder?.dispatchEvent(new MouseEvent('click', { bubbles: true }));
  });
  await page.waitForFunction(
    () => document.querySelectorAll('flt-semantics').length > 5,
    null,
    { timeout: 15_000 },
  );
}

async function accessibilitySnapshot(page) {
  const session = await page.context().newCDPSession(page);
  try {
    await session.send('Accessibility.enable');
    const { nodes } = await session.send('Accessibility.getFullAXTree');
    const exposed = nodes.filter((node) => !node.ignored);
    const interactive = exposed.filter((node) =>
      interactiveRoles.has(node.role?.value),
    );
    const focusableInteractive = interactive.filter((node) =>
      (node.properties || []).some(
        (property) =>
          property.name === 'focusable' && property.value?.value === true,
      ),
    );
    return {
      exposedNodeCount: exposed.length,
      interactiveNodeCount: interactive.length,
      focusableInteractiveNodeCount: focusableInteractive.length,
      focusableInteractiveNodes: focusableInteractive.map((node) => ({
        name: (node.name?.value || '').trim(),
        role: node.role?.value || '',
      })),
      unnamedInteractiveNodes: focusableInteractive
        .filter((node) => !(node.name?.value || '').trim())
        .map((node) => ({
          role: node.role?.value || '',
          nodeId: node.nodeId,
        })),
    };
  } finally {
    await session.detach();
  }
}

async function interactiveTargetSnapshot(page) {
  return page.evaluate(() => {
    const targetRoles = new Set([
      'button',
      'checkbox',
      'combobox',
      'link',
      'menuitem',
      'radio',
      'searchbox',
      'slider',
      'switch',
      'tab',
      'textbox',
    ]);
    const minimumCssPixels = 44;
    const seen = new Set();
    const targets = [];
    for (const element of document.querySelectorAll(
      'flt-semantics[role], input, textarea, select, button',
    )) {
      if (!(element instanceof HTMLElement)) continue;
      const role =
        element.getAttribute('role') ||
        (element instanceof HTMLInputElement
          ? element.type === 'checkbox'
            ? 'checkbox'
            : 'textbox'
          : element.tagName.toLowerCase());
      if (!targetRoles.has(role)) continue;
      if (element.getAttribute('aria-disabled') === 'true') continue;
      const rect = element.getBoundingClientRect();
      if (
        rect.width <= 0 ||
        rect.height <= 0 ||
        rect.right <= 0 ||
        rect.bottom <= 0 ||
        rect.left >= window.innerWidth ||
        rect.top >= window.innerHeight
      ) {
        continue;
      }
      const name = (
        element.getAttribute('aria-label') ||
        element.textContent?.trim() ||
        element.getAttribute('placeholder') ||
        ''
      ).replace(/\s+/g, ' ');
      const record = {
        name: name.slice(0, 160),
        role,
        width: Number(rect.width.toFixed(2)),
        height: Number(rect.height.toFixed(2)),
        touchesViewportEdge:
          rect.left <= 0.5 ||
          rect.top <= 0.5 ||
          rect.right >= window.innerWidth - 0.5 ||
          rect.bottom >= window.innerHeight - 0.5,
      };
      const key = `${record.role}|${record.name}|${record.width}|${record.height}`;
      if (seen.has(key)) continue;
      seen.add(key);
      targets.push(record);
    }
    const undersizedTargets = targets.filter(
      (target) =>
        target.width < minimumCssPixels ||
        target.height < minimumCssPixels,
    );
    return {
      minimumCssPixels,
      measuredTargetCount: targets.length,
      targets,
      viewportClippedCandidates: undersizedTargets.filter(
        (target) => target.touchesViewportEdge,
      ),
      violations: undersizedTargets.filter(
        (target) => !target.touchesViewportEdge,
      ),
    };
  });
}

async function keyboardTraversal(page) {
  await page.evaluate(() => {
    if (document.activeElement instanceof HTMLElement) {
      document.activeElement.blur();
    }
  });
  const records = [];
  for (let index = 0; index < 32; index += 1) {
    await page.keyboard.press('Tab');
    const record = await page.evaluate(() => {
      const active = document.activeElement;
      if (!(active instanceof HTMLElement)) return null;
      const namedAncestor = active.closest('flt-semantics[aria-label]');
      const text = active.textContent?.trim() || '';
      const label =
        active.getAttribute('aria-label') ||
        text ||
        namedAncestor?.getAttribute('aria-label') ||
        '';
      const role =
        active.getAttribute('role') ||
        namedAncestor?.getAttribute('role') ||
        active.tagName.toLowerCase();
      return {
        label: label.replace(/\s+/g, ' ').slice(0, 160),
        role,
        tag: active.tagName.toLowerCase(),
      };
    });
    if (record?.label && record.tag !== 'flutter-view') records.push(record);
  }
  return records;
}

async function focusSemanticControl(page, { label, labelPrefix, textPrefix }) {
  return page.evaluate(
    ({ expectedLabel, expectedLabelPrefix, expectedTextPrefix }) => {
      const accessibleName = (element) =>
        (
          element.getAttribute('aria-label') ||
          element.textContent?.trim() ||
          ''
        ).replace(/\s+/g, ' ');
      const focusableSelector =
        '[tabindex="0"], input, textarea, select, button';
      const candidates = [
        ...document.querySelectorAll(
          'flt-semantics, input, textarea, select, button',
        ),
      ];
      const preferredMatch = (predicate) => {
        const matches = candidates.filter(predicate);
        return (
          matches.find((element) => element.matches(focusableSelector)) ||
          matches.find((element) => element.closest(focusableSelector)) ||
          matches[0]
        );
      };
      const wrapper =
        (expectedLabel
          ? preferredMatch(
              (element) => accessibleName(element) === expectedLabel,
            )
          : null) ||
        (expectedLabelPrefix
          ? preferredMatch((element) =>
              accessibleName(element).startsWith(expectedLabelPrefix),
            )
          : null) ||
        (expectedTextPrefix
          ? preferredMatch(
              (element) =>
                (element.textContent?.trim() || '').startsWith(
                  expectedTextPrefix,
                ) &&
                (element.matches(
                  '[tabindex="0"], input, textarea, select, button',
                ) ||
                  [
                    'button',
                    'checkbox',
                    'combobox',
                    'link',
                    'radio',
                    'switch',
                  ].includes(element.getAttribute('role') || '')),
            ) ||
            preferredMatch((element) =>
              (element.textContent?.trim() || '').startsWith(
                expectedTextPrefix,
              ),
            )
          : null);
      if (!(wrapper instanceof HTMLElement)) return false;
      const target =
        (wrapper.matches(focusableSelector)
          ? wrapper
          : wrapper.querySelector(focusableSelector)) ||
        wrapper.closest(focusableSelector) ||
        wrapper;
      if (!(target instanceof HTMLElement)) return false;
      target.focus();
      return document.activeElement === target;
    },
    {
      expectedLabel: label || '',
      expectedLabelPrefix: labelPrefix || '',
      expectedTextPrefix: textPrefix || '',
    },
  );
}

async function keyboardActivateGroupsNavigation(page) {
  const prepared = await focusSemanticControl(page, {
    label: 'Groups admin section',
  });
  if (!prepared) return false;
  await page.keyboard.press('Enter');
  try {
    await page.waitForFunction(
      () => location.hash === '#/admin/groups',
      null,
      { timeout: 5_000 },
    );
    return true;
  } catch (_) {
    return false;
  }
}

async function keyboardOpenFirstGroupRecord(page) {
  const prepared = await focusSemanticControl(page, {
    labelPrefix: 'Open Public group',
    textPrefix: 'Open Public group',
  });
  if (!prepared) return false;
  await page.keyboard.press('Enter');
  try {
    await page.waitForFunction(
      () => /^#\/admin\/groups\/collection-\d+$/.test(location.hash),
      null,
      { timeout: 5_000 },
    );
    return true;
  } catch (_) {
    return false;
  }
}

async function keyboardExerciseReasonDialog(page) {
  const prepared = await focusSemanticControl(page, {
    labelPrefix: 'Request SMS reparse for',
    textPrefix: 'Request SMS reparse for',
  });
  if (!prepared) return false;
  await page.keyboard.press('Enter');
  const reasonInput = page.locator('input[aria-label="Reason"], textarea[aria-label="Reason"]');
  try {
    await reasonInput.waitFor({ state: 'attached', timeout: 5_000 });
    await reasonInput.fill('Browser keyboard QA');
  } catch (_) {
    return false;
  }
  const cancelPrepared = await focusSemanticControl(page, {
    textPrefix: 'Cancel',
  });
  if (!cancelPrepared) return false;
  await page.keyboard.press('Enter');
  try {
    await reasonInput.waitFor({ state: 'detached', timeout: 5_000 });
    return page.evaluate(() => {
      const active = document.activeElement;
      if (!(active instanceof HTMLElement)) return false;
      const namedAncestor = active.closest('flt-semantics[aria-label]');
      const label =
        active.getAttribute('aria-label') ||
        namedAncestor?.getAttribute('aria-label') ||
        active.textContent?.trim() ||
        '';
      return label.startsWith('Request SMS reparse for');
    });
  } catch (_) {
    return false;
  }
}

async function keyboardExportCurrentPage(page) {
  const searchInput = page.locator('input:not([disabled])').first();
  try {
    await searchInput.waitFor({ state: 'attached', timeout: 5_000 });
    await searchInput.fill('Public group 30');
    await searchInput.press('Enter');
    await page.waitForFunction(
      () =>
        [...document.querySelectorAll('[aria-label]')].some(
          (element) =>
            element.getAttribute('aria-label') ===
            'Admin records table, 1 rows',
        ),
      null,
      { timeout: 5_000 },
    );
  } catch (error) {
    return {
      passed: false,
      stage: 'export-filter-unavailable',
      error: String(error),
    };
  }
  await page.evaluate(() => {
    if (document.activeElement instanceof HTMLElement) {
      document.activeElement.blur();
    }
  });
  let prepared = false;
  let preparedLabel = '';
  const viewport = page.viewportSize();
  if (viewport) {
    await page.mouse.move(viewport.width * 0.8, viewport.height * 0.72);
    for (let attempt = 0; attempt < 8 && !prepared; attempt += 1) {
      await page.mouse.wheel(0, 700);
      await page.waitForTimeout(180);
      prepared = await focusSemanticControl(page, {
        label: 'Export Groups current page CSV',
        textPrefix: 'Export CSV',
      });
    }
  }
  for (let attempt = 0; attempt < 120 && !prepared; attempt += 1) {
    await page.keyboard.press('Tab');
    preparedLabel = await page.evaluate(() => {
      const active = document.activeElement;
      if (!(active instanceof HTMLElement)) return '';
      const namedAncestor = active.closest('flt-semantics[aria-label]');
      return (
        active.getAttribute('aria-label') ||
        active.textContent?.trim() ||
        namedAncestor?.getAttribute('aria-label') ||
        ''
      ).replace(/\s+/g, ' ');
    });
    prepared =
      preparedLabel === 'Export Groups current page CSV' ||
      preparedLabel.startsWith('Export CSV');
  }
  if (!prepared) {
    return {
      passed: false,
      stage: 'export-action-unavailable',
      preparedLabel,
    };
  }
  await page.keyboard.press('Enter');
  try {
    await page.waitForFunction(
      () =>
        [...document.querySelectorAll('flt-semantics')].some((element) => {
          const exposed =
            element.getAttribute('aria-label') ||
            element.textContent ||
            '';
          return exposed.includes('Groups CSV copied for export');
        }),
      null,
      { timeout: 5_000 },
    );
    const state = await page.evaluate(() => {
      const active = document.activeElement;
      if (!(active instanceof HTMLElement)) {
        return { focusLabel: '', feedback: [] };
      }
      const namedAncestor = active.closest('flt-semantics[aria-label]');
      const label =
        active.getAttribute('aria-label') ||
        namedAncestor?.getAttribute('aria-label') ||
        active.textContent?.trim() ||
        '';
      const feedback = [...document.querySelectorAll('flt-semantics')]
        .map(
          (element) =>
            element.getAttribute('aria-label') ||
            element.textContent?.trim() ||
            '',
        )
        .filter((value) => value.includes('Groups CSV copied for export'));
      return { focusLabel: label, feedback };
    });
    const focusRetained =
      state.focusLabel === 'Export Groups current page CSV' ||
      state.focusLabel.startsWith('Export CSV');
    return {
      passed: focusRetained,
      stage: focusRetained
        ? 'exported-and-focus-retained'
        : 'exported-without-focus-retention',
      state,
    };
  } catch (error) {
    const state = await page.evaluate(() => ({
      labels: [...document.querySelectorAll('[aria-label]')]
        .map((element) => element.getAttribute('aria-label') || '')
        .filter(Boolean),
      text: document.body.textContent?.replace(/\s+/g, ' ').slice(0, 4000) || '',
    }));
    return {
      passed: false,
      stage: 'export-feedback-timeout',
      state,
      error: String(error),
    };
  }
}

async function keyboardActivateDeniedRecovery(page) {
  const prepared = await focusSemanticControl(page, {
    label: 'Return to operations',
    textPrefix: 'Return to operations',
  });
  if (!prepared) return false;
  await page.keyboard.press('Enter');
  try {
    await page.waitForFunction(
      () => location.hash === '#/admin',
      null,
      { timeout: 5_000 },
    );
    return true;
  } catch (_) {
    return false;
  }
}

async function keyboardActivateDeniedSignIn(page) {
  const prepared = await focusSemanticControl(page, {
    label: 'Admin sign-in',
    textPrefix: 'Admin sign-in',
  });
  if (!prepared) return false;
  await page.keyboard.press('Enter');
  try {
    await page.waitForFunction(
      () => location.hash === '#/admin/login',
      null,
      { timeout: 5_000 },
    );
    return true;
  } catch (_) {
    return false;
  }
}

async function keyboardAdvanceAdminLogin(page) {
  const phoneInput = page.locator(
    'input[aria-label="+250 7XX XXX XXX"], input[aria-label="WhatsApp phone"]',
  );
  try {
    await phoneInput.waitFor({ state: 'attached', timeout: 5_000 });
    await phoneInput.fill('+250 788 000 001');
  } catch (_) {
    return false;
  }
  const prepared = await focusSemanticControl(page, {
    label: 'Send admin WhatsApp OTP',
    textPrefix: 'Send WhatsApp OTP',
  });
  if (!prepared) return false;
  await page.keyboard.press('Enter');
  try {
    await page.waitForFunction(
      () =>
        [...document.querySelectorAll('[aria-label]')].some((element) =>
          (element.getAttribute('aria-label') || '').startsWith('OTP code'),
        ),
      null,
      { timeout: 5_000 },
    );
    return true;
  } catch (_) {
    return false;
  }
}

async function resetForKeyboardInteraction(page, url) {
  await page.goto(url, {
    waitUntil: 'domcontentloaded',
    timeout: 30_000,
  });
  await page.waitForFunction(
    () => document.querySelector('flutter-view'),
    null,
    { timeout: 15_000 },
  );
  await page.waitForTimeout(750);
  await enableFlutterSemantics(page);
}

async function keyboardExerciseSensitiveGate(page) {
  let reasonPrepared = false;
  for (let attempt = 0; attempt < 4 && !reasonPrepared; attempt += 1) {
    reasonPrepared = await focusSemanticControl(page, {
      labelPrefix: 'Compliance investigation',
      textPrefix: 'Compliance investigation',
    });
    if (!reasonPrepared) {
      await page.mouse.wheel(0, 700);
      await page.waitForTimeout(250);
    }
  }
  if (!reasonPrepared) {
    return {
      passed: false,
      stage: 'reveal-reason-unavailable',
    };
  }
  await page.keyboard.press('Space');
  await page.waitForTimeout(100);
  const sensitiveGateState = await page.evaluate(() => {
    const candidates = [...document.querySelectorAll('flt-semantics')];
    const describe = (element) =>
      element
        ? {
            label: element.getAttribute('aria-label') || '',
            role: element.getAttribute('role') || '',
            disabled: element.getAttribute('aria-disabled') || '',
            checked: element.getAttribute('aria-checked') || '',
            selected: element.getAttribute('aria-selected') || '',
            text: element.textContent?.trim().replace(/\s+/g, ' ') || '',
          }
        : null;
    return {
      reason: describe(
        candidates.find(
          (element) =>
            (element.getAttribute('aria-label') || '').startsWith(
              'Compliance investigation',
            ) ||
            (element.textContent?.trim() || '').startsWith(
              'Compliance investigation',
            ),
        ),
      ),
      reveal: describe(
        candidates.find(
          (element) =>
            element.getAttribute('aria-label') === 'Reveal raw SMS' ||
            (element.textContent?.trim() || '').startsWith('Reveal raw SMS'),
        ),
      ),
    };
  });

  const revealPrepared = await focusSemanticControl(page, {
    label: 'Reveal raw SMS',
    textPrefix: 'Reveal raw SMS',
  });
  if (!revealPrepared) {
    return {
      passed: false,
      stage: 'reveal-action-unavailable',
      sensitiveGateState,
    };
  }
  await page.keyboard.press('Space');
  try {
    await page.waitForFunction(
      () =>
        Boolean(
          [
            ...document.querySelectorAll('[aria-label]'),
          ].find((element) =>
            (element.getAttribute('aria-label') || '').includes(
              'Sensitive data revealed. Raw message hidden in route evidence.',
            ),
          ),
        ),
      null,
      { timeout: 5_000 },
    );
    return {
      passed: true,
      stage: 'revealed',
      sensitiveGateState,
    };
  } catch (error) {
    const revealedLabels = await page.evaluate(() =>
      [...document.querySelectorAll('[aria-label]')]
        .map((element) => element.getAttribute('aria-label') || '')
        .filter((label) => label.includes('Sensitive data revealed')),
    );
    return {
      passed: false,
      stage: 'reveal-result-timeout',
      sensitiveGateState,
      revealedLabels,
      error: String(error),
    };
  }
}

async function auditRoute(browser, route, viewport) {
  const page = await browser.newPage({
    viewport: { width: viewport.width, height: viewport.height },
    deviceScaleFactor: 1,
  });
  const consoleMessages = [];
  const pageErrors = [];
  page.on('console', (message) => {
    if (['error', 'warning', 'assert'].includes(message.type())) {
      consoleMessages.push({
        type: message.type(),
        text: message.text(),
        url: message.location().url || '',
      });
    }
  });
  page.on('pageerror', (error) => pageErrors.push(error.message));

  try {
    const url = `${targetUrl.replace(/\/$/, '')}/#${route.path}`;
    const response = await page.goto(url, {
      waitUntil: 'domcontentloaded',
      timeout: 30_000,
    });
    await page.waitForFunction(
      () => document.querySelector('flutter-view'),
      null,
      { timeout: 15_000 },
    );
    await page.waitForTimeout(750);
    await enableFlutterSemantics(page);

    const browserState = await page.evaluate(() => {
      const labels = [
        ...document.querySelectorAll('[aria-label]'),
      ].map((element) => element.getAttribute('aria-label') || '');
      const accessibleLabels = [
        ...new Set([
          ...labels,
          ...[...document.querySelectorAll('flt-semantics')]
            .map((element) =>
              (
                element.getAttribute('aria-label') ||
                element.textContent?.trim() ||
                ''
              ).replace(/\s+/g, ' '),
            )
            .filter(Boolean),
        ]),
      ];
      const flutterView = document.querySelector('flutter-view');
      const flutterViewRect = flutterView?.getBoundingClientRect();
      return {
        hash: location.hash,
        labels,
        accessibleLabels,
        documentScrollWidth: document.documentElement.scrollWidth,
        bodyScrollWidth: document.body.scrollWidth,
        viewportWidth: window.innerWidth,
        flutterViewWidth: flutterViewRect?.width || 0,
        semanticsCount: document.querySelectorAll('flt-semantics').length,
        placeholderPresent: Boolean(
          document.querySelector('flt-semantics-placeholder'),
        ),
      };
    });
    const accessibility = await accessibilitySnapshot(page);
    const interactiveTargets = await interactiveTargetSnapshot(page);
    const focusRecords = await keyboardTraversal(page);
    const focusLabels = [...new Set(focusRecords.map((item) => item.label))];
    const expectedNavigationLabel = viewport.width < 720
      ? 'Collect admin mobile navigation'
      : 'Collect admin primary navigation';
    const screenshotPath = join(
      screenshotDir,
      `${routeName(route.path)}_${viewport.name}.png`,
    );
    await page.screenshot({ path: screenshotPath, fullPage: false });

    const checks = {
      httpOk: Boolean(
        response && response.status() >= 200 && response.status() < 300,
      ),
      routeResolved: browserState.hash === `#${route.path}`,
      semanticsEnabled:
        !browserState.placeholderPresent &&
        browserState.semanticsCount > (route.minimumSemanticsCount ?? 20),
      requiredLabelsPresent: route.requiredLabels.every((label) =>
        browserState.accessibleLabels.includes(label),
      ),
      responsiveNavigationPresent:
        route.expectsNavigation === false
          ? !browserState.accessibleLabels.includes(
              'Collect admin mobile navigation',
            ) &&
            !browserState.accessibleLabels.includes(
              'Collect admin primary navigation',
            )
          : browserState.accessibleLabels.includes(expectedNavigationLabel),
      noDocumentHorizontalOverflow:
        browserState.documentScrollWidth <= browserState.viewportWidth + 1 &&
        browserState.flutterViewWidth <= browserState.viewportWidth + 1,
      accessibilityTreeExposed:
        accessibility.exposedNodeCount >
        (route.minimumAccessibilityNodes ?? 20),
      interactiveControlsNamed:
        accessibility.focusableInteractiveNodeCount > 0 &&
        accessibility.unnamedInteractiveNodes.length === 0,
      requiredInteractiveNamesPresent:
        !route.requiredInteractiveNames ||
        route.requiredInteractiveNames.every((name) =>
          accessibility.focusableInteractiveNodes.some(
            (node) => node.name === name,
          ),
        ),
      interactiveTargetsMeasured:
        interactiveTargets.measuredTargetCount > 0,
      interactiveTargetsMeetMinimum:
        interactiveTargets.violations.length === 0,
      keyboardTraversal:
        focusLabels.length >= (route.minimumKeyboardStops ?? 2),
      noBrowserErrors:
        consoleMessages.length === 0 && pageErrors.length === 0,
    };

    let keyboardGroupsNavigation = null;
    if (route.path === '/admin' && !viewport.compact) {
      await resetForKeyboardInteraction(page, url);
      keyboardGroupsNavigation = await keyboardActivateGroupsNavigation(page);
      checks.keyboardActivatesNavigation = keyboardGroupsNavigation;
    }
    let keyboardOpensTableRecord = null;
    if (route.path === '/admin/groups') {
      await resetForKeyboardInteraction(page, url);
      keyboardOpensTableRecord = await keyboardOpenFirstGroupRecord(page);
      checks.keyboardOpensTableRecord = keyboardOpensTableRecord;
    }
    let keyboardExportsCurrentPage = null;
    if (route.path === '/admin/groups') {
      await resetForKeyboardInteraction(page, url);
      keyboardExportsCurrentPage = await keyboardExportCurrentPage(page);
      checks.keyboardExportsCurrentPage = keyboardExportsCurrentPage.passed;
    }
    let keyboardReasonDialog = null;
    if (route.path === '/admin/payment-events') {
      await resetForKeyboardInteraction(page, url);
      keyboardReasonDialog = await keyboardExerciseReasonDialog(page);
      checks.keyboardReasonDialog = keyboardReasonDialog;
    }
    let keyboardSensitiveGate = null;
    if (route.path === '/admin/sms/sms-1') {
      await resetForKeyboardInteraction(page, url);
      keyboardSensitiveGate = await keyboardExerciseSensitiveGate(page);
      checks.keyboardSensitiveGate = keyboardSensitiveGate.passed;
    }
    let keyboardDeniedRecovery = null;
    if (route.path === '/admin/denied') {
      await resetForKeyboardInteraction(page, url);
      keyboardDeniedRecovery = await keyboardActivateDeniedRecovery(page);
      checks.keyboardDeniedRecovery = keyboardDeniedRecovery;
    }
    let keyboardDeniedSignIn = null;
    if (route.path === '/admin/denied') {
      await resetForKeyboardInteraction(page, url);
      keyboardDeniedSignIn = await keyboardActivateDeniedSignIn(page);
      checks.keyboardDeniedSignIn = keyboardDeniedSignIn;
    }
    let keyboardAdvancesAdminLogin = null;
    if (route.path === '/admin/login') {
      await resetForKeyboardInteraction(page, url);
      keyboardAdvancesAdminLogin = await keyboardAdvanceAdminLogin(page);
      checks.keyboardAdvancesAdminLogin = keyboardAdvancesAdminLogin;
    }

    return {
      route: route.path,
      viewport: viewport.name,
      url,
      screenshotPath,
      checks,
      failures: Object.entries(checks)
        .filter(([, passed]) => !passed)
        .map(([name]) => name),
      browserState: {
        ...browserState,
        labels: browserState.labels.filter(Boolean),
      },
      accessibility,
      interactiveTargets,
      focusRecords,
      focusLabels,
      keyboardGroupsNavigation,
      keyboardOpensTableRecord,
      keyboardExportsCurrentPage,
      keyboardReasonDialog,
      keyboardSensitiveGate,
      keyboardDeniedRecovery,
      keyboardDeniedSignIn,
      keyboardAdvancesAdminLogin,
      consoleMessages,
      pageErrors,
    };
  } finally {
    await page.close();
  }
}

await mkdir(screenshotDir, { recursive: true });
const { modulePath, playwright } = await loadPlaywright();
const executablePath = findExisting(chromeCandidates, 'Chrome executable');
const browser = await playwright.chromium.launch({
  executablePath,
  headless: true,
});
const results = [];
try {
  for (const viewport of viewports) {
    for (const route of routes) {
      results.push(await auditRoute(browser, route, viewport));
    }
  }
} finally {
  await browser.close();
}

const failures = results.flatMap((result) =>
  result.failures.map(
    (failure) => `${result.route} ${result.viewport}: ${failure}`,
  ),
);
const report = {
  status: failures.length === 0 ? 'pass' : 'fail',
  generatedAt: new Date().toISOString(),
  targetUrl,
  playwrightCore: modulePath,
  executablePath,
  routeCount: routes.length,
  viewportCount: viewports.length,
  screenshotCount: results.length,
  privacy:
    'Admin evidence mode uses deterministic masked test data only. No production session, service-role key, raw SMS body, OTP, PIN, real phone, or customer data is captured.',
  failures,
  results,
};
const reportPath = join(evidenceDir, 'admin_browser_qa.json');
await writeFile(reportPath, `${JSON.stringify(report, null, 2)}\n`);
console.log(
  JSON.stringify(
    {
      status: report.status,
      reportPath,
      routeCount: report.routeCount,
      viewportCount: report.viewportCount,
      screenshotCount: report.screenshotCount,
      failures,
    },
    null,
    2,
  ),
);
process.exit(report.status === 'pass' ? 0 : 1);
