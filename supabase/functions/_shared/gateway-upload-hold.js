import {ApiError} from './domain/core.js';

// Independent, explicit admission for the approved Buri receiving installation.
// Processing flags, a legacy gateway credential or a member claim cannot opt in.
export function nativeGatewayUploadsEnabled(env){
 return env?.BURIMUNSI_NATIVE_ENABLED==='true'&&env.BURIMUNSI_NATIVE_UPLOADS_ENABLED==='true';
}
export function isGatewayIngest(method,path){
 return method==='POST'&&path==='/v1/momo/gateway/ingest';
}
export function hasGatewayBinding(body){
 return body?.gateway_binding_id!=null||body?.gateway_binding_version!=null;
}
export function gatewayUploadHeld(){
 return new ApiError(503,'gateway_upload_held','Gateway uploads are paused. Keep this capture on the phone.');
}
