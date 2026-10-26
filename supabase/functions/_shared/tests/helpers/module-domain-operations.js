import * as actual from '../../domain/operations.js';
import {wrapFixtureModule} from './fenced-module.js';
const wrapped=wrapFixtureModule('domain/operations.js',actual);
export const dispatchOperation=wrapped.dispatchOperation;
export const operationInventory=wrapped.operationInventory;
