export {HASH, UUID, OperatorError, canonical, hash, integer, keys, need, plain, same, sha, timestamp, uuid} from './wire_values.mjs';
export {ACTIONS, REQUESTS, WRITES, request} from './request_contract.mjs';
export {MARKER, receipt, sanitized} from './receipt_contract.mjs';
export {authorityKey, emailVerification, hasFreshEmailVerification, publicSession, sensitiveAuthorityKey} from './authority_contract.mjs';

export const CONTRACT_SHA = '9c88f77dacb0f5757f09b8a246b115462b2e25c135de6807c68df33d6ece534e';
export const ORIGINS = Object.freeze(['https://platform-admin.collect.ikanisa.com','https://admin-supabase-qa.collect.ikanisa.com']);
