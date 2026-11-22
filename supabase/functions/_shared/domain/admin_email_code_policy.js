import {ApiError} from './core.js';

export const ADMIN_EMAIL_CODE_MAX_SECONDS=1800;
export const ADMIN_EMAIL_CODE_MIN_SECONDS=60;

// Pending code lifetime only. Consumed-email proof freshness stays separate.
export function adminEmailCodeTtlSeconds(env){
 const raw=env.COLLECT_ADMIN_EMAIL_OTP_TTL_SECONDS===undefined?'1800':env.COLLECT_ADMIN_EMAIL_OTP_TTL_SECONDS;
 if(typeof raw!=='string'||! /^[1-9][0-9]{1,3}$/.test(raw)||Number(raw)<ADMIN_EMAIL_CODE_MIN_SECONDS||Number(raw)>ADMIN_EMAIL_CODE_MAX_SECONDS)
  throw new ApiError(503,'admin_email_otp_unconfigured','Admin email code lifetime is not configured.');
 return Number(raw);
}
