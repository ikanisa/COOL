// Node-only, network-denied handler import fixture. Production imports the
// pinned npm driver; this preload is never an application/deployment role.
import {registerHooks} from 'node:module';
registerHooks({resolve(specifier,context,next){if(specifier==='npm:postgres@3.4.7')return{url:'data:text/javascript,export default (...args)=>globalThis.__collectFencePostgresFixture(...args)',shortCircuit:true};if(specifier==='npm:nodemailer@10.1.7')return{url:'data:text/javascript,export function createTransport(){throw Error(%22No SMTP construction allowed in import fixture%22)}',shortCircuit:true};return next(specifier,context);}});
globalThis.__collectFencePostgresFixture=()=>({begin(){throw Error('No SQL execution is allowed in this import fixture');},reserve(){throw Error('No SQL reservation is allowed in this import fixture');}});
