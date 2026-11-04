// These are controller regressions with synthetic DOM objects, not browser,
// accessibility-reader or visual-comparison evidence.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {dirname, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import vm from 'node:vm';
import test from 'node:test';
import {uuid as joinUuid} from '../supabase/functions/_shared/domain/core.js';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
// Evaluating the real builder prefix also runs its ordinary capability/source validation.
const rendered = JSON.parse(execFileSync('ruby', ['-e', 'source = File.read("scripts/public_static_site_build.rb"); eval(source.split("allowed_build_roots =", 2).first, TOPLEVEL_BINDING, "scripts/public_static_site_build.rb"); print JSON.generate({source: site_js, publicUrl: PUBLIC_URL, groupHtml: share_landing_page_html(kind: :group)})'], {cwd: root, encoding: 'utf8'}));
const {source, publicUrl, groupHtml} = rendered;
const validUuid = 'f0e5d2a1-9213-45cc-8e03-123456789abc';
function fixture({kind, path = '/', query = '', userAgent = 'Desktop', oldTemplate = false, clipGate = null, href = null} = {}) {
  const documentHandlers = {}, windowHandlers = {}, nodes = new Map(), assigned = [];
  const document = {activeElement: null, visibilityState: 'visible'};
  function node({tagName = 'DIV', disabled = false} = {}) {
    const attrs = new Map(), names = new Set(), handlers = {};
    return {
      attrs, handlers, tagName, disabled, textContent: '', inert: false, dataset: {}, href: '', content: '',
      classList: {toggle(name, yes) {yes ? names.add(name) : names.delete(name);}, contains(name) {return names.has(name);}},
      setAttribute(name, value) {attrs.set(name, value);}, getAttribute(name) {return attrs.get(name);},
      removeAttribute(name) {attrs.delete(name); if (name === 'href') this.href = '';}, hasAttribute(name) {return name === 'href' ? !!this.href : attrs.has(name);},
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
  const address = new URL(href || path + query, publicUrl);
  const location = {href: address.href, hash: address.hash, pathname: address.pathname, search: address.search, origin: address.origin, assign(value) {assigned.push(value);}};
  const window = {innerWidth: 390, location, addEventListener(event, action) {windowHandlers[event] = action;}, setTimeout() {}};
  const clipboard = [];
  const navigator = {userAgent, platform: '', maxTouchPoints: 0, clipboard: {async writeText(text) {if (clipGate) await clipGate; clipboard.push(text);}}};
  if (kind) {
    const share = node(); share.dataset.shareLanding = kind; nodes.set('[data-share-landing]', share);
    for (const role of ['share-code', 'share-heading', 'share-status', 'share-canonical', 'share-og-url', 'share-smart-banner']) nodes.set('[data-' + role + ']', node());
    const open = node({tagName: kind === 'group' && !oldTemplate ? 'BUTTON' : 'A', disabled: kind === 'group' && !oldTemplate});
    if (kind === 'app') open.href = 'collect://app';
    if (oldTemplate) open.href = 'collect://group/old-placeholder';
    nodes.set('[data-collect-open-link]', open);
    nodes.set('[data-collect-copy-link]', node({tagName: 'BUTTON', disabled: kind === 'group'}));
  }
  vm.runInNewContext(source, {document, window, navigator, URL, URLSearchParams, Date, encodeURIComponent, decodeURIComponent, requestAnimationFrame() {}});
  return {document, documentHandlers, windowHandlers, window, navigator, button, nav, first, last, content, nodes, clipboard, assigned};
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
test('invalid and legacy non-UUID group links stay disabled and offer recovery', () => {
  for (const path of ['/c/invalid_slug', '/c/legacy-group']) {
    const f = fixture({kind: 'group', path});
    assert.equal(f.nodes.get('[data-collect-open-link]').disabled, true);
    assert.equal(f.nodes.get('[data-collect-copy-link]').disabled, true);
    assert.match(f.nodes.get('[data-share-status]').textContent, /cannot be used.*new link/);
    assert.deepEqual(f.assigned, []);
  }
});
test('valid shared links open only on a user action and copy the canonical UUID', async () => {
  const f = fixture({kind: 'group', path: '/c/' + validUuid.toUpperCase(), query: '?tracking=ignored', userAgent: 'iPhone'});
  const open = f.nodes.get('[data-collect-open-link]'), copy = f.nodes.get('[data-collect-copy-link]');
  assert.equal(open.disabled, false); assert.equal(copy.disabled, false); assert.deepEqual(f.assigned, []);
  assert.match(f.first.href, /apps.apple.com/);
  open.handlers.click(); assert.deepEqual(f.assigned, ['collect://group/' + validUuid]);
  await copy.handlers.click(); assert.deepEqual(f.clipboard, [new URL('/c/' + validUuid, publicUrl).href]);
  assert.equal(f.nodes.get('[data-share-status]').textContent, 'Link copied.');
});
test('clipboard rejection offers original-message recovery and allows retry', async () => {
  const f = fixture({kind: 'group', path: '/c/' + validUuid});
  const clipboard = f.navigator.clipboard; clipboard.writeText = async () => {throw new Error('denied');};
  const copy = f.nodes.get('[data-collect-copy-link]'); await copy.handlers.click();
  assert.match(f.nodes.get('[data-share-status]').textContent, /original message/);
  clipboard.writeText = async text => {f.clipboard.push(text);}; await copy.handlers.click();
  assert.deepEqual(f.clipboard, [new URL('/c/' + validUuid, publicUrl).href]);
});
test('all accepted UUID versions and variants agree with the actual join validator', async () => {
  for (const version of '12345678') for (const variant of '89ab') {
    const id = `f0e5d2a1-9213-${version}5cc-${variant}e03-123456789abc`;
    for (const value of [id, id.toUpperCase()]) {
      assert.equal(joinUuid(value, 'group_code'), id);
      const f = fixture({kind: 'group', path: '/c/' + value});
      assert.equal(f.nodes.get('[data-collect-open-link]').disabled, false);
      f.nodes.get('[data-collect-open-link]').handlers.click();
      assert.deepEqual(f.assigned, ['collect://group/' + id]);
    }
  }
  const invalid = [...'09abcdef'].map(version => `f0e5d2a1-9213-${version}5cc-8e03-123456789abc`)
    .concat([...'01234567cdef'].map(variant => `f0e5d2a1-9213-45cc-${variant}e03-123456789abc`));
  for (const id of invalid) {
    assert.throws(() => joinUuid(id, 'group_code'));
    const f = fixture({kind: 'group', path: '/c/' + id});
    assert.equal(f.nodes.get('[data-collect-open-link]').disabled, true);
    assert.equal(f.nodes.get('[data-collect-copy-link]').disabled, true);
  }
});
test('alternate targets, wrong origin and fragments do not enable group actions', () => {
  for (const options of [
    {path: '/c/' + validUuid, query: '?slug=other'},
    {path: '/c/' + validUuid, query: '?group=other'},
    {path: '/c/' + validUuid, query: '#other'},
    {href: 'https://other.example/c/' + validUuid},
    {path: '/group-link/', query: '?slug=' + validUuid + '&slug=other'},
  ]) {
    const f = fixture({kind: 'group', ...options});
    assert.equal(f.nodes.get('[data-collect-open-link]').disabled, true);
    assert.equal(f.nodes.get('[data-collect-copy-link]').disabled, true);
  }
});
test('a pending copy may finish for the original link after navigation without claiming the new link', async () => {
  let finish; const held = new Promise(resolve => {finish = resolve;});
  const f = fixture({kind: 'group', path: '/c/' + validUuid, clipGate: held});
  const pending = f.nodes.get('[data-collect-copy-link]').handlers.click();
  f.window.location.href = new URL('/c/f0e5d2a1-9213-45cc-8e03-abcdefabcdef', publicUrl).href;
  finish(); await pending;
  assert.deepEqual(f.clipboard, [new URL('/c/' + validUuid, publicUrl).href]);
  assert.notEqual(f.nodes.get('[data-share-status]').textContent, 'Link copied.');
});
test('an old href-bearing group template is disabled by the new script', () => {
  const f = fixture({kind: 'group', path: '/c/' + validUuid, oldTemplate: true});
  const open = f.nodes.get('[data-collect-open-link]');
  assert.equal(open.href, ''); assert.equal(open.getAttribute('aria-disabled'), 'true');
  assert.equal(f.nodes.get('[data-collect-copy-link]').disabled, true);
  let prevented = false; open.handlers.click({preventDefault() {prevented = true;}});
  assert.equal(prevented, true); assert.deepEqual(f.assigned, []);
});
test('app invitations keep their previous open action and dynamic metadata', () => {
  const f = fixture({kind: 'app', path: '/invite/Abc_123'});
  assert.equal(f.nodes.get('[data-collect-open-link]').href, 'collect://invite/Abc_123');
  assert.equal(f.nodes.get('[data-share-canonical]').href, publicUrl + '/invite/Abc_123');
  assert.equal(f.nodes.get('[data-share-og-url]').content, publicUrl + '/invite/Abc_123');
  assert.match(f.nodes.get('[data-share-smart-banner]').content, /app-argument=/);
});
test('group template starts disabled and identifies both stores without JavaScript', () => {
  assert.match(groupHtml, /<button class="button primary" type="button" data-collect-open-link disabled>/);
  assert.match(groupHtml, /<button class="button ghost" type="button" data-collect-copy-link disabled>/);
  assert.match(groupHtml, /<noscript>.*reopen the original link/s);
  assert.match(groupHtml, /data-collect-store-link>Google Play<\/a>/);
  assert.match(groupHtml, /aria-label="Get Collect on the Apple App Store">App Store<\/a>/);
});
test('all public share templates have the same operable compact menu', () => {
  const builder = readFileSync(resolve(root, 'scripts/public_static_site_build.rb'), 'utf8');
  const share = builder.slice(builder.indexOf('def share_landing_page_html'), builder.indexOf('def stylesheet'));
  assert.match(share, /data-menu-button aria-expanded="false" aria-controls="site-nav"/);
  assert.match(share, /id="site-nav" class="site-nav" data-site-nav/);
  assert.match(share, /class="mobile-menu-actions"/);
});

test('legacy UUID query aliases retain explicit action and canonical copy', async () => {
  for (const path of ['/c', '/c/', '/c/index.html', '/group-link', '/group-link/', '/group-link/index.html']) {
    const f = fixture({kind: 'group', path, query: '?slug=' + validUuid.toUpperCase()});
    const open = f.nodes.get('[data-collect-open-link]'), copy = f.nodes.get('[data-collect-copy-link]');
    assert.equal(open.disabled, false, path); assert.equal(copy.disabled, false, path);
    open.handlers.click(); assert.deepEqual(f.assigned, ['collect://group/' + validUuid], path);
    await copy.handlers.click(); assert.deepEqual(f.clipboard, [new URL('/c/' + validUuid, publicUrl).href], path);
  }
});
test('an address changed before the action cannot open or copy the previous invitation', async () => {
  const f = fixture({kind: 'group', path: '/c/' + validUuid});
  f.window.location.href = new URL('/c/f0e5d2a1-9213-45cc-8e03-abcdefabcdef', publicUrl).href;
  const open = f.nodes.get('[data-collect-open-link]'), copy = f.nodes.get('[data-collect-copy-link]');
  open.handlers.click(); assert.deepEqual(f.assigned, []); assert.equal(open.disabled, true); assert.equal(copy.disabled, true);
  await copy.handlers.click(); assert.deepEqual(f.clipboard, []);
  assert.match(f.nodes.get('[data-share-status]').textContent, /link changed/i);
});
test('group disabled selector has greater specificity than enabled hero controls', () => {
  const css = readFileSync(resolve(root, 'web/public/revolut.css'), 'utf8');
  const disabled = css.match(/\.revolut-public\.route-share-link \.hero \.button:disabled,[\s\S]*?\{([^}]+)\}/);
  assert.ok(disabled);
  for (const declaration of ['background: var(--web-card-border)', 'color: var(--web-secondary)', 'border-color: var(--web-card-border)', 'cursor: default']) assert.ok(disabled[1].includes(declaration));
  for (const enabled of ['.revolut-public .hero .button.primary', '.revolut-public .hero .button.ghost']) {
    assert.ok(css.includes(enabled + ' {'));
    assert.equal(enabled.match(/[.:][\w-]+/g).length, 4);
  }
  assert.equal('.revolut-public.route-share-link .hero .button:disabled'.match(/[.:][\w-]+/g).length, 5);
});
