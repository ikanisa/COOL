import test from 'node:test';
import assert from 'node:assert/strict';
import {setupFixture} from './scope-setup-fixture.mjs';
import '../helpers/node-postgres-import.mjs';

const {compileSql} = await import('../../postgres.js');

for (const operation of ['prepare', 'activate']) {
 test(`scope ${operation} keeps JSON transport as text before PostgreSQL jsonb conversion`, async () => {
  const fixture = setupFixture();
  const command = fixture[operation];
  await fixture.service.apply(command);
  const statement = fixture.state.calls.find(call => call.sql.includes('burimunsi_setup_apply'));
  assert.ok(statement);
  const compiled = compileSql(statement.sql, statement.values);
  assert.equal(compiled.text,
   'SELECT private.burimunsi_setup_apply($1,$2,$3,$4,$5::text::jsonb,$6,$7::text::jsonb) AS result');
  assert.equal(compiled.values.length, 7);
  assert.deepEqual(JSON.parse(compiled.values[4]), command);
  assert.match(compiled.values[5], /^[a-f0-9]{64}$/);
  if (operation === 'prepare') {
   assert.equal(compiled.values[6], null);
  } else {
   const delivery = JSON.parse(compiled.values[6]);
   assert.equal(delivery.binding.requestId, command.requestId);
   assert.equal(delivery.binding.collectionId, command.collectionId);
   assert.equal(typeof delivery.ciphertext, 'string');
  }
 });
}
