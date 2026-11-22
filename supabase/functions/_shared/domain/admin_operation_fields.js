import {text} from './core.js';
import {fail} from './admin_records.js';

export function keys(data, allowed) {
 if(Object.keys(data).some(key=>!allowed.includes(key)))fail(400,'invalid_request','Request has unsupported fields.');
}

export const optionalText=(value,field,max)=>value==null||value===''?null:text(value,field,max);
