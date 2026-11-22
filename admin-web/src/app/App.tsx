import {useMemo} from 'react';
import {createHashRouter, Navigate, RouterProvider} from 'react-router';
import type {AdminNavItem} from '../layout/AdminShell';
import {ProtectedShell, publicSessionRoutes} from './SessionRoutes';
import {UnavailablePage} from './UnavailablePage';
import {workspaceRoutes} from './WorkspaceRoutes';
import './transaction-view.css';

const navigation: readonly AdminNavItem[] = [
  {label: 'Overview', path: '/admin', section: 'Workspace', icon: 'home'},
  {label: 'Groups', path: '/admin/groups', section: 'Workspace', icon: 'users'},
  {label: 'Users', path: '/admin/users', section: 'People', icon: 'user'},
  {label: 'Members', path: '/admin/members', section: 'People', icon: 'users'},
  {label: 'Payees', path: '/admin/payees', section: 'People', icon: 'contact'},
  {label: 'Transactions', path: '/admin/transactions', section: 'Operations', icon: 'swap'},
  {label: 'Reconciliations', path: '/admin/reconciliations', section: 'Operations', icon: 'layers'},
  {label: 'Ledgers', path: '/admin/ledgers', section: 'Operations', icon: 'book'},
  {label: 'SMS receipts', path: '/admin/sms-receipts', section: 'Communications', icon: 'message'},
  {label: 'MoMo receipts', path: '/admin/momo-receipts', section: 'Communications', icon: 'message'},
  {label: 'Assisted SMS', path: '/admin/notification-operator', section: 'Communications', icon: 'message'},
  {label: 'SMS controls', path: '/admin/notification-settings', section: 'Communications', icon: 'settings'},
  {label: 'Gateway devices', path: '/admin/gateway', section: 'Communications', icon: 'smartphone'},
  {label: 'Member receipts', path: '/admin/member-receipts', section: 'Communications', icon: 'file'},
  {label: 'Email notifications', path: '/admin/email', section: 'Communications', icon: 'message'},
  {label: 'Request history', path: '/admin/requests', section: 'Administration', icon: 'clock'},
  {label: 'Privacy requests', path: '/admin/privacy-requests', section: 'Administration', icon: 'lock'},
  {label: 'Admins and staff', path: '/admin/admin-users', section: 'Administration', icon: 'users'},
  {label: 'BuriMunsi access', path: '/admin/burimunsi', section: 'Administration', icon: 'lock'},
  {label: 'Password and security', path: '/admin/security', section: 'Administration', icon: 'settings'},
];

export function makeAdminRouter(setup: {token: string; invite: boolean} | null) {
  return createHashRouter([
    {path: '/', element: <Navigate to="/admin" replace />},
    ...publicSessionRoutes(setup),
    {path: '/admin', caseSensitive: true, element: <ProtectedShell navigation={navigation} />, children: workspaceRoutes},
    {path: '*', element: <UnavailablePage title="Page unavailable" />},
  ]);
}

export function AdminApp({setup}: {setup: {token: string; invite: boolean} | null}) {
  const router = useMemo(() => makeAdminRouter(setup), [setup]);
  return <RouterProvider router={router} />;
}
