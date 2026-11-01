import {createSmsGatewayHandler} from '../../../deploy/collect-sms/src/edge.ts';

const handler=createSmsGatewayHandler(Deno.env.toObject());
Deno.serve(handler);
