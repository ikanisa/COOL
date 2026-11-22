import { UUID, invalid, isUuid, object, strictKeys, unavailable } from '../config.mjs';
import { boundPage, listFilters, marker, page, pageQuery, paging, readTool, record, schema,
  validSearch, validatePage } from './contracts.mjs';

const relations = ['evidence', 'proposals', 'ledger_entries'];
const queuePermissions = ['reconciliations.read', 'payments.read'];
const memberPermissions = [...queuePermissions, 'users.read'];

function listQueue(args) {
  strictKeys(args, ['search', 'status', 'sort', 'limit', 'offset']);
  const { requested, query } = listFilters(args, 'transactions');
  return {
    permission: queuePermissions,
    read: async ({ get }) => validatePage(await get(`/api/admin/reconciliations?${query}`), requested),
  };
}

function getDetail(args) {
  strictKeys(args, ['transaction_id', 'relation', 'limit', 'offset']);
  const requested = paging(args), { transaction_id: id, relation } = args;
  if (!isUuid(id) || relation !== undefined && !relations.includes(relation)) invalid();
  const query = pageQuery(requested, relation ? { relation } : {});
  return {
    permission: relation === 'ledger_entries' ? [...memberPermissions, 'ledger.read'] : memberPermissions,
    read: async ({ get, user }) => {
      const value = await get(`/api/admin/reconciliations/${id}?${query}`);
      marker(value);
      if (value.resource_type !== 'reconciliations' || value.resource?.id !== id || !object(value.related) ||
          value.current_actor_id !== user.id || value.current_principal_id !== user.principalId) unavailable();
      for (const [name, related] of Object.entries(value.related)) {
        if (!relations.includes(name) || !object(related) || related.limit !== requested.limit || related.offset !== requested.offset) unavailable();
        boundPage(related.rows, related);
        related.rows.forEach(record);
      }
      if (relation && !Object.hasOwn(value.related, relation)) unavailable();
      return value;
    },
  };
}

function listMembers(args) {
  strictKeys(args, ['transaction_id', 'search', 'limit', 'offset']);
  const requested = paging(args), search = args.search ?? '', id = args.transaction_id;
  if (!isUuid(id) || !validSearch(search)) invalid();
  const query = pageQuery(requested, { transaction_id: id, search });
  return {
    permission: memberPermissions,
    read: async ({ get }) => {
      const value = await get(`/api/admin/reconciliations/members?${query}`);
      marker(value);
      if (value.transaction_id !== id || value.limit !== requested.limit || value.offset !== requested.offset) unavailable();
      boundPage(value.rows, value);
      for (const candidate of value.rows) {
        if (!object(candidate) || !isUuid(candidate.member_user_id) || !isUuid(candidate.group_id) ||
            !Number.isSafeInteger(candidate.member_version) || candidate.member_version < 1 ||
            !Number.isSafeInteger(candidate.membership_version) || candidate.membership_version < 1 ||
            !Number.isSafeInteger(candidate.group_version) || candidate.group_version < 1 || !object(candidate.payment_identity)) unavailable();
      }
      return value;
    },
  };
}

const transactionId = { type: 'string', pattern: UUID.source };
const search = { type: 'string', maxLength: 200 };
export const reconciliationTools = [
  readTool('collect_admin_list_reconciliations', 'Reconciliation queue',
    'Read one bounded page of the actual canonical reconciliation queue, preserving transaction search/status/order semantics. Does not propose or review attribution.',
    schema({ search, status: { type: 'string', maxLength: 32 }, sort: { type: 'string', maxLength: 80 }, ...page }), listQueue),
  readTool('collect_admin_get_reconciliation', 'Reconciliation details',
    'Read an exact transaction’s reconciliation evidence metadata, retained proposals and authorized ledger entries. Optionally read one related page. Does not approve, reject, reverse or allocate.',
    schema({ transaction_id: transactionId, relation: { type: 'string', enum: relations }, ...page }, ['transaction_id']), getDetail),
  readTool('collect_admin_list_reconciliation_members', 'Scoped reconciliation member candidates',
    'Read candidates scoped by the actual backend to one exact transaction’s active group and recorded payment identity. A candidate is not an approved attribution.',
    schema({ transaction_id: transactionId, search, ...page }, ['transaction_id']), listMembers),
];
