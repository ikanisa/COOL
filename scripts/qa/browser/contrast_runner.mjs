import playwrightRunner from './playwright_runner.cjs';

const {launchPlaywright, withPage} = playwrightRunner;

export const contrastBaseUrl = process.env.PUBLIC_CONTRAST_URL || 'http://127.0.0.1:4188';

export async function launchContrastBrowser() {
  const {browser} = await launchPlaywright({
    installedFirst: false,
    moduleCandidates: [
      '/Users/jeanbosco/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright-core/index.js',
    ],
  });
  return browser;
}

export function withContrastPage(browser, width, route, measure) {
  return withPage(browser, {viewport: {width, height: 1000}, deviceScaleFactor: 1}, async (page) => {
    const base = new URL(contrastBaseUrl);
    const address = new URL(route, base);
    if (address.origin !== base.origin) throw new Error('Contrast report contains a route outside the configured origin');
    const response = await page.goto(address.href, {waitUntil: 'networkidle'});
    if (!response?.ok()) throw new Error(`Contrast page did not return a successful response: ${route}`);
    return measure(page);
  });
}
