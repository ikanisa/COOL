import * as actual from '../../domain/groups.js';
import {wrapFixtureModule} from './fenced-module.js';
const wrapped=wrapFixtureModule('domain/groups.js',actual);
export const groupRpc=wrapped.groupRpc;
export const publicGroups=wrapped.publicGroups;
