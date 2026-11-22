import { execFileSync } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { sha256 } from './pwa-assets.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const output = resolve(root, process.env.ADMIN_PWA_BUILD_DIR ?? 'build/admin-web');
const json = process.argv.includes('--json');

function report(status, fields) {
  const result = { status, frontend: 'react-vite', ...fields };
  console.log(json ? JSON.stringify(result, null, 2) : `React Admin live check ${status}: ${fields.reason ?? fields.origin}`);
}

try {
  const { environment, admin_origin: expectedOrigin, asset_manifest_sha256: assetId } =
    JSON.parse(await readFile(join(output, 'version.json'), 'utf8'));
  const profile = process.argv.includes('--qualification') ? 'qualification' : 'production';
  if (environment !== profile) throw new Error(`The live check requires a ${profile}-profile React Admin build.`);
  const url = new URL(process.env.ADMIN_PWA_LIVE_URL ?? expectedOrigin);
  if (url.protocol !== 'https:' || url.origin !== expectedOrigin || url.username || url.password || url.port ||
      url.pathname !== '/' || url.search || url.hash) {
    throw new Error('The live URL must be the exact HTTPS origin bound to the React Admin artifact.');
  }
  execFileSync(process.execPath, [join(root, 'admin-web/scripts/build-admin.mjs'), 'verify-hosting', output], {
    cwd: root, stdio: 'ignore',
  });
  const { files } = JSON.parse(await readFile(output + '.json', 'utf8'));
  const served = files.filter(([name]) => !name.startsWith('_') || name.startsWith('_build/'));
  const entry = `_build/${assetId}/assets/admin-entry.js`;
  const htmlSha = served.find(([name]) => name === 'index.html')[1];
  const checks = [['/', htmlSha], ['/admin/settings', htmlSha],
    ...served.map(([name, digest]) => ['/' + name, digest])];
  const [globalRules] = (await readFile(join(output, '_headers'), 'utf8')).split('\n\n');
  const expectedHeaders = globalRules.split('\n').slice(1).map(line => line.trim().split(/: (.+)/).slice(0, 2));

  let checked = 0;
  for (const [pathname, digest] of checks) {
    const response = await fetch(new URL(pathname, url), { redirect: 'manual', signal: AbortSignal.timeout(15_000) });
    if (response.status !== 200 || sha256(Buffer.from(await response.arrayBuffer())) !== digest) {
      throw new Error(`Hosted bytes or status differ for ${pathname === '/' ? 'the Admin shell' : pathname}.`);
    }
    const cache = response.headers.get('cache-control') ?? '';
    const contentType = response.headers.get('content-type') ?? '';
    if (['/', '/index.html', '/admin/settings'].includes(pathname)) {
      if (!contentType.startsWith('text/html') || !cache.includes('no-store') || !cache.includes('no-transform') ||
          expectedHeaders.some(([name, value]) => response.headers.get(name) !== value)) {
        throw new Error('The hosted HTML security or caching headers differ from the Admin contract.');
      }
    }
    if (pathname.startsWith('/_build/') && !cache.includes('immutable')) throw new Error('Versioned assets lack immutable caching.');
    if (['/custom-sw.js', '/version.json', '/manifest.json'].includes(pathname) &&
        (!/\b(?:no-cache|no-store)\b/.test(cache) || cache.includes('immutable'))) {
      throw new Error('Mutable PWA metadata must revalidate.');
    }
    if ([`/${entry}`, '/custom-sw.js'].includes(pathname) && !contentType.includes('javascript')) {
      throw new Error('The Admin entry or service worker has an invalid content type.');
    }
    if (pathname.startsWith('/.well-known/') && !contentType.startsWith('application/json')) {
      throw new Error('Native association files must be served as JSON.');
    }
    checked += 1;
  }
  report('pass', { origin: url.origin, static_responses_verified: checked });
} catch (error) {
  const blocked = error.code === 'ENOENT' || error.status !== undefined;
  report(blocked ? 'blocked' : 'fail', { reason: blocked ?
    'A verified local React Admin artifact and its receipt are required.' : error.message });
  process.exitCode = blocked ? 99 : 1;
}
