import {CAPABILITIES, REQUIRED_CAPABILITY, STAFF_CAPABILITIES} from './wire/operator-capabilities.generated.mjs';

export {CAPABILITIES, REQUIRED_CAPABILITY};

export function roleAllowsCapability(role, capability) {
  if (role === 'staff') return STAFF_CAPABILITIES.includes(capability);
  return role === 'admin' && CAPABILITIES.includes(capability);
}

export function validOperatorCapabilities(role, values) {
  if (!Array.isArray(values) || values.length > CAPABILITIES.length || !values.includes(REQUIRED_CAPABILITY)) return false;
  const distinct = new Set(values);
  return distinct.size === values.length && [...distinct].every(capability => roleAllowsCapability(role, capability));
}
