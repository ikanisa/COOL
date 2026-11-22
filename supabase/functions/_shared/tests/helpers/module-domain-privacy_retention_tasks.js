import * as actual from '../../domain/privacy_retention_tasks.js';
import {wrapFixtureModule} from './fenced-module.js';
const wrapped=wrapFixtureModule('domain/privacy_retention_tasks.js',actual);
export const retentionObjectSendStart=wrapped.retentionObjectSendStart;
