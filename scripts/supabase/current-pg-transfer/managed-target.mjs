// Fixed managed database transport for read-only reconciliation. The peer
// check is an admission check on a trusted pg Client, not host attestation.
import {hasPinnedProviderSSL,loadProviderRoot} from '../managed-cloud-migrations/provider-ca.mjs';

const PROJECT='rrlduytparvsjfmegalh';
const DIRECT=`db.${PROJECT}.supabase.co`;
const POOLER='aws-0-eu-north-1.pooler.supabase.com';

export function isManagedReconciliationTarget({host,port,database,user}={}) {
  return database==='postgres' && Number(port)===5432 &&
    ((host===DIRECT && user==='postgres') || (host===POOLER && user===`postgres.${PROJECT}`));
}

export function managedReconciliationSsl() {
  return {rejectUnauthorized:true,ca:loadProviderRoot()};
}

export function isManagedReconciliationPeer(parameters,stream) {
  return !!parameters && isManagedReconciliationTarget(parameters) &&
    hasPinnedProviderSSL(parameters.ssl) && stream?.encrypted===true &&
    stream.authorized===true && stream.servername===parameters.host;
}
