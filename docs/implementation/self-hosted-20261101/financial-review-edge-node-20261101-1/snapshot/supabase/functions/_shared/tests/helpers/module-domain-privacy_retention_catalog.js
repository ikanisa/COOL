import * as actual from '../../domain/privacy_retention_catalog.js';
import {wrapFixtureModule} from './fenced-module.js';
const wrapped=wrapFixtureModule('domain/privacy_retention_catalog.js',actual);
export const retentionApprovalScope=wrapped.retentionApprovalScope;
export const retentionSchema=wrapped.retentionSchema;
export const retentionSnapshot=wrapped.retentionSnapshot;
export const snapshotCompareGuards=wrapped.snapshotCompareGuards;
