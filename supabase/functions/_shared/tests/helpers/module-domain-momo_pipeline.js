import * as actual from '../../domain/momo_pipeline.js';
import {wrapFixtureModule} from './fenced-module.js';
const wrapped=wrapFixtureModule('domain/momo_pipeline.js',actual);
export const MOMO_PARSER_VERSION=wrapped.MOMO_PARSER_VERSION;
export const MOMO_SCHEMA_VERSION=wrapped.MOMO_SCHEMA_VERSION;
export const processMomoJob=wrapped.processMomoJob;
export const validateMomoExtraction=wrapped.validateMomoExtraction;
