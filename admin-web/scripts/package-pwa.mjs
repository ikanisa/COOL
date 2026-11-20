import { createHash } from 'node:crypto';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const templatePath = path.resolve(here, '../../scripts/templates/admin_pwa_service_worker.js');
const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');
const expectedIconHash = 'cae23ce3562e8aac2e248e7b22f7feed194f4fcfd2b57725ec1026f064bb0ad9';

async function filesUnder(root, directory = root) {
  const files = [];
  for (const entry of await fs.readdir(directory, { withFileTypes: true })) {
    if (entry.name.startsWith('._') || entry.name === '.DS_Store') continue;
    const absolute = path.join(directory, entry.name);
    if (entry.isSymbolicLink()) throw new Error('Static build must not contain symlinks');
    if (entry.isDirectory()) files.push(...await filesUnder(root, absolute));
    else if (entry.isFile()) {
      const name = path.relative(root, absolute).split(path.sep).join('/');
      if (!/^[A-Za-z0-9._/-]+$/.test(name) || name.split('/').includes('..')) {
        throw new Error('Static build contains an invalid asset name');
      }
      files.push(name);
    } else throw new Error('Static build contains a non-regular asset');
  }
  return files.sort();
}

function replaceOnce(source, marker, value) {
  if (source.split(marker).length !== 2) throw new Error(`Invalid worker template: ${marker}`);
  return source.replace(marker, value);
}

function renderWorker(template, urls, hashes) {
  const cacheId = sha256(`${sha256(template)}\n${JSON.stringify(hashes)}`).slice(0, 16);
  let worker = replaceOnce(template, '__COLLECT_ADMIN_CACHE_NAME__', JSON.stringify(`collect-admin-${cacheId}`));
  worker = replaceOnce(worker, '__COLLECT_ADMIN_CACHE_URLS__', JSON.stringify(urls));
  worker = replaceOnce(worker, '__COLLECT_ADMIN_CACHE_HASHES__', JSON.stringify(hashes));
  return { cacheId, worker };
}

const hostingHeaders = `/*
  X-Frame-Options: DENY
  X-Content-Type-Options: nosniff
  Referrer-Policy: no-referrer
  Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=(), usb=(), fullscreen=(self)
  Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self'; frame-src 'self' https://api.collect.ikanisa.com; manifest-src 'self'; worker-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'; upgrade-insecure-requests
  X-Robots-Tag: noindex, nofollow

/
  Cache-Control: no-store, no-transform

/index.html
  Cache-Control: no-store, no-transform

/admin
  Cache-Control: no-store, no-transform

/admin/*
  Cache-Control: no-store, no-transform

/custom-sw.js
  Cache-Control: no-cache

/manifest.json
  Cache-Control: no-cache

/version.json
  Cache-Control: no-cache

/.well-known/assetlinks.json
  Content-Type: application/json; charset=utf-8
  Cache-Control: public, max-age=300, must-revalidate

/.well-known/apple-app-site-association
  Content-Type: application/json; charset=utf-8
  Cache-Control: public, max-age=300, must-revalidate

/_build/*
  Cache-Control: public, max-age=31536000, immutable
`;

/**
 * Package a Vite build created with ADMIN_ASSET_BASE=./ as an unqualified
 * PWA. The destination must not exist; this function never overwrites a release.
 */
export async function packagePwa(inputDirectory, outputDirectory, { publicBuild } = {}) {
  const input = path.resolve(inputDirectory);
  const output = path.resolve(outputDirectory);
  if (input === output || output.startsWith(`${input}${path.sep}`) || input.startsWith(`${output}${path.sep}`)) {
    throw new Error('Input and output directories must be separate');
  }
  const stat = await fs.lstat(input);
  if (!stat.isDirectory() || stat.isSymbolicLink()) throw new Error('Invalid Vite build directory');
  const all = await filesUnder(input);
  if (!all.includes('index.html') || !all.includes('icons/collect-web-512.png') ||
      !all.includes('assets/admin-entry.js')) {
    throw new Error('Vite build must contain the Admin shell, JavaScript and Collect icon');
  }
  if (sha256(await fs.readFile(path.join(input, 'icons/collect-web-512.png'))) !== expectedIconHash) {
    throw new Error('Collect Admin icon does not match the approved asset');
  }
  const runtime = all.filter((name) => name !== 'index.html');
  if (runtime.some((name) =>
    /^(?:api|v1|functions|privacy|account-deletion)(?:\/|$)/.test(name) ||
    /^(?:custom-sw\.js|manifest\.json|version\.json|_headers|_redirects)$/.test(name) ||
    /(?:^|\/)\.[^/]+|\.(?:pem|key|sqlite|db|sql)$/i.test(name))) {
    throw new Error('Static build contains a reserved or sensitive-looking path');
  }
  const fileHashes = Object.fromEntries(await Promise.all(runtime.map(async (name) => [
    name, sha256(await fs.readFile(path.join(input, name))),
  ])));
  const assetId = sha256(runtime.map((name) => `${name}\0${fileHashes[name]}`).join('\n'));
  const assetPrefix = `_build/${assetId}/`;
  let index = await fs.readFile(path.join(input, 'index.html'), 'utf8');
  if (!index.includes('<title>Collect Admin</title>') ||
      !index.includes('Collect platform operations console.') ||
      !/src=["']\.\/assets\/admin-entry\.js["']/.test(index)) {
    throw new Error('Build must use the Collect Admin shell and relative Vite asset base');
  }
  // The same shell serves legacy path-style deep links as well as '/'. Rooted
  // asset URLs must resolve before the application can normalize those routes.
  index = index.replace(/(["'])\.\/(assets|icons|licenses)\//g, `$1/${assetPrefix}$2/`)
    .replace(/(["'])\.\/manifest\.json\1/g, '$1/manifest.json$1');
  if (/(?:src|href)=["'](?:\/|\.\/)?(?:assets|icons)\//.test(index) ||
      /<script\b(?![^>]*\bsrc=)/i.test(index)) {
    throw new Error('Admin shell contains an unversioned asset or inline script');
  }

  // No deployable or qualified backend claim is manufactured by this package.
  if (publicBuild && (publicBuild.backend !== 'supabase' ||
      !/^[a-f0-9]{64}$/.test(publicBuild.public_build_config_sha256 ?? ''))) {
    throw new Error('Expected a bound public Supabase build configuration');
  }
  const version = {
    ...publicBuild,
    app_name: 'collect-admin',
    frontend: 'react-vite',
    asset_manifest_sha256: assetId,
    backend: publicBuild?.backend ?? 'unconfigured',
    qualification_complete: false,
    shipping_candidate: false,
  };
  const manifest = {
    name: 'Collect Admin', short_name: 'Collect Admin',
    description: 'Collect platform operations console.', display: 'standalone',
    start_url: '.', scope: '.', background_color: '#ffffff', theme_color: '#171b20',
    icons: [{ src: `./${assetPrefix}icons/collect-web-512.png`, sizes: '512x512',
      type: 'image/png', purpose: 'any maskable' }],
  };
  const template = await fs.readFile(templatePath, 'utf8');
  await fs.mkdir(output); // Fails rather than overwriting any earlier candidate.
  for (const name of runtime) {
    const destination = path.join(output, assetPrefix, name);
    await fs.mkdir(path.dirname(destination), { recursive: true });
    await fs.copyFile(path.join(input, name), destination, fs.constants.COPYFILE_EXCL);
  }
  await fs.writeFile(path.join(output, 'index.html'), index, { flag: 'wx' });
  await fs.writeFile(path.join(output, 'manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`, { flag: 'wx' });
  await fs.writeFile(path.join(output, 'version.json'), `${JSON.stringify(version, null, 2)}\n`, { flag: 'wx' });
  await fs.writeFile(path.join(output, '_headers'), hostingHeaders, { flag: 'wx' });
  await fs.writeFile(path.join(output, '_redirects'), `/favicon.ico /${assetPrefix}icons/collect-web-512.png 302\n`, { flag: 'wx' });
  await fs.writeFile(path.join(output, 'robots.txt'), 'User-agent: *\nDisallow: /\n', { flag: 'wx' });

  const urls = ['./', './manifest.json', './version.json', ...runtime.map((name) => `./${assetPrefix}${name}`)];
  const hashes = Object.fromEntries(await Promise.all(urls.map(async (url) => [
    url, sha256(await fs.readFile(path.join(output, url === './' ? 'index.html' : url.slice(2)))),
  ])));
  const { cacheId, worker } = renderWorker(template, urls, hashes);
  await fs.writeFile(path.join(output, 'custom-sw.js'), worker, { flag: 'wx' });
  await verifyPwaPackage(output);
  return { assetId, cacheId, files: runtime.length, qualificationComplete: false };
}

/** Verify the generated static inventory against the exact bytes on disk. */
export async function verifyPwaPackage(directory) {
  const root = path.resolve(directory);
  const version = JSON.parse(await fs.readFile(path.join(root, 'version.json'), 'utf8'));
  const worker = await fs.readFile(path.join(root, 'custom-sw.js'), 'utf8');
  const urlMatch = worker.match(/const CACHE_URLS = (\[[^\n]*\]);/);
  const hashMatch = worker.match(/const CACHE_HASHES = (\{[^\n]*\});/);
  if (!urlMatch || !hashMatch) throw new Error('Missing Admin cache manifest');
  const urls = JSON.parse(urlMatch[1]);
  const hashes = JSON.parse(hashMatch[1]);
  if (!/^[a-f0-9]{64}$/.test(version.asset_manifest_sha256 ?? '')) throw new Error('Invalid Admin asset version');
  const prefix = `_build/${version.asset_manifest_sha256}/`;
  const rootFiles = ['index.html', 'manifest.json', 'version.json', 'custom-sw.js', '_headers', '_redirects', 'robots.txt'];
  const associations = ['.well-known/apple-app-site-association', '.well-known/assetlinks.json'];
  const files = await filesUnder(root);
  const assets = files.filter(name => name.startsWith(prefix));
  const expectedUrls = ['./', './manifest.json', './version.json', ...assets.map(name => `./${name}`)];
  if (!rootFiles.every(name => files.includes(name)) || (files.some(name => name.startsWith('.well-known/')) &&
      !associations.every(name => files.includes(name))) ||
      files.some(name => !rootFiles.includes(name) && !associations.includes(name) && !name.startsWith(prefix)) ||
      JSON.stringify(urls) !== JSON.stringify(expectedUrls) || Object.keys(hashes).length !== expectedUrls.length) {
    throw new Error('Invalid Admin cache inventory');
  }
  for (const url of urls) {
    const bytes = await fs.readFile(path.join(root, url === './' ? 'index.html' : url.slice(2)));
    if (sha256(bytes) !== hashes[url]) throw new Error(`Static asset integrity failed: ${url}`);
  }
  const template = await fs.readFile(templatePath, 'utf8');
  if (worker !== renderWorker(template, urls, hashes).worker) {
    throw new Error('Admin worker differs from the audited template');
  }
  if (version.frontend !== 'react-vite' || version.shipping_candidate !== false ||
      version.qualification_complete !== false || !['unconfigured', 'supabase'].includes(version.backend) ||
      (version.backend === 'supabase' && !/^[a-f0-9]{64}$/.test(version.public_build_config_sha256 ?? ''))) {
    throw new Error('Expected an unqualified React Admin package');
  }
  const assetId = sha256(assets.map(name => `${name.slice(prefix.length)}\0${hashes['./' + name]}`).join('\n'));
  const index = await fs.readFile(path.join(root, 'index.html'), 'utf8');
  const manifest = JSON.parse(await fs.readFile(path.join(root, 'manifest.json'), 'utf8'));
  const icon = `${prefix}icons/collect-web-512.png`;
  if (assetId !== version.asset_manifest_sha256 || !assets.includes(prefix + 'assets/admin-entry.js') ||
      !['"', "'"].some(quote => index.includes(`src=${quote}/${prefix}assets/admin-entry.js${quote}`)) ||
      hashes['./' + icon] !== expectedIconHash ||
      manifest.start_url !== '.' || manifest.scope !== '.' || manifest.display !== 'standalone' ||
      manifest.icons?.length !== 1 || manifest.icons[0]?.src !== './' + icon) {
    throw new Error('Admin entry and cache differ from the asset version');
  }
  const text = (name) => fs.readFile(path.join(root, name), 'utf8');
  if (await text('_headers') !== hostingHeaders || await text('robots.txt') !== 'User-agent: *\nDisallow: /\n' ||
      await text('_redirects') !== `/favicon.ico /${icon} 302\n`) {
    throw new Error('Admin hosting rules or robots policy differ from the package contract');
  }
  return { cacheEntries: urls.length };
}
