import {ApiError} from '../core.js';
import {PinHasher} from './pin.js';

/** Protected server settings only. Never use a native build field, login PIN,
 * shared DATA/BFF key, or a default as the native credential pepper. */
export function nativePinHasher(env) {
  const raw=env.BURIMUNSI_PIN_PEPPER_BASE64,id=env.BURIMUNSI_PIN_PEPPER_ID;
  try {
    if(typeof raw!=='string'||raw.length<44||raw.length>344||raw.length%4!==0||
      !/^[A-Za-z0-9+/]+={0,2}$/.test(raw)||typeof id!=='string'||
      !/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/.test(id))throw Error();
    const bytes=Uint8Array.from(atob(raw),c=>c.charCodeAt(0));
    if(bytes.length<32||bytes.length>256||btoa(String.fromCharCode(...bytes))!==raw||
      raw===env.DATA_ENCRYPTION_KEY||raw===env.SESSION_ENCRYPTION_KEY)throw Error();
    return new PinHasher({pepper:bytes,pepperId:id});
  } catch {
    throw new ApiError(503,'burimunsi_provisioning_unavailable','Protected BuriMunsi credential settings are unavailable.');
  }
}
