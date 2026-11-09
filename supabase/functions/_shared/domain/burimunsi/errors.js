/** Fixed error codes only; never put an SMS, passcode or bearer into errors. */
export class BuriError extends Error {
  constructor(code, status = 400) { super(code); this.name = 'BuriError'; this.code = code; this.status = status; }
}
export function requireThat(condition, code, status = 400) {
  if (!condition) throw new BuriError(code, status);
}
export function requirePort(port, names) {
  requireThat(port && names.every(n => typeof port[n] === 'function'), 'collect_adapter_required', 503);
}
