// Fresh fixture entry point for the reviewed schema and SQL acceptance suites.
import {dirname} from 'node:path';
import {runDefaultSchema} from '../../scripts/supabase/test_schema.mjs';

const connectionString = process.env.COLLECT_SCHEMA_TEST_URL;
if (!connectionString) {
  throw new Error('Set COLLECT_SCHEMA_TEST_URL for a dedicated local collect_*_test database.');
}
const pgModule = process.env.COLLECT_PG_MODULE;
if (!pgModule) throw new Error('Set COLLECT_PG_MODULE to the pinned local pg module directory or package.json.');

await runDefaultSchema({
  connectionString,
  pgModule: pgModule.endsWith('/package.json') ? dirname(pgModule) : pgModule,
  requireFresh: true,
});
