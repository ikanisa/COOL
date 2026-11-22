// Offline compilation using only the repository's reviewed retention selectors.
import {readFile, writeFile} from 'node:fs/promises';
import * as app from '../../supabase/functions/_shared/domain/privacy_retention_catalog.js';
import {
  privateRetentionExpressions, privateRetentionSelection,
} from '../../supabase/functions/_shared/private-retention.js';

const schemaSource = new URL('../../supabase/schema-src/', import.meta.url);
const migrations = new URL('../../supabase/migrations/', import.meta.url);
const inventorySource = new URL('../../supabase/retention-inventory.json', import.meta.url);

const inventoryMigration = '20261101014231_collect_retention_inventory_manifests.sql';
const rowExecutorMigration = '20261101020642_collect_retention_row_executor.sql';
const smsFenceMigration = '20261101030502_collect_sms_application_fence.sql';
const gatewayMigration = '20261101012503_collect_sms_gateway.sql';
const laterPrivateClasses = new Set([
  'private:collect_fence_local_stopped_admissions', // 20261110181002
  'private:collect_managed_job_tickets',           // 20261117073850
]);
const smsFenceClass = 'private:collect_sms_fence_admissions';

const readSource = (directory, file) => readFile(new URL(file, directory), 'utf8');
const asJson = value => JSON.stringify(value, null, 2) + '\n';
const asPostgres = sql => sql.replaceAll('?', '$1');

function applicationCatalog() {
  const columns = {
    ...app.retentionColumns,
    ...app.momoPipelineRetentionColumns,
    ...app.momoFinancialRetentionColumns,
    ...app.googleAuthRetentionColumns,
    ...app.adminOtpRetentionColumns,
    ...app.adminEmailRetentionColumns,
    ...app.diagnosticRetentionColumns,
    ...app.notificationDeliveryRetentionColumns,
    ...app.notificationChannelRetentionColumns,
  };
  return Object.fromEntries(Object.keys(columns).sort().map(name => [name, {
    columns: columns[name],
    where: asPostgres(app.retentionSelection(name, 'subject', columns).sql),
  }]));
}

function privateCatalog(inventory) {
  return inventory.classes
    .filter(entry => entry.relation.startsWith('private.') && !laterPrivateClasses.has(entry.name))
    .map(entry => {
      if (entry.scope === 'shared_fence' || entry.scope === 'shared_realtime') {
        return {...entry, blocked: true};
      }
      return {
        ...entry,
        where: asPostgres(privateRetentionSelection(entry, 'subject').where),
        ...privateRetentionExpressions(entry),
      };
    });
}

function gatewayTablesFrom(sql) {
  const names = [...sql.matchAll(/CREATE TABLE (?:collect_sms\.)?([a-z0-9_]+)/g)]
    .map(match => match[1]).sort();
  if (names.length !== 29 || new Set(names).size !== names.length) {
    throw new Error('Exact SMS gateway table catalog changed');
  }
  return names;
}

function catalogFunction(catalogText, {replace = false} = {}) {
  const create = replace ? 'CREATE OR REPLACE' : 'CREATE';
  return create +
    ' FUNCTION private._retention_manifest_catalog_v2() RETURNS jsonb LANGUAGE sql IMMUTABLE' +
    ' SET search_path=pg_catalog,pg_temp AS $function$\n' +
    ' SELECT $catalog$' + catalogText + '$catalog$::jsonb\n' +
    '$function$;';
}

function fillMarker(template, marker, sql) {
  if (template.split(marker).length !== 2) throw new Error('Expected one template marker: ' + marker);
  return template.replace(marker, () => sql);
}

async function compileCatalog() {
  const [inventory, gatewaySql] = await Promise.all([
    readFile(inventorySource, 'utf8').then(JSON.parse),
    readSource(migrations, gatewayMigration),
  ]);
  const application = applicationCatalog();
  const privateClasses = privateCatalog(inventory);
  const gatewayTables = gatewayTablesFrom(gatewaySql);
  const catalog = {
    contract: 'collect.retention.descriptor-catalog.v2',
    application,
    engine_tables: app.engineTables,
    private_classes: privateClasses,
    copy_classes: app.copyClasses,
    gateway_tables: gatewayTables,
  };
  // Retain the original inventory migration. The later SMS fence migration
  // carries the added ownership-journal classification.
  const original = {...catalog, private_classes: privateClasses.filter(entry => entry.name !== smsFenceClass)};
  const catalogText = asJson(catalog);
  const additiveSql = '-- Generated exact shared SMS admission classification; no erasure authority.\n' +
    catalogFunction(catalogText, {replace: true}) + '\n';
  const summary = {
    application_tables: Object.keys(application).length,
    private_classes: privateClasses.length,
    gateway_tables: gatewayTables.length,
    compiled: true,
  };
  return {originalFunction: catalogFunction(asJson(original)), catalogText, additiveSql, summary};
}

async function verifyRetainedMigrations({originalFunction, additiveSql}) {
  const [inventoryTemplate, rowTemplate, rowExecution, existingInventory, existingRow, existingFence] =
    await Promise.all([
      readSource(schemaSource, 'retention-inventory-manifests.sql'),
      readSource(schemaSource, 'retention-row-executor.sql'),
      readSource(schemaSource, 'retention-row-execution.sql'),
      readSource(migrations, inventoryMigration),
      readSource(migrations, rowExecutorMigration),
      readSource(migrations, smsFenceMigration),
    ]);
  if (fillMarker(inventoryTemplate, '-- COMPILED_CATALOG_FUNCTION', originalFunction) !== existingInventory) {
    throw new Error('Retained inventory migration differs from its generated SQL: ' + inventoryMigration);
  }
  if (fillMarker(rowTemplate, '-- EXECUTION_FUNCTIONS', rowExecution) !== existingRow) {
    throw new Error('Retained row executor migration differs from its generated SQL: ' + rowExecutorMigration);
  }
  if (!existingFence.includes(additiveSql)) {
    throw new Error('Retained SMS fence migration differs from its generated catalog: ' + smsFenceMigration);
  }
}

const args = process.argv.slice(2);
if (args.length && (args.length !== 1 || args[0] !== '--check')) {
  throw new Error('Usage: node scripts/supabase/compile-retention-manifest-catalog.mjs [--check]');
}
const compiled = await compileCatalog();
await verifyRetainedMigrations(compiled);

const generated = [
  ['retention-manifest-catalog.json', compiled.catalogText],
  ['sms-fence-retention-catalog.sql', compiled.additiveSql],
];
for (const [name, expected] of generated) {
  if (args.length) {
    if (await readSource(schemaSource, name) !== expected) {
      throw new Error('Retention generated source drift: ' + name);
    }
  } else {
    await writeFile(new URL(name, schemaSource), expected, 'utf8');
  }
}
console.log(JSON.stringify(compiled.summary));
