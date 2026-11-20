import {InputError,prepareImportRows} from './onboarding.mjs';
import {extractMemberImage} from './ocr.mjs';
/** CSV parser including escaped quoted fields. UTF-8 only. */
export function parseCsv(text) {
 if(typeof text!=='string'||text.length>2_000_000)throw new InputError('CSV file exceeds size limit');
 let row=[],rows=[],field='',quoted=false;
 for(let i=0;i<text.length;i++){
  const c=text[i];
  if(quoted){if(c==='"'&&text[i+1]==='"'){field+='"';i++;}else if(c==='"')quoted=false;else field+=c;}
  else if(c==='"'){if(field!=='')throw new InputError('Invalid CSV quoting');quoted=true;}
  else if(c===','){row.push(field);field='';}
  else if(c==='\n'){row.push(field.replace(/\r$/,''));rows.push(row);row=[];field='';}
  else field+=c;
 }
 if(quoted)throw new InputError('Unterminated CSV quote');
 if(row.length||field){row.push(field);rows.push(row)}
 if(!rows.length)return [];
 const headers=rows.shift().map(x=>x.trim().toLowerCase());
 const nameAt=headers.findIndex(x=>['momo name','momo_name','name','amazina','member name'].includes(x));
 const phoneAt=headers.findIndex(x=>['momo number','momo_number','phone','number','nimero','mobile'].includes(x));
 if(nameAt<0||phoneAt<0)throw new InputError('CSV requires MoMo name and MoMo number columns');
 return prepareImportRows(rows.filter(r=>r.some(v=>v.trim())).map(r=>({momoName:r[nameAt]??'',momoNumber:r[phoneAt]??''})));
}
/** Supported formats: image, CSV directly. PDF / XLSX through trusted host adapters. No arbitrary shell invocation. */
export async function parseDocument({bytes,mimeType,ocrConfig,adapters={}}){
 if(!bytes?.length||bytes.length>10*1024*1024)throw new InputError('File exceeds 10 MB');
 if(['image/png','image/jpeg','image/webp'].includes(mimeType))return extractMemberImage({imageBytes:bytes,mimeType,...ocrConfig});
 if(mimeType==='text/csv'||mimeType==='application/csv')return parseCsv(Buffer.from(bytes).toString('utf8').replace(/^\uFEFF/,''));
 if(mimeType==='application/pdf') {
  if(!adapters.pdfToImages)throw new InputError('PDF converter is not configured on server','ADAPTER_REQUIRED');
  const pages=await adapters.pdfToImages(bytes,{maxPages:10,format:'image/png'});
  if(!Array.isArray(pages)||pages.length<1||pages.length>10)throw new InputError('Invalid PDF page count');
  let all=[];for(const page of pages)all.push(...await extractMemberImage({imageBytes:page,mimeType:'image/png',...ocrConfig}));
  return prepareImportRows(all.map(r=>({name:r.momoName,phone:r.momoNumber})));
 }
 if(mimeType==='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'){
  if(!adapters.xlsxToRows)throw new InputError('XLSX parser is not configured on server','ADAPTER_REQUIRED');
  return prepareImportRows(await adapters.xlsxToRows(bytes,{maxRows:500}));
 }
 throw new InputError('Unsupported file type','UNSUPPORTED_DOCUMENT');
}
