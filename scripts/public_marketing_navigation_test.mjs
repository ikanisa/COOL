// These are controller regressions with synthetic DOM objects, not browser,
// accessibility-reader or visual-comparison evidence.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {dirname, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import vm from 'node:vm';
import test from 'node:test';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const source = execFileSync('ruby', ['-e', 'source = File.read("scripts/public_static_site_build.rb"); eval(source.split("allowed_build_roots =", 2).first, TOPLEVEL_BINDING, "scripts/public_static_site_build.rb"); print site_js'], {cwd: root, encoding: 'utf8'});
function fixture({kind, path = '/', query = '', userAgent = 'Desktop'} = {}) {
  const documentHandlers = {}, windowHandlers = {}, nodes = new Map();
  const document = {activeElement: null, visibilityState: 'visible'};
  function node() {
    const attrs = new Map(), names = new Set(), handlers = {};
    return {
      attrs, handlers, textContent: '', inert: false, dataset: {}, href: '',
      classList: {toggle(name, yes) {yes ? names.add(name) : names.delete(name);}, contains(name) {return names.has(name);}},
      setAttribute(name, value) {attrs.set(name, value);}, getAttribute(name) {return attrs.get(name);},
      removeAttribute(name) {attrs.delete(name);}, hasAttribute(name) {return attrs.has(name);},
      focus() {document.activeElement = this;}, addEventListener(name, action) {handlers[name] = action;},
    };
  }
  const button = node(), nav = node(), first = node(), last = node(), content = [node(), node()];
  nav.querySelector = () => first;
  nav.querySelectorAll = () => [first, last];
  nodes.set('[data-menu-button]', button); nodes.set('[data-site-nav]', nav);
  document.body = node();
  document.querySelector = selector => nodes.get(selector) || null;
  document.querySelectorAll = selector => selector === 'main, .site-footer' ? content : selector === '[data-collect-store-link]' ? [first, last] : [];
  document.addEventListener = (event, action) => {documentHandlers[event] = action;};
  const window = {innerWidth: 390, location: {hash: '', pathname: path, search: query, origin: 'https://collect.example'}, addEventListener(event, action) {windowHandlers[event] = action;}, setTimeout() {}};
  const clipboard = [];
  const navigator = {userAgent, platform: '', maxTouchPoints: 0, clipboard: {async writeText(text) {clipboard.push(text);}}};
  if (kind) {
    const share = node(); share.dataset.shareLanding = kind; nodes.set('[data-share-landing]', share);
    for (const role of ['open-link', 'share-code', 'share-heading', 'share-status', 'share-canonical', 'share-og-url', 'share-smart-banner', 'copy-link']) nodes.set('[data-' + (role.startsWith('share-') ? role : 'collect-' + role) + ']', node());
  }
  vm.runInNewContext(source, {document, window, navigator, URLSearchParams, Date, encodeURIComponent});
  return {document, documentHandlers, windowHandlers, window, navigator, button, nav, first, last, content, nodes, clipboard};
}

test('mobile menu contains focus, makes background inert and restores Escape focus', () => {
  const f = fixture(); f.button.handlers.click();
  assert.equal(f.button.getAttribute('aria-expanded'), 'true');
  assert.equal(f.document.activeElement, f.first);
  assert.ok(f.content.every(node => node.inert));
  f.last.focus(); let prevented = false;
  f.documentHandlers.keydown({key: 'Tab', shiftKey: false, preventDefault() {prevented = true;}});
  assert.equal(prevented, true); assert.equal(f.document.activeElement, f.button);
  f.documentHandlers.keydown({key: 'Tab', shiftKey: true, preventDefault() {}});
  assert.equal(f.document.activeElement, f.last);
  f.documentHandlers.keydown({key: 'Escape', preventDefault() {}});
  assert.equal(f.button.getAttribute('aria-expanded'), 'false');
  assert.equal(f.document.activeElement, f.button);
  assert.ok(f.content.every(node => !node.inert));
});
test('navigation and switching to desktop release the mobile menu', () => {
  const f = fixture(); f.button.handlers.click();
  f.nav.handlers.click({target: {closest() {return f.first;}}});
  assert.equal(f.nav.classList.contains('open'), false);
  f.button.handlers.click(); f.window.innerWidth = 1440; f.windowHandlers.resize();
  assert.equal(f.document.body.classList.contains('menu-open'), false);
  assert.ok(f.content.every(node => !node.inert));
});
test('invalid group links cannot open the app and offer visible recovery', () => {
  const f = fixture({kind: 'group', path: '/c/invalid_slug'});
  assert.equal(f.nodes.get('[data-collect-open-link]').getAttribute('aria-disabled'), 'true');
  assert.equal(f.nodes.get('[data-share-code]').textContent, 'This group link is invalid.');
  assert.match(f.nodes.get('[data-share-status]').textContent, /share a new link/);
});
test('shared links preserve group identity and platform store navigation', async () => {
  const f = fixture({kind: 'group', path: '/c/community-group', userAgent: 'iPhone'});
  assert.equal(f.nodes.get('[data-collect-open-link]').href, 'collect://group/community-group');
  assert.match(f.first.href, /apps.apple.com/);
  await f.nodes.get('[data-collect-copy-link]').handlers.click();
  assert.deepEqual(f.clipboard, ['https://collect.example/c/community-group']);
  assert.equal(f.nodes.get('[data-share-status]').textContent, 'Link copied.');
});
test('clipboard rejection shows recovery and an unchanged link can be retried', async () => {
  const f = fixture({kind: 'group', path: '/c/community-group'});
  const clipboard = f.navigator.clipboard;
  clipboard.writeText = async () => {throw new Error('Clipboard permission denied');};
  const copy = f.nodes.get('[data-collect-copy-link]');
  await copy.handlers.click();
  assert.equal(f.nodes.get('[data-share-status]').textContent, 'Copy the link from your browser address bar.');
  const copied = [];
  clipboard.writeText = async text => {copied.push(text);};
  await copy.handlers.click();
  assert.deepEqual(copied, ['https://collect.example/c/community-group']);
  assert.equal(f.nodes.get('[data-share-status]').textContent, 'Link copied.');
});
test('all public share templates have the same operable compact menu', () => {
  const builder = readFileSync(resolve(root, 'scripts/public_static_site_build.rb'), 'utf8');
  const share = builder.slice(builder.indexOf('def share_landing_page_html'), builder.indexOf('def stylesheet'));
  assert.match(share, /data-menu-button aria-expanded="false" aria-controls="site-nav"/);
  assert.match(share, /id="site-nav" class="site-nav" data-site-nav/);
  assert.match(share, /class="mobile-menu-actions"/);
});
