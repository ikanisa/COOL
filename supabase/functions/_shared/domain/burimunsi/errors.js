/** Fixed error codes only; never put an SMS, passcode or bearer into errors. */
export class BuriError extends Error {
  constructor(code, status = 400) { super(code); this.name = 'BuriError'; this.code = code; this.status = status; }
}
/** A request-specific storage uncertainty, never an acknowledgement. */
export class ObservationUploadUnresolved extends BuriError {
  constructor(requestId) {
    if(typeof requestId!=='string'||!/^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/.test(requestId))
      throw new TypeError('Invalid observation request identity');
    super('observation_upload_unresolved',503);
    this.name='ObservationUploadUnresolved';this.requestId=requestId;
  }
}
export function requireThat(condition, code, status = 400) {
  if (!condition) throw new BuriError(code, status);
}
export function requirePort(port, names) {
  requireThat(port && names.every(n => typeof port[n] === 'function'), 'collect_adapter_required', 503);
}
