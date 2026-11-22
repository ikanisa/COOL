import {test} from 'node:test';
import assert from 'node:assert/strict';
import {adminRpc as legacyRpc} from '../src/admin.js';

// Direct handler checks only; actual HTTP/session, backed policy and alerting
// require separate qualification. The database must not be used by this stub.
const noDb={DB:{prepare(){throw new Error('unexpected database access');}}};
const overview={permissions:new Set(['overview.read'])};
for (const [target, adminRpc] of [['legacy-worker',legacyRpc]]) {
  for (const queue of ['admin_list_notifications','admin_list_collect_reconciliations']) {
    test(`${target}: unavailable SLA is an error for ${queue}`, async () => {
      await assert.rejects(()=>adminRpc('admin_get_queue_sla',{p_queue_key:queue},noDb,overview),
        error=>error.status===503 && error.code==='queue_sla_unavailable');
    });
  }
  for (const [label, actor] of [['no permissions',{permissions:new Set()}],
    ['settings only',{permissions:new Set(['settings.read'])}]]) {
    test(`${target}: ${label} cannot request SLA`, async () => {
      await assert.rejects(()=>adminRpc('admin_get_queue_sla',{p_queue_key:'admin_list_notifications'},noDb,actor),
        error=>error.status===403 && error.code==='42501');
    });
  }
  test(`${target}: unrelated authorized runtime configuration still responds`, async () => {
    const result=await adminRpc('admin_runtime_config',{},noDb,overview);
    assert.equal(result.handled,true);
    assert.ok(Array.isArray(result.value.navigation_items));
  });
  test(`${target}: an unregistered handler remains unhandled`, async () => {
    assert.deepEqual(await adminRpc('not_registered',{},noDb,overview),{handled:false});
  });
}
