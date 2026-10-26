import * as actual from '../../auth-http.js';
import {wrapFixtureModule} from './fenced-module.js';
const wrapped=wrapFixtureModule('auth-http.js',actual);
export const verifyToken=wrapped.verifyToken;
