import {requireThat} from './errors.js';
/** PostgreSQL integer/numeric projections must be exact, not coercible.
 * Number(null), Number('') and Number(false) are all zero; none is a balance. */
export function pgInteger(value,{minimum=Number.MIN_SAFE_INTEGER,maximum=Number.MAX_SAFE_INTEGER,code='invalid_database_integer'}={}) {
  requireThat(typeof value==='number'||typeof value==='string'&&/^-?(0|[1-9]\d*)$/.test(value),code,503);
  const n=Number(value);
  requireThat(Number.isSafeInteger(n)&&n>=minimum&&n<=maximum,code,503);
  return n;
}
