import {matchRoutes, type RouteObject} from 'react-router';
import type {AdminUser} from '../session/sessionResponses';
import {workspaceRoutes} from './WorkspaceRoutes';

const protectedRoutes: RouteObject[] = [{path: '/admin', caseSensitive: true, children: workspaceRoutes}];

/** Presentation guard only; every operation remains server-authorized. */
export function canOpenAdminPath(path: string, user: AdminUser): boolean {
  const matches = matchRoutes(protectedRoutes, path);
  const access = matches?.at(-1)?.route.handle;
  return typeof access === 'function' && access(user) === true;
}
