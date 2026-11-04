import * as actual from '../../domain/privacy.js';
import {wrapFixtureModule} from './fenced-module.js';
const wrapped=wrapFixtureModule('domain/privacy.js',actual);
export const privacyRpc=wrapped.privacyRpc;
