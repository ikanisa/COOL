import * as actual from '../../domain/auth.js';
import {wrapFixtureModule} from './fenced-module.js';
const wrapped=wrapFixtureModule('domain/auth.js',actual);
export const handleAuth=wrapped.handleAuth;
export const projectSession=wrapped.projectSession;
export const requireSession=wrapped.requireSession;
export const startOtp=wrapped.startOtp;
export const verifyOtp=wrapped.verifyOtp;
