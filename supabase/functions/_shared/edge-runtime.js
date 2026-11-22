import {SupabaseObjectBucket, providerAdapters} from './adapters.js';
import {sqlFenceBackend} from './application-fence.js';
import {assertRuntimeDeployment} from './deployment-database.js';
import {connection, fenceConnection} from './postgres-connections.js';
import {PostgresDatabase} from './postgres.js';

// Keep the lifecycle stage with the request. Both entry points report failures
// using these same labels and keep the admission open for background work.
export class EdgeRuntimeWork {
  stage = 'environment';
  work;

  async initializeDatabase(env) {
    this.stage = 'database_initialization';
    env.DB = new PostgresDatabase(connection(env.COLLECT_DATABASE_URL, env));
    await assertRuntimeDeployment(env.DB.sql, env);
  }

  async admit(env, openWork, kind, signal) {
    this.stage = 'fence_admission';
    this.work = await openWork({
      backend: sqlFenceBackend(env.DB.sql, fenceConnection(env.COLLECT_DATABASE_URL, env)),
      sourceSha256: env.BUILD_SOURCE_ID,
      kind,
      ...(signal === undefined ? {} : {signal}),
    });
    env.COLLECT_FENCE_WORK = this.work;
    env.DB.setApplicationWork(this.work);
    return this.work;
  }

  initializeAdapters(env) {
    this.stage = 'storage_initialization';
    env.PRIVATE_MEDIA = new SupabaseObjectBucket(env);
    this.stage = 'provider_initialization';
    Object.assign(env, providerAdapters(env));
  }

  waitUntil(promise) {
    this.work.waitUntil(promise);
    if (typeof EdgeRuntime !== 'undefined') {
      EdgeRuntime.waitUntil(Promise.resolve(promise).catch(() => {}));
    }
  }

  finish() {
    if (!this.work) return;
    const done = this.work.finish().catch(() => {
      console.error(JSON.stringify({
        service: 'collect_platform_api',
        event: 'application_work_close_unconfirmed',
        scope: 'application_only',
      }));
    });
    if (typeof EdgeRuntime !== 'undefined') EdgeRuntime.waitUntil(done);
  }
}

export function isFenceFailure(error) {
  return error?.code === 'application_fenced' || error?.code === 'application_fence_unavailable';
}

// Health observations never change an admitted response or application work.
export function observeFailure(report, value) {
  try {
    report(value);
  } catch {
    // Health reporting must leave the original outcome intact.
  }
}
