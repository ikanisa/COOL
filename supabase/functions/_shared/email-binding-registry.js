// Only adapters implemented in this source graph opt into the identity-bound
// dispatch contract. Other existing bindings retain their original behavior.
const builtins=new WeakSet();
export function registerBuiltinEmailBinding(binding){builtins.add(binding);return binding;}
export function isBuiltinEmailBinding(binding){return !!binding&&builtins.has(binding);}
