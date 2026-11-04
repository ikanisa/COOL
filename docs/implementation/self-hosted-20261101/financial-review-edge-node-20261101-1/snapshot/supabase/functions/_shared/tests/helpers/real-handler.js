import {createHandler as actualHandler,createScheduledHandler as actualScheduled,logicalRequest,runtimeFailureEvent,requestTransportProfile} from '../../serve.js';
import {openApplicationWork} from '../../application-fence.js';
import {SYNTHETIC_FENCE_SOURCE,ownFixtureWork} from './fenced-unit.js';
export {logicalRequest,runtimeFailureEvent,requestTransportProfile};
const source=reader=>()=>({...reader(),BUILD_SOURCE_ID:SYNTHETIC_FENCE_SOURCE});
// Actual SQL admission/register/held WORK/close, tracked solely for fixture cleanup.
const realOpen=async options=>ownFixtureWork(await openApplicationWork(options));
export const createHandler=(name,reader=/** @type {() => Record<string, unknown>} */ (()=>Deno.env.toObject()))=>actualHandler(name,source(reader),{openWork:realOpen});
export const createScheduledHandler=(reader=/** @type {() => Record<string, unknown>} */ (()=>Deno.env.toObject()),cleanup,process)=>actualScheduled(source(reader),cleanup,process,{openWork:realOpen});
