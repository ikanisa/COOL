#!/usr/bin/env node
// Conservative contrast check for the public hero's rendered image and scrim.
// Sample every background pixel in each text line box, rather than averaging
// the photo or mistaking a transparent ancestor's CSS color for its backdrop.
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';

const load = await import(process.env.PLAYWRIGHT_CORE_PATH || '/Users/jeanbosco/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright-core/index.js');
const {chromium} = load.default || load;
const base = process.env.PUBLIC_CONTRAST_URL || 'http://127.0.0.1:4188';
const output = process.env.PUBLIC_PHOTO_CONTRAST_OUT || '.cache/revolut-design-20260906/website-photo-contrast';
const widths = [320, 390, 430, 720, 721, 800, 1100, 1101, 1440];
await mkdir(output, {recursive: true});
const browser = await chromium.launch({executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true});
const results = [];
try {
  for (const width of widths) {
    const page = await browser.newPage({viewport: {width, height: 1000}, deviceScaleFactor: 1});
    await page.goto(base + '/', {waitUntil: 'networkidle'});
    await page.evaluate(async () => {
      await document.fonts.ready;
      await Promise.all([...document.querySelectorAll('.hero img')].map(image => image.decode()));
    });
    const selectors = [
      '.hero h1', '.hero-intro', '.hero-actions .cta-app',
      '.hero-actions .cta-group', '.hero-actions .cta-touch',
      '.site-header .brand strong', '.site-header .nav-link',
      '.site-header .cta-app', '.site-header .menu-button',
    ];
    for (const selector of selectors) for (const [index, target] of (await page.locator(selector).all()).entries()) {
      if (!await target.isVisible()) continue;
      await page.evaluate(() => window.scrollTo({top: 0, behavior: 'instant'}));
      const geometry = await target.evaluate(element => {
        const style = getComputedStyle(element);
        const bounds = element.getBoundingClientRect();
        const lines = [];
        const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
        while (walker.nextNode()) {
          if (!walker.currentNode.textContent.trim()) continue;
          const range = document.createRange();
          range.selectNodeContents(walker.currentNode);
          for (const rect of range.getClientRects()) {
            lines.push({x: rect.x - bounds.x, y: rect.y - bounds.y, width: rect.width, height: rect.height});
          }
        }
        for (let node = element; node; node = node.parentElement) {
          if (Number(getComputedStyle(node).opacity) !== 1) {
            throw new Error('Ancestor opacity requires a separate compositing check');
          }
        }
        const rgba = style.color.match(/[\d.]+/g)?.map(Number);
        if (!style.color.startsWith('rgb') || !rgba) throw new Error('Unsupported text color');
        const fontSize = parseFloat(style.fontSize);
        const minimum = fontSize >= 24 || (fontSize >= 18.66 && Number(style.fontWeight) >= 700) ? 3 : 4.5;
        return {lines, rgba: [...rgba.slice(0, 3), rgba[3] ?? 1], fontSize, minimum,
          textWidth: bounds.width, textHeight: bounds.height, text: element.textContent.trim()};
      });
      const name = `${width}-${selector.replace(/[^a-z0-9]+/gi, '-').replace(/^-/, '')}-${index}`;
      await target.screenshot({path: `${output}/${name}.png`, animations: 'disabled'});
      // Transparent glyph fill leaves layout, images and the real scrim intact.
      const originalStyle = await target.getAttribute('style');
      await target.evaluate(element => {
        element.style.setProperty('-webkit-text-fill-color', 'transparent', 'important');
        element.style.setProperty('text-shadow', 'none', 'important');
      });
      const background = await target.screenshot({path: `${output}/${name}-background.png`, animations: 'disabled'});
      await target.evaluate((element, original) => {
        if (original === null) element.removeAttribute('style');
        else element.setAttribute('style', original);
      }, originalStyle);
      const measurement = await page.evaluate(async ({encoded, geometry}) => {
        const bitmap = await createImageBitmap(await (await fetch(`data:image/png;base64,${encoded}`)).blob());
        const canvas = document.createElement('canvas');
        canvas.width = bitmap.width; canvas.height = bitmap.height;
        const ctx = canvas.getContext('2d', {willReadFrequently: true});
        ctx.drawImage(bitmap, 0, 0);
        const pixels = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
        const luminance = color => color.map(value => value / 255)
          .map(value => value <= .04045 ? value / 12.92 : ((value + .055) / 1.055) ** 2.4)
          .reduce((sum, value, index) => sum + value * [.2126, .7152, .0722][index], 0);
        let minimumRatio = Infinity, sampledPixels = 0, worstPixel = null;
        for (const line of geometry.lines) {
          for (let y = Math.max(0, Math.floor(line.y)); y < Math.min(canvas.height, Math.ceil(line.y + line.height)); y++) {
            for (let x = Math.max(0, Math.floor(line.x)); x < Math.min(canvas.width, Math.ceil(line.x + line.width)); x++) {
              const offset = (y * canvas.width + x) * 4;
              if (pixels[offset + 3] !== 255) throw new Error('Unexpected transparent background capture');
              const bg = [...pixels.slice(offset, offset + 3)];
              const fg = bg.map((value, index) => geometry.rgba[index] * geometry.rgba[3] + value * (1 - geometry.rgba[3]));
              const a = luminance(fg), b = luminance(bg);
              const ratio = (Math.max(a, b) + .05) / (Math.min(a, b) + .05);
              sampledPixels++;
              if (ratio < minimumRatio) {minimumRatio = ratio; worstPixel = {x, y, background: bg};}
            }
          }
        }
        bitmap.close();
        if (!sampledPixels) throw new Error('No text background pixels sampled');
        return {minimumRatio, sampledPixels, worstPixel};
      }, {encoded: background.toString('base64'), geometry});
      results.push({route: '/', width, selector, ...geometry, ...measurement,
        status: measurement.minimumRatio >= geometry.minimum ? 'pass' : 'fail',
        screenshot: `${name}.png`, backgroundScreenshot: `${name}-background.png`});
    }
    await page.locator('.hero').screenshot({path: `${output}/${width}-hero.png`, animations: 'disabled'});
    await page.close();
  }
} finally {
  await browser.close();
}
const cssResponse = await fetch(base + '/revolut.css');
if (!cssResponse.ok) throw new Error(`Cannot bind rendered CSS: ${cssResponse.status}`);
const renderedCss = await cssResponse.text();
const sourceCss = await readFile('web/public/revolut.css', 'utf8');
const failures = results.filter(result => result.status !== 'pass');
const report = {status: failures.length ? 'fail' : 'pass', checkedAt: new Date().toISOString(), baseUrl: base,
  method: 'Minimum WCAG luminance ratio over every rendered background pixel in each text line rectangle, with glyph fill hidden and original image crops and scrims preserved. Conservative bounds include non-glyph pixels; this is not a screen-reader or native app test.',
  sourceCssMatchesRendered: renderedCss === sourceCss,
  renderedCssSha256: createHash('sha256').update(renderedCss).digest('hex'),
  failures: failures.length, results};
await writeFile(`${output}/report.json`, JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify({status: report.status, checked: results.length, failures: failures.length,
  sourceCssMatchesRendered: report.sourceCssMatchesRendered,
  minimumRatio: Math.min(...results.map(result => result.minimumRatio))}));
process.exitCode = failures.length || !report.sourceCssMatchesRendered ? 1 : 0;
