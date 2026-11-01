const names=new Set(['collect-api','admin-api','collect-jobs','collect-email-jobs','collect-sms','send-sms-hook']);
const reserved=new Set(['POSTGRES_PASSWORD','SUPABASE_DB_URL','JWT_SECRET','JWT_KEYS','JWT_JWKS','SUPABASE_JWKS','COLLECT_SMS_EDGE_PASSWORD','COLLECT_EDGE_PASSWORD']);
const gatewayOnly=new Set(['COLLECT_SMS_DATABASE_URL','ROOT_ADMIN_TOKEN','OTP_HMAC_KEY','CALLBACK_ENCRYPTION_KEY','FCM_CLIENT_EMAIL','FCM_PRIVATE_KEY','COLLECT_SMS_MAINTENANCE_TOKEN','OPENSMS_FCM_PROJECT_ID','OPENSMS_FCM_CLIENT_EMAIL','OPENSMS_FCM_PRIVATE_KEY']);
const gatewayNames=new Set(['COLLECT_SMS_ENABLED','COLLECT_SMS_APPROVAL_SHA256','BUILD_SOURCE_ID','COLLECT_DEPLOYMENT_PROFILE','COLLECT_DEPLOYMENT_PROFILE_SHA256','COLLECT_SMS_DATABASE_URL','COLLECT_DB_CA_PEM','ROOT_ADMIN_TOKEN','OTP_HMAC_KEY','DISPATCH_PAUSED','FCM_ENABLED','RETENTION_AUTO_PURGE','COLLECT_SMS_MAINTENANCE_TOKEN','REQUIRE_ACTUAL_PARTS','OTP_REQUIRE_READY_GATEWAY','OTP_SEGMENT_INTERVAL_MS','CALLBACK_ENCRYPTION_KEY','CALLBACK_ALLOWED_HOSTS','MESSAGE_RETENTION_DAYS','OPENSMS_FCM_PROJECT_ID','OPENSMS_FCM_CLIENT_EMAIL','OPENSMS_FCM_PRIVATE_KEY']);
const hookNames=new Set(['COLLECT_DATABASE_URL','COLLECT_DB_CA_PEM','BUILD_SOURCE_ID','COLLECT_DEPLOYMENT_PROFILE','COLLECT_DEPLOYMENT_PROFILE_SHA256','APP_ENVIRONMENT','SUPABASE_URL','AUTH_PROJECT_ID','AUTH_SMS_ENABLED','AUTH_WHATSAPP_ENABLED','AUTH_PHONE_DELIVERY_MODE','AUTH_SEND_SMS_SECRET','OPENSMS_BASE_URL','OPENSMS_APPLICATION_ID','OPENSMS_APPLICATION_TOKEN','OPENSMS_SENDER_LABEL','OPENSMS_DISPATCH_TTL_SECONDS','OPENSMS_RECEIPT_APPLICATION_ID']);
const hookOnly=new Set(['AUTH_SEND_SMS_SECRET','COLLECT_SMS_HOOK_SECRET','SUPABASE_SMS_HOOK_SECRET','SUPABASE_SMS_HOOK_SECRETS','OPENSMS_BASE_URL','OPENSMS_APPLICATION_ID','OPENSMS_APPLICATION_TOKEN']);
export function workerEnvironment(name,source){
 if(!names.has(name))throw Error('Unknown function');
 const result={};
 for(const [key,value]of Object.entries(source)){
  if(reserved.has(key)||key.startsWith('SMTP_')||key.startsWith('GOTRUE_')||['GOOGLE_SECRET','GOOGLE_CLIENT_ID'].includes(key))continue;
  if(name==='collect-sms'&&!gatewayNames.has(key))continue;
  if(name==='send-sms-hook'&&!hookNames.has(key))continue;
  if(gatewayOnly.has(key)&&name!=='collect-sms')continue;
  if(hookOnly.has(key)&&name!=='send-sms-hook')continue;
  if(key==='OPENSMS_RECEIPT_APPLICATION_TOKEN'&&name!=='admin-api')continue;
  if(key==='COLLECT_JOB_TOKEN'&&name!=='collect-jobs')continue;
  if(key==='COLLECT_EMAIL_JOB_TOKEN'&&name!=='collect-email-jobs')continue;
  result[key]=value;
 }
 if(name==='collect-sms')for(const suffix of ['PROJECT_ID','CLIENT_EMAIL','PRIVATE_KEY']){
  const key='OPENSMS_FCM_'+suffix;
  if(Object.hasOwn(result,key)){result['FCM_'+suffix]=result[key];delete result[key];}
 }
 result.SUPABASE_FUNCTION_SLUG=name;return Object.entries(result);
}
