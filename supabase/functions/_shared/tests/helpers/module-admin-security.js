import * as actual from '../../admin-security.js';
import {wrapFixtureModule} from './fenced-module.js';
const wrapped=wrapFixtureModule('admin-security.js',actual);
export const validateAdminOrigin=wrapped.validateAdminOrigin;
