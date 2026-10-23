import * as actual from '../../domain/privacy_email_auth.js';
import {wrapFixtureModule} from './fenced-module.js';
const wrapped=wrapFixtureModule('domain/privacy_email_auth.js',actual);
export const handlePrivacyEmailAuth=wrapped.handlePrivacyEmailAuth;
