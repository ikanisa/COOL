import * as actual from '../../domain/admin_accounts.js';
import {wrapFixtureModule} from './fenced-module.js';
const wrapped=wrapFixtureModule('domain/admin_accounts.js',actual);
export const adminAccountSession=wrapped.adminAccountSession;
export const adminCanonicalActor=wrapped.adminCanonicalActor;
export const handleAdminAccounts=wrapped.handleAdminAccounts;
export const issueAdminSession=wrapped.issueAdminSession;
