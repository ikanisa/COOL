// Test-only process adapter. Production has no configurable fetch origin or
// insecure transport flag. Requests still go over a real local HTTP socket.
import { ADMIN_ORIGIN } from '../src/config.mjs';
const actual = globalThis.fetch;
const fixture = new URL(process.env.COLLECT_MCP_FIXTURE_URL);
if (fixture.protocol !== 'http:' || fixture.hostname !== '127.0.0.1') throw new Error('Invalid test fixture');
globalThis.fetch = async (input, options) => {
  const source = new URL(input);
  if (source.origin !== ADMIN_ORIGIN || options.redirect !== 'error') throw new Error('Unsafe test request');
  const response = await actual(new URL(source.pathname + source.search, fixture), options);
  return new Response(response.body, { status: response.status, headers: response.headers });
};
