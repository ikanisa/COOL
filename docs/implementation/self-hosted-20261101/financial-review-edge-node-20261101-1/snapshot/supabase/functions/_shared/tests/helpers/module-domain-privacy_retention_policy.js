import * as actual from '../../domain/privacy_retention_policy.js';
import {wrapFixtureModule} from './fenced-module.js';
const wrapped=wrapFixtureModule('domain/privacy_retention_policy.js',actual);
export const actorGuard=wrapped.actorGuard;
export const loadRetentionPolicy=wrapped.loadRetentionPolicy;
