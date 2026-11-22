import {requireThat} from './errors.js';
function cell(value){
  let s=String(value??'');
  // Prefix cells that a spreadsheet could execute, including leading controls/spaces.
  if(/^[\s\u0000-\u001f]*[=+@-]/u.test(s)||/^[\t\r\n]/.test(s))s="'"+s;
  return '"'+s.replaceAll('"','""')+'"';
}
export function ledgerCsv(records){
  requireThat(Array.isArray(records),'records_required');
  const rows=[['at','FT Id','from','MoMo number','RWF']];
  for(const r of records){
    requireThat(typeof r.atRaw==='string'&&typeof r.ftId==='string'&&typeof r.payerNameRaw==='string'&&
      typeof r.memberPhone==='string'&&Number.isSafeInteger(r.amountRwf),'invalid_ledger_row',503);
    rows.push([r.atRaw,r.ftId,r.payerNameRaw,r.memberPhone,r.amountRwf]);
  }
  return rows.map(r=>r.map(cell).join(',')).join('\r\n')+'\r\n';
}
