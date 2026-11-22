import { capabilityName } from '../api.mjs';
import { UUID, invalid, isUuid, object, strictKeys, unavailable } from '../config.mjs';
import { PERMISSIONS, RELATIONS, area, areaProperty, boundPage, listFilters, marker, page, pageQuery,
  paging, readTool, record, schema, validatePage } from './contracts.mjs';

function listRecords(args) {
  strictKeys(args, ['area', 'search', 'status', 'sort', 'limit', 'offset']);
  const kind = area(args.area), { requested, query } = listFilters(args, kind);
  return {
    permission: PERMISSIONS[kind],
    read: async ({ get }) => validatePage(await get(`/api/admin/core/${kind}?${query}`), requested),
  };
}

function getRecord(args) {
  strictKeys(args, ['area', 'id', 'relation', 'limit', 'offset']);
  const kind = area(args.area), requested = paging(args), { id, relation } = args;
  if (!isUuid(id) || relation !== undefined && !RELATIONS[kind].includes(relation) ||
      relation === undefined && (args.limit !== undefined || args.offset !== undefined)) invalid();
  const query = relation === undefined ? '' : `?${pageQuery(requested, { relation })}`;
  return {
    permission: PERMISSIONS[kind],
    read: async ({ get }) => {
      const value = await get(`/api/admin/operations/${kind}/${id}${query}`);
      marker(value);
      if (value.resource_type !== kind || !object(value.related) || !object(value.related_pages)) unavailable();
      record(value.resource);
      if (value.resource.id !== id) unavailable();
      for (const [name, records] of Object.entries(value.related)) {
        if (!RELATIONS[kind].includes(name)) unavailable();
        boundPage(records, value.related_pages[name]);
        records.forEach(record);
      }
      return value;
    },
  };
}

export const recordTools = [
  readTool('collect_admin_session', 'Current Admin access',
    'Verify the current operator, role and actual granted read capabilities. Does not sign in or return the cookie.',
    schema(), args => {
      strictKeys(args, []);
      return { read: async ({ user }) => ({ account: user, read_only: true }) };
    }),
  readTool('collect_admin_overview', 'Workspace overview',
    'Read measured canonical workspace totals; amounts are recorded evidence, not provider settlement.',
    schema(), args => {
      strictKeys(args, []);
      return {
        permission: 'overview.read',
        read: async ({ get }) => {
          const value = await get('/api/admin/core/overview?country=RW');
          marker(value);
          if (!Array.isArray(value.metrics) || value.metrics.length > 100) unavailable();
          return value;
        },
      };
    }),
  readTool('collect_admin_list_records', 'List Admin records',
    'Read one bounded page of Groups, Users, Members, Payees, Transactions or Ledgers. Server search supports quoted phrases, status and type filters. Pagination does not aggregate all records.',
    schema({ area: areaProperty, search: { type: 'string', maxLength: 200 },
      status: { type: 'string', maxLength: 32 }, sort: { type: 'string', maxLength: 80,
        description: 'An actual area ordering field followed by _asc or _desc; default created_at_desc.' }, ...page }, ['area']), listRecords),
  readTool('collect_admin_get_record', 'Get Admin record',
    'Read an exact record UUID and authorized related metadata. Optionally read one related page. Does not retrieve evidence binaries or execute returned allowed_operations.',
    schema({ area: areaProperty, id: { type: 'string', pattern: UUID.source },
      relation: { type: 'string', enum: ['memberships', 'payees', 'evidence', 'ledger_entries'] }, ...page }, ['area', 'id']), getRecord),
];

const roles = ['owner', 'admin', 'staff'];
export const teamTool = readTool('collect_admin_team_access', 'Admin and Staff access review',
  'Read the actual canonical team list and capability matrix for the current account. The backend route has no pagination; this adapter fails closed above 200 team rows instead of truncating. This cannot invite, revoke, change roles or grant access.',
  schema(), args => {
    strictKeys(args, []);
    return {
      permission: 'admin_users.read',
      read: async ({ get, user }) => {
        const value = await get('/api/admin/team');
        if (value.currentEmail !== user.email || typeof value.canManage !== 'boolean' || !object(value.permissionsByRole) ||
            !Array.isArray(value.members) || value.members.length > 200) unavailable();
        for (const role of roles) {
          const capabilities = value.permissionsByRole[role];
          if (!Array.isArray(capabilities) || capabilities.length > 256 || capabilities.some(cap => !capabilityName(cap))) unavailable();
        }
        for (const member of value.members) {
          if (!object(member) || !isUuid(member.id) || !roles.includes(member.role) ||
              !['active', 'invited', 'revoked'].includes(member.status) || typeof member.email !== 'string' || member.email.length > 254) unavailable();
        }
        const current = value.members.find(member => member.id === user.id);
        if (!current || current.email !== user.email || current.role !== user.role || current.status !== 'active' ||
            value.canManage && (user.role !== 'owner' || user.assuranceLevel !== 2 || !user.permissions.includes('admin_users.manage'))) unavailable();
        return value;
      },
    };
  });
