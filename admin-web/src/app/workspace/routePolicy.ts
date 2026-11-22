import type {ReactElement} from 'react';
import type {RouteObject} from 'react-router';
import type {AdminUser} from '../../session/sessionResponses';

export type WorkspaceAccess = (user: AdminUser) => boolean;
export type WorkspaceRoute = RouteObject & {handle: WorkspaceAccess};

export function workspaceRoute(path: string, element: ReactElement, access: WorkspaceAccess): WorkspaceRoute {
  return {path, caseSensitive: true, element, handle: access};
}

export function requiresPermissions(...permissions: string[]): WorkspaceAccess {
  return user => permissions.every(permission => user.permissions.includes(permission));
}

export function requiresAdminRole(...permissions: string[]): WorkspaceAccess {
  const allowed = requiresPermissions(...permissions);
  return user => user.role !== 'staff' && allowed(user);
}
