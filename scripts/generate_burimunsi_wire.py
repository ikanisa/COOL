#!/usr/bin/env python3
"""Compile product-owned JSON Schema documents into JS/Kotlin resources. No runtime downloads."""
from pathlib import Path
import json,hashlib,argparse,sys
ROOT=Path(__file__).resolve().parents[1]
KEYS={'$schema','$id','$defs','$ref','type','properties','required','additionalProperties','items','minItems','maxItems','uniqueItems','minLength','maxLength','pattern','format','minimum','maximum','enum','const','anyOf','x-code'}
def inspect(s):
 for key in s:
  if key not in KEYS:raise ValueError('unsupported schema keyword: '+key)
 for key in ('properties','$defs'):
  for v in s.get(key,{}).values():inspect(v)
 if 'items'in s:inspect(s['items'])
 if 'anyOf'in s:
  assert len(s['anyOf'])==2 and s['anyOf'][1]=={'type':'null'}
  inspect(s['anyOf'][0])
def quote(s):return json.dumps(s,ensure_ascii=True).replace('$','\\$')
def outputs():
 out={}
 for product,cls in [('burimunsi','BuriMunsiSchemas')]:
  path=ROOT/'contracts/burimunsi-api/schema.json';s=json.loads(path.read_text());inspect(s)
  meta=json.loads((path.parent/'profile.json').read_text());h=hashlib.sha256(path.read_bytes()).hexdigest()
  out['supabase/functions/_shared/domain/burimunsi/wire/burimunsi.generated.mjs']='// Generated from contracts/burimunsi-api/schema.json; schema SHA-256 '+h+'\nexport const profile='+json.dumps(meta,separators=(',',':'))+';\nexport const defs='+json.dumps(s['$defs'],separators=(',',':'))+';\n'
  lines=['package rw.ikanisa.wire','', '// Generated from contracts/burimunsi-api/schema.json; schema SHA-256 '+h, 'object '+cls+' {','  const val VERSION = '+quote(meta['contractVersion']), '  val definitions: Map<String, Any?> by lazy { linkedMapOf(']
  for k,v in s['$defs'].items():lines.append('    '+quote(k)+' to StrictJson.parse('+quote(json.dumps(v,separators=(',',':')))+'),')
  lines+=['  ) }','  val routes = listOf('+','.join('listOf('+','.join(quote(x)for x in row)+')'for row in meta['routes'])+')' if meta['routes'] else '  val routes: List<List<String>> = emptyList()', '  val contract by lazy { WireContract('+quote(product)+', VERSION, definitions, routes) }', '}','']
  out['native/burimunsi/app/src/main/kotlin/rw/ikanisa/wire/BuriMunsiSchemas.kt']='\n'.join(lines)
 return out
if __name__=='__main__':
 check=argparse.ArgumentParser();check.add_argument('--check',action='store_true');args=check.parse_args();bad=[]
 for name,text in outputs().items():
  p=ROOT/name
  if args.check:
   if not p.exists()or p.read_text()!=text:bad.append(name)
  else:p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)
 if bad:print('GENERATED_DRIFT: '+', '.join(bad));sys.exit(1)
 print('PASS generated schemas are synchronized' if args.check else 'Generated separate JS/Kotlin schemas')
