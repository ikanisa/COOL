import {createHandler} from '../_shared/serve.js';
import {admitNativeIngress,verifyNativeIngress,claimNativeIngress} from '../_shared/native-ingress.js';
import {consumeNativeIngressNonce} from '../_shared/native-ingress-nonce.js';
Deno.serve(createHandler('collect-api',undefined,{admitNativeIngress,verifyNativeIngress,claimNativeIngress,consumeNativeIngressNonce}));
