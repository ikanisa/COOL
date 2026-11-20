import {NativeAuthService} from './auth-service.js';
import {PinHasher} from './pin.js';
import {RecordsService} from './records-service.js';
import {ScopedCursor} from './cursor.js';
import {ContributionService} from './contribution-service.js';
import {MemberService} from './member-service.js';
import {GatewayRegistry} from './gateway-registry.js';
import {createNativeHandler} from './http.js';
import {requireThat,requirePort} from './errors.js';

/** Per-admitted-request composition, not a global SQL/session bypass.
 * Production supplies adapters over the current Collect transaction/fence context.
 * There are deliberately no no-op, memory, auto-approve or demo fallbacks.
 * Operational activation is explicit and defaults OFF.
 */
export function composeNativeRequest({admission,config,ports,secrets,networkBucket,clock=()=>Date.now()}) {
  requireThat(admission?.verified===true&&admission.groupId===config?.groupId,'request_not_admitted',503);
  requireThat(config?.enabled===true&&config.groupId&&config.origin,'native_service_disabled',503);
  requireThat(secrets?.pinPepper instanceof Uint8Array&&secrets.cursorKey instanceof Uint8Array,'authentication_unconfigured',503);
  requirePort(ports?.auth,['consumeAttempts','findAccount','findDeviceGrant','createSessionIfCurrent','loadSession','changePinIfCurrent','mutateStaff','findStaff','retainedStaffCommand','revokeSession']);
  requirePort(ports?.records,['withReadSnapshot']);
  requirePort(ports?.canonical,['inCanonicalTransaction']);
  requirePort(ports?.gateway,['withAuthorityTransaction','withReadSnapshot']);
  const groupId=config.groupId;
  const auth=new NativeAuthService({store:ports.auth,hasher:new PinHasher({pepper:secrets.pinPepper,pepperId:secrets.pinPepperId}),groupId,clock,sessionTtlMs:config.sessionTtlMs??1800000,
    preserveStaffPinOnPhoneChange:config.preserveStaffPinOnPhoneChange===true,defaultStaffPin:secrets.defaultStaffPin});
  const contributions=composeNativeContributions({config,ports,clock});
  const members=new MemberService({store:ports.canonical,groupId,clock});
  const gateway=new GatewayRegistry({store:ports.gateway,groupId,clock});
  requireThat(config.smartOnboardingAdvancedEnabled===undefined||typeof config.smartOnboardingAdvancedEnabled==='boolean','invalid_worker_config',503);
  const smartOnboardingImport=config.smartOnboardingAdvancedEnabled===true?ports.smartOnboardingImport:null;
  if(config.smartOnboardingAdvancedEnabled===true)requirePort(smartOnboardingImport,['preview']);
  else requireThat(ports.smartOnboardingImport===undefined,'smart_import_config_conflict',503);
  const cursor=new ScopedCursor(secrets.cursorKey);
  const records=new RecordsService({store:ports.records,groupId,cursor,clock,smartOnboardingImport});
  return createNativeHandler({auth,records,contributions,members,gateway,observations:ports.observations,cursor,
    origin:config.origin,networkBucket,groupId,strictContract:true});
}

/** Shared request/worker selection. Enabled preparation can never silently fall
 * back to posting without preparation because a port was omitted. Server-only.
 */
export function composeNativeContributions({config,ports,clock=()=>Date.now()}) {
  requireThat(config?.enabled===true&&config.groupId,'native_service_disabled',503);
  requireThat(config.postingPreparationEnabled===undefined||typeof config.postingPreparationEnabled==='boolean','invalid_worker_config',503);
  const preparation=config.postingPreparationEnabled===true?ports?.preparation:null;
  if(config.postingPreparationEnabled===true)requirePort(preparation,['prepare']);
  return new ContributionService({store:ports?.canonical,groupId:config.groupId,clock,preparation});
}
