// Extend only the newly generated managed Storage lifecycle candidate; retain
// its exact predecessor checks and classify the new proof as blocked history.
export function includeManagedRetirement(sql){
 const old="'SELECT jsonb_set(base, ''{copy_classes}'', (base->''copy_classes'') || %L::jsonb) FROM (%s) prior(base)'";
 const descriptor='{"name":"private:collect_managed_executor_retirements","relation":"private.collect_managed_executor_retirements","scope":"shared_fence","purpose":"Immutable managed executor retirement and unquantified external obligation; no provider settlement or subject-empty assertion","blocked":true}';
 const next="'SELECT jsonb_set(jsonb_set(base, ''{copy_classes}'', (base->''copy_classes'') || %L::jsonb), ''{private_classes}'', (base->''private_classes'') || ''"+descriptor+"''::jsonb) FROM (%s) prior(base)'";
 if(sql.split(old).length!==2)throw Error('managed_catalog_anchor_changed');
 return sql.replace(old,next);
}
