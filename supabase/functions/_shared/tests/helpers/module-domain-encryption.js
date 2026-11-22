import * as actual from '../../domain/encryption.js';
import {wrapFixtureModule} from './fenced-module.js';
const wrapped=wrapFixtureModule('domain/encryption.js',actual);
export const encrypt=wrapped.encrypt;
