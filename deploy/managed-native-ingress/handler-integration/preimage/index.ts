import {createHandler} from '../_shared/serve.js';
import {admitNativeIngress} from '../_shared/native-ingress.js';
Deno.serve(createHandler('collect-api',undefined,{admitNativeIngress}));
