import * as actual from '../../domain/admin_sms_receipts.js';
import {wrapFixtureModule} from './fenced-module.js';
const wrapped=wrapFixtureModule('domain/admin_sms_receipts.js',actual);
export const adminSmsMetadataRead=wrapped.adminSmsMetadataRead;
