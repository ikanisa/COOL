import {PublicError,objectValue} from './production_contract.ts';
export type IntegrityPolicy={packageName:string;minimumVersion:number;certificates:ReadonlySet<string>;nowMs:number};
/** App/device/request trust; never proof of a settled financial transaction. */
export function validateIntegrityVerdict(value: unknown, requestHash: string, policy: IntegrityPolicy) {
  if (!Number.isSafeInteger(policy.minimumVersion) || policy.minimumVersion<1 || !policy.certificates.size) throw new PublicError('integrity_policy_unconfigured',503);
  const d=objectValue(value),r=objectValue(d.requestDetails),a=objectValue(d.appIntegrity),c=objectValue(d.accountDetails),v=objectValue(d.deviceIntegrity);
  const timestamp=Number(r.timestampMillis);const age=policy.nowMs-timestamp;
  const version=/^\d{1,15}$/.test(String(a.versionCode ?? '')) ? Number(a.versionCode) : NaN;
  const certs=Array.isArray(a.certificateSha256Digest)?a.certificateSha256Digest:[];
  const labels=Array.isArray(v.deviceRecognitionVerdict)?v.deviceRecognitionVerdict.filter((x):x is string=>typeof x==='string'):[];
  if (r.requestPackageName!==policy.packageName || a.packageName!==policy.packageName || r.requestHash!==requestHash ||
      a.appRecognitionVerdict!=='PLAY_RECOGNIZED' || c.appLicensingVerdict!=='LICENSED' || !Number.isSafeInteger(version) || version<policy.minimumVersion ||
      !Number.isSafeInteger(timestamp) || timestamp<=0 || !Number.isFinite(age) || age < -30000 || age>300000 || !certs.length ||
      !certs.every(x=>typeof x==='string' && policy.certificates.has(x)) || !labels.some(x=>x==='MEETS_DEVICE_INTEGRITY'||x==='MEETS_STRONG_INTEGRITY')) throw new PublicError('integrity_policy_rejected',403);
  return {packageName:policy.packageName,appVerdict:'PLAY_RECOGNIZED',deviceVerdicts:labels,timestampMillis:timestamp};
}
