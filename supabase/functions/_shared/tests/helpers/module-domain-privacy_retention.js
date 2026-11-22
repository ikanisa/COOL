import * as actual from '../../domain/privacy_retention.js';
import {wrapFixtureModule} from './fenced-module.js';
const wrapped=wrapFixtureModule('domain/privacy_retention.js',actual);
export const claimRetentionTask=wrapped.claimRetentionTask;
export const executeRetentionTask=wrapped.executeRetentionTask;
export const planRetention=wrapped.planRetention;
