from pathlib import Path
import hashlib,difflib,json
root=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL');out=root/'docs/release/rapid-completion-2026-10-01/current-admin-browser-current1'
p=root/'scripts/qa/current_browser_lifecycle.mjs';before=(out/'current_browser_lifecycle.before.mjs').read_text();assert p.read_text()==before
s=before.replace("const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');", "const workspaceRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../..');\n// Read immutable candidate inputs while keeping mutable builds outside checkout.\nconst root = resolve(process.env.COLLECT_BROWSER_SOURCE_ROOT || workspaceRoot);")
s=s.replace('buildRoot === root','buildRoot === workspaceRoot')
s=s.replace("  sources_before: await snapshot(), commands: [], checks: [], errors: [], blocked_outbound_requests: [],", "  sources_before: await snapshot(), source_root: root, build_root: buildRoot,\n  executing_harness_sha256: hash(await readFile(fileURLToPath(import.meta.url))),\n  executing_fixture_sha256: hash(await readFile(join(workspaceRoot, 'scripts/qa/local_browser_api_fixture.mjs'))),\n  commands: [], checks: [], route_states: [], errors: [], blocked_outbound_requests: [],")
s=s.replace("    installed_pwa: false },", "    installed_pwa: false, signed_out_all_routes: false, authenticated_all_routes: false },")
needle="  await login(page); check('email-sign-in-keeps-admin-route', new URL(page.url()).hash.startsWith('#/admin'));"
assert s.count(needle)==1
routes=r'''  const routerSource = await readFile(join(root, 'lib/admin/admin_router.dart'), 'utf8');
  const declaredBlock = routerSource.match(/const adminRoutePaths = <String>\[([\s\S]*?)\];/);
  if (!declaredBlock) throw Error('Current Admin route declaration missing');
  const declaredRoutes = [...declaredBlock[1].matchAll(/'([^']+)'/g)].map(value => value[1]);
  const recordId = '99690000-0000-4000-8000-000000090001';
  const failure = 'The admin request could not be completed.';
  // Exact enabled route/state contract. Empty lists and deliberately unavailable
  // synthetic reads prove recovery UI, not real server/populated/action outcomes.
  const routeStates = {
    '/admin/login': ['Collect admin login', 'login'],
    '/admin/denied': ['Admin access required', 'denied'],
    '/admin': ['Local synthetic receipts', 'synthetic-summary'],
    '/admin/groups': ['No groups', 'empty'],
    '/admin/groups/:id': [failure, 'unavailable-read'],
    '/admin/users': ['No users', 'empty'],
    '/admin/users/:id': [failure, 'unavailable-read'],
    '/admin/members': ['No members', 'empty'],
    '/admin/members/:id': [failure, 'unavailable-read'],
    '/admin/payees': ['No payees', 'empty'],
    '/admin/transactions': ['No transactions', 'empty'],
    '/admin/transactions/:id': [failure, 'unavailable-read'],
    '/admin/reconciliations': [failure, 'unavailable-read'],
    '/admin/ledgers': ['No ledgers', 'empty'],
    '/admin/sms-receipts': ['No sms receipts', 'empty'],
    '/admin/sms-receipts/:id': [failure, 'unavailable-read'],
    '/admin/notifications': ['No notifications', 'empty'],
    '/admin/notifications/:id': [failure, 'unavailable-read'],
    '/admin/audit-logs': ['No audit logs', 'empty'],
    '/admin/audit-logs/entity/:kind/:id': ['Action history service unavailable', 'unavailable-read'],
    '/admin/settings': ['No settings', 'empty'],
    '/admin/feature-flags': ['No feature flags', 'empty'],
    '/admin/system-health': [failure, 'unavailable-read'],
    '/admin/automations': ['Receipt operations policy service is unavailable.', 'unavailable-policy'],
    '/admin/sms-gateway': ['Gateway read failed', 'invalid-synthetic-read-refused'],
    '/admin/exceptions': ['Exception read failed', 'invalid-synthetic-read-refused'],
    '/admin/admin-users': ['No admin users', 'empty'],
    '/admin/admin-users/:id': [failure, 'unavailable-read'],
  };
  check('current-route-contract-covers-declared28', declaredRoutes.length === 28
    && JSON.stringify([...declaredRoutes].sort()) === JSON.stringify(Object.keys(routeStates).sort()));
  function concreteRoute(pattern) {
    const id = pattern === '/admin/transactions/:id' ? encodeURIComponent('momo:' + recordId) : recordId;
    return pattern.replace(':kind', 'gateway_device').replace(':id', id);
  }
  async function navigateHash(path) {
    await page.evaluate(value => { location.hash = value; }, path);
  }
  const beforeSignedOutRoutes = fixture.calls.length;
  for (const pattern of declaredRoutes) {
    await navigateHash(concreteRoute(pattern));
    await page.waitForFunction(() => location.hash === '#/admin/login');
    await visible(page, 'Collect admin login');
    check('signed-out-route:' + pattern, noCredentials(await storage(page)));
    report.route_states.push({ pattern, authority: 'signed-out', actual_path: new URL(page.url()).hash,
      state: 'login', status: 'pass' });
  }
  check('signed-out-routes-dispatch-no-private-rpc', !fixture.calls.slice(beforeSignedOutRoutes)
    .some(value => !['otp', 'verify', 'user', 'logout'].includes(value.action)));
  report.coverage.signed_out_all_routes = true;
  await navigateHash('/admin/groups');
  await login(page);
  for (const pattern of declaredRoutes) {
    const path = concreteRoute(pattern), [expected, state] = routeStates[pattern];
    const beforeCalls = fixture.calls.length;
    await navigateHash(path);
    await page.waitForFunction(value => decodeURIComponent(location.hash.slice(1)) === decodeURIComponent(value), path);
    await visible(page, expected);
    check('authenticated-route:' + pattern, noCredentials(await storage(page)), { state, expected });
    report.route_states.push({ pattern, authority: 'authenticated-email-owner', actual_path: new URL(page.url()).hash,
      state, expected, calls: fixture.calls.slice(beforeCalls).map(value => value.action), status: 'pass' });
    if (['/admin/sms-gateway', '/admin/exceptions', '/admin/automations', '/admin/audit-logs/entity/:kind/:id'].includes(pattern)) {
      await page.screenshot({ path: join(output, 'route-' + pattern.replace(/[^a-z0-9]/gi, '_') + '.png'), fullPage: true });
    }
  }
  report.coverage.authenticated_all_routes = true;
  await navigateHash('/admin/groups');
  await visible(page, 'No groups');
  check('email-sign-in-keeps-admin-route', new URL(page.url()).hash.startsWith('#/admin'));'''
s=s.replace(needle,routes)
p.write_text(s)
(out/'current_browser_lifecycle.diff').write_text(''.join(difflib.unified_diff(before.splitlines(True),s.splitlines(True),fromfile='a/scripts/qa/current_browser_lifecycle.mjs',tofile='b/scripts/qa/current_browser_lifecycle.mjs')))
(out/'harness-scope.json').write_text(json.dumps({'before_sha256':hashlib.sha256(before.encode()).hexdigest(),'after_sha256':hashlib.sha256(s.encode()).hexdigest(),'runtime_changed':False,'direct_vm_source_contract_consumers':[],'affected_node_fixture_boundary':'scripts/tests/local_browser_email_fixture_test.mjs','scope':'Immutable source-root binding and28route signed-out/authenticated state checks; no source/provider/visual closure implied'},indent=2)+'\n')
copy=json.loads((out/'copied-inputs.json').read_text());dest=Path(copy['build_root'])
(dest/'scripts/qa/current_browser_lifecycle.mjs').write_text(s)
assert (dest/'scripts/qa/local_browser_api_fixture.mjs').read_bytes()==(root/'scripts/qa/local_browser_api_fixture.mjs').read_bytes()
