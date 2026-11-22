import {ApiError} from './core.js';

export const marker={contract_version:2,model:'canonical_evidence_ledger'};
export const contributionBasis='reconciled_evidence_entries';
export const collectedBasis='retained_received_evidence';
export const fail=(status,code,message)=>{throw new ApiError(status,code,message);};
export const unavailable=()=>fail(501,'operation_unavailable','This action is unavailable for the current evidence ledger.');
export const iso=value=>{if(typeof value!=='string'||!/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(value)||!Number.isFinite(Date.parse(value)))fail(503,'invalid_source_data','A record timestamp is unavailable.');return value;};
export const exact=(v,{signed=false}={})=>{if(!Number.isSafeInteger(v)||(!signed&&v<0))fail(503,'invalid_source_data','Workspace measurements are unavailable.');return v;};
export const amountString=v=>{if(typeof v!=='string'||!/^(0|[1-9][0-9]*)$/.test(v))fail(503,'invalid_source_data','Workspace measurements are unavailable.');return v;};
