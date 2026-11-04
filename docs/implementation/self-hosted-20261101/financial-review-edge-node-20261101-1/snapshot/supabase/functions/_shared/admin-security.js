import {ApiError} from './domain/core.js';
export function validateAdminOrigin(request,env) {
 const allowed=(env.ADMIN_ORIGINS??env.ADMIN_ORIGIN??'').split(',').map(v=>v.trim()).filter(Boolean);
 if(!allowed.length||allowed.some(v=>{try{const u=new URL(v);return u.origin!==v||u.protocol!=='https:';}catch{return true;}}))throw new ApiError(503,'admin_origin_unconfigured','Admin origin is not configured.');
 const origin=request.headers.get('Origin'),mutating=!['GET','HEAD','OPTIONS'].includes(request.method);
 if(new URL(request.url).protocol!=='https:'||request.headers.get('Sec-Fetch-Site')==='cross-site'||origin&&!allowed.includes(origin)||mutating&&(!origin||!allowed.includes(origin)||request.headers.get('X-Collect-Requested-With')!=='collect-admin'||!/^application\/json(?:;|$)/i.test(request.headers.get('Content-Type')??'')))throw new ApiError(403,'origin_rejected','Open the configured Admin website to continue.');
 return origin??(allowed.includes(new URL(request.url).origin)?new URL(request.url).origin:null);
}
