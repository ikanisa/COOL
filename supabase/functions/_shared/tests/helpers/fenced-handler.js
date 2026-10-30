import {createHandler as actualHandler,createScheduledHandler as actualScheduled,logicalRequest,runtimeFailureEvent,requestTransportProfile} from '../../serve.js';
import {openApplicationWork} from '../../application-fence.js';
import {syntheticFenceBackend,SYNTHETIC_FENCE_SOURCE,ownFixtureWork} from './fenced-unit.js';
export {logicalRequest,runtimeFailureEvent,requestTransportProfile};
const source=reader=>()=>({...reader(),BUILD_SOURCE_ID:SYNTHETIC_FENCE_SOURCE});
// These pure runtime tests originally used no SQL sockets. Inject genuine
// synthetic admission I/O while executing the actual production handler gate.
const fakeOpen=async options=>ownFixtureWork(await openApplicationWork({...options,backend:syntheticFenceBackend()}));
export const createHandler=(name,reader=()=>Deno.env.toObject())=>actualHandler(name,source(reader),{openWork:fakeOpen});
export const createScheduledHandler=(reader=()=>Deno.env.toObject(),cleanup,process,options={})=>actualScheduled(source(reader),cleanup,process,{openWork:fakeOpen,cleanupDiagnostics:async()=>({status:'complete',removed:0,limit:1000}),...options});
