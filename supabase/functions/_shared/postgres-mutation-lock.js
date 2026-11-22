// Existing SQL routines and older runtimes take this key exclusively. Scoped
// writers hold it in shared mode before their feature lock or row locks.
export const COLLECT_MUTATION_LOCK = '734636924058501';

export function lockCollectMutation(tx) {
  return tx.unsafe(`SELECT pg_advisory_xact_lock(${COLLECT_MUTATION_LOCK}::bigint)`);
}

export function joinCollectMutation(tx) {
  return tx.unsafe(`SELECT pg_catalog.pg_advisory_xact_lock_shared(${COLLECT_MUTATION_LOCK}::bigint)`);
}

export async function lockAdminSessionMutation(tx, tokenHash) {
  await joinCollectMutation(tx);
  await tx.unsafe('SELECT pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended($1::text,7346380))', [tokenHash]);
}
