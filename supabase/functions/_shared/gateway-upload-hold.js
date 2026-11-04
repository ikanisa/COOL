import {ApiError} from './domain/core.js';

// This hold is an owner-selected release boundary, not a parser pause or a
// credential flag. Existing queued captures retain their original identity.
export function isGatewayIngest(method,path){
 return method==='POST'&&path==='/v1/momo/gateway/ingest';
}
export function hasGatewayBinding(body){
 return body?.gateway_binding_id!=null||body?.gateway_binding_version!=null;
}
export function gatewayUploadHeld(){
 return new ApiError(503,'gateway_upload_held','Gateway uploads are paused. Keep this capture on the phone.');
}
