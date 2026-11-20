import {isVerifiedCurrentOwner, type AdminUser} from '../session/SessionProvider';
import {canReadRequestHistory} from '../features/requests/permissions';

const areas: Record<string, {read: string; write: string}> = {
  groups: {read: 'collections.read', write: 'collections.manage'},
  users: {read: 'users.read', write: 'users.manage'},
  members: {read: 'users.read', write: 'users.manage'},
  payees: {read: 'receivers.read', write: 'receivers.manage'},
  transactions: {read: 'payments.read', write: 'payments.manage'},
  ledgers: {read: 'ledger.read', write: 'ledger.manage'},
};

/** Presentation guard only; every operation remains server-authorized. */
export function canOpenAdminPath(path: string, user: AdminUser): boolean {
  const allowed = (permission: string) => user.permissions.includes(permission);
  if (path === '/admin') return allowed('overview.read');
  const parts = path.split('/');
  if (parts[0] !== '' || parts[1] !== 'admin' || !parts[2]) return false;
  const area = areas[parts[2]];
  if (area) {
    if (!allowed(area.read)) return false;
    if (parts[2] === 'transactions' && parts[4] === 'reverse') return allowed('payments.reconcile');
    if (parts[2] === 'transactions' && parts[4] === 'allocations' && parts[6] === 'journal' && parts[7] === 'new') return allowed('ledger.read') && allowed('ledger.manage');
    if (parts[2] === 'transactions' && parts[3] === 'new' && user.financialModel === 'transaction_journals') return user.role !== 'staff' && ['payments.manage', 'collections.read', 'receivers.read', 'overview.read'].every(allowed);
    if (parts[2] === 'payees' && parts[4] === 'edit' && user.financialModel === 'transaction_journals') return user.role !== 'staff' && ['receivers.manage', 'collections.read', 'overview.read'].every(allowed);
    if (parts[2] === 'ledgers' && parts[4] === 'post') return allowed('ledger.manage');
    if (parts[2] === 'groups' && parts[4] === 'members' && parts[5] === 'new') return allowed('users.manage');
    if (parts[2] === 'groups' && parts[4] === 'members' && parts[6] === 'edit') return allowed('users.manage');
    if (parts[2] === 'groups' && parts[4] === 'payees' && parts[5] === 'new') return allowed('receivers.manage');
    if (parts[2] === 'groups' && parts[4] === 'ledger-accounts' && parts[5] === 'new') return user.role !== 'staff' && allowed('ledger.read') && allowed('ledger.manage') && allowed('overview.read');
    if (parts[2] === 'groups' && parts[4] === 'journals' && parts[5] === 'new') return user.role !== 'staff' && allowed('ledger.read') && allowed('ledger.manage') && allowed('overview.read');
    if (parts[2] === 'groups' && parts[4] === 'transactions' && parts[5] === 'new') return user.role !== 'staff' && ['payments.read', 'payments.manage', 'receivers.read', 'overview.read'].every(allowed);
    if (parts[3] === 'new') return allowed(parts[2] === 'groups' ? 'collections.create' : area.write);
    if (parts.length >= 5 && parts[parts.length - 1] === 'edit') return allowed(area.write);
    return true;
  }
  switch (parts[2]) {
    case 'reconciliations': return allowed('reconciliations.read');
    case 'momo-receipts': return allowed('sms.read') || allowed('payments.read');
    case 'sms-receipts': return allowed('sms.read');
    case 'notification-settings': return user.role === 'owner' && allowed('admin_users.manage');
    case 'notification-operator': return allowed('assisted_sms.read');
    case 'burimunsi': return user.financialModel === 'canonical_evidence_ledger' && isVerifiedCurrentOwner(user) && ['admin_users.manage', 'receivers.read', 'receivers.manage'].every(allowed);
    case 'email': return allowed('email.read');
    case 'member-receipts': return allowed('payments.read');
    case 'gateway': return allowed('gateway.read') && (parts[3] !== 'new' || allowed('gateway.manage'));
    case 'ledger-accounts': return allowed('ledger.read') && (parts[parts.length - 1] !== 'edit' || allowed('ledger.manage'));
    case 'requests': return canReadRequestHistory(user.financialModel, user.permissions);
    case 'admin-users': return allowed('admin_users.read');
    case 'privacy-requests': return allowed('privacy.review');
    case 'security': return parts.length === 4 && ['verify-email', 'authenticator'].includes(parts[3]) || allowed('account.manage');
    case 'licenses': return true;
    default: return false;
  }
}
