import * as actual from '../../auth-cleanup.js';
import {wrapFixtureModule} from './fenced-module.js';
const wrapped=wrapFixtureModule('auth-cleanup.js',actual);
export const cleanupExpiredGoogleFlows=wrapped.cleanupExpiredGoogleFlows;
