import * as actual from '../../domain/google_auth.js';
import {wrapFixtureModule} from './fenced-module.js';
const wrapped=wrapFixtureModule('domain/google_auth.js',actual);
export const GOOGLE_APPLICATION_CALLBACK=wrapped.GOOGLE_APPLICATION_CALLBACK;
export const GOOGLE_PROJECT_ORIGIN=wrapped.GOOGLE_PROJECT_ORIGIN;
export const callbackResult=wrapped.callbackResult;
export const exchangeGoogleFlow=wrapped.exchangeGoogleFlow;
export const handleGoogleAuth=wrapped.handleGoogleAuth;
export const startGoogleFlow=wrapped.startGoogleFlow;
