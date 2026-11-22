#!/usr/bin/env node
// Check rendered text against its computed flat background.
// Photos, gradients and inherited opacity require rendered-pixel evidence.
import {readFile, writeFile} from 'node:fs/promises';
import {launchContrastBrowser, withContrastPage} from './browser/contrast_runner.mjs';

const evidence = process.env.REVOLUT_DESIGN_EVIDENCE || '.cache/revolut-design-20260905';
const input = process.env.PUBLIC_ROUTE_QA_REPORT || evidence + '/exhaustive-website/route_rendered_qa.json';
const output = process.env.PUBLIC_CONTRAST_REPORT || evidence + '/website-text-contrast.json';
const qa = JSON.parse(await readFile(input, 'utf8'));
const routes = [...new Set(qa.results.map(row => row.route))];
if (routes.length === 0) throw new Error('The route QA report does not contain any pages to measure');

function measureFlatContrast() {
  function rgb(value) {
    if (!/^rgba?\(/.test(value)) return null;
    const components = value.match(/[\d.]+/g)?.map(Number);
    if (!components || components.length < 3) return null;
    return [components[0], components[1], components[2], components[3] ?? 1];
  }
  function blend(foreground, background) {
    return background.map((value, index) => foreground[index] * foreground[3] + value * (1 - foreground[3]));
  }
  function luminance(color) {
    return color.map(channel => channel / 255)
      .map(value => value <= .04045 ? value / 12.92 : ((value + .055) / 1.055) ** 2.4)
      .reduce((sum, value, index) => sum + value * [.2126, .7152, .0722][index], 0);
  }

  const failures = [];
  const unverified = [];
  let checked = 0;
  for (const element of document.querySelectorAll('body *')) {
    const text = [...element.childNodes].filter(node => node.nodeType === Node.TEXT_NODE)
      .map(node => node.textContent.trim()).join(' ').trim();
    if (!text || ['SCRIPT', 'STYLE', 'NOSCRIPT'].includes(element.tagName)) continue;
    const style = getComputedStyle(element);
    const box = element.getBoundingClientRect();
    if (!box.width || !box.height || style.visibility === 'hidden' || style.display === 'none') continue;

    const item = {tag: element.tagName.toLowerCase(), classes: element.className, text: text.slice(0, 140)};
    const layers = [];
    let backgroundOwner;
    let reason;
    for (let parent = element; parent; parent = parent.parentElement) {
      const backdrop = getComputedStyle(parent);
      if (Number(backdrop.opacity) < 1) { reason = 'opacity'; break; }
      if (backdrop.backgroundImage !== 'none') { reason = 'image or gradient'; break; }
      const color = rgb(backdrop.backgroundColor);
      if (!color) { reason = 'unsupported background color'; break; }
      layers.push(color);
      if (color[3] === 1) { backgroundOwner = parent; break; }
    }

    // Positioned transparent content can paint over a sibling photograph.
    if (!reason && backgroundOwner && layers.slice(0, -1).every(color => color[3] === 0)) {
      const painted = document.elementsFromPoint(box.left + box.width / 2, box.top + box.height / 2);
      const ownerIndex = painted.indexOf(backgroundOwner);
      if (painted.some((layer, index) => index < ownerIndex && !layer.contains(element) &&
          getComputedStyle(layer).backgroundImage !== 'none')) reason = 'non-ancestor image backdrop';
    }

    const foreground = rgb(style.color);
    if (reason || !foreground) {
      unverified.push({...item, reason: reason || 'unsupported color'});
      continue;
    }
    const background = layers.reverse().reduce((current, layer) => blend(layer, current), [255, 255, 255]);
    const textLuminance = luminance(blend(foreground, background));
    const backgroundLuminance = luminance(background);
    const ratio = (Math.max(textLuminance, backgroundLuminance) + .05) /
      (Math.min(textLuminance, backgroundLuminance) + .05);
    const fontSize = Number.parseFloat(style.fontSize);
    const minimum = fontSize >= 24 || (fontSize >= 18.66 && Number(style.fontWeight) >= 700) ? 3 : 4.5;
    checked += 1;
    if (ratio + .03 < minimum) {
      failures.push({...item, color: style.color, background, ratio: Number(ratio.toFixed(2)), minimum});
    }
  }
  return {checked, failures, unverified};
}

const browser = await launchContrastBrowser();
const results = [];
try {
  for (const width of [320, 1440]) {
    for (const route of routes) {
      const measurements = await withContrastPage(browser, width, route, page => page.evaluate(measureFlatContrast));
      results.push({route, width, ...measurements});
    }
  }
} finally {
  await browser.close();
}

const failures = results.reduce((sum, row) => sum + row.failures.length, 0);
const report = {
  status: failures ? 'fail' : 'pass',
  scope: 'Computed flat-background contrast. Images, gradients and opacity remain visually unverified.',
  checkedAt: new Date().toISOString(),
  failures,
  results,
};
await writeFile(output, JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify({
  status: report.status,
  failures,
  checked: results.reduce((sum, row) => sum + row.checked, 0),
  unverified: results.reduce((sum, row) => sum + row.unverified.length, 0),
}));
process.exitCode = failures ? 1 : 0;
