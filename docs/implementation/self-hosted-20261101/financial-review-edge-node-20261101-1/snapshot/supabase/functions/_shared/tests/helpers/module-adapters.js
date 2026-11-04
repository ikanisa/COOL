import * as actual from '../../adapters.js';
import {wrapFixtureModule} from './fenced-module.js';
const wrapped=wrapFixtureModule('adapters.js',actual);
export const SupabaseObjectBucket=wrapped.SupabaseObjectBucket;
