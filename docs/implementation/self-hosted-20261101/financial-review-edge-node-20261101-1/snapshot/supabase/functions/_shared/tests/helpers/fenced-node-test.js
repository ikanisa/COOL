import original from 'node:test';
import {finishFixtureWork} from './fenced-unit.js';
function test(...args){const index=args.findLastIndex(value=>typeof value==='function');if(index>=0){const fn=args[index];args[index]=async(...values)=>{try{return await fn(...values);}finally{await finishFixtureWork();}};}return original(...args);}
for(const name of ['skip','todo','only'])test[name]=original[name].bind(original);
export {test};
export default test;
