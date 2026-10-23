import * as actual from '../../domain/admin_invitation.js';
import {wrapFixtureModule} from './fenced-module.js';
const wrapped=wrapFixtureModule('domain/admin_invitation.js',actual);
export const handleAdminInvitation=wrapped.handleAdminInvitation;
