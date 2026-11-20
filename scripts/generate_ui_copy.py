#!/usr/bin/env python3
"""Generate Android UI resources and a statically referenced resource-ID map.
No network, machine translation, runtime getIdentifier, or provider-data rewriting.
"""
import argparse,html,json,pathlib,re,sys
ROOT=pathlib.Path(__file__).resolve().parents[1]
def format_signature(text):
    """Only positional string/integer substitutions; fail on malformed or unindexed '%' tokens."""
    if not isinstance(text,str) or not text or any(ord(c)<32 and c!='\n' for c in text):
        raise ValueError('Empty, non-text or control-character copy')
    tokens=[]; cursor=0; types={}
    while cursor<len(text):
        if text[cursor]!='%':cursor+=1;continue
        if text.startswith('%%',cursor):tokens.append('%%');cursor+=2;continue
        match=re.match(r'%([1-9][0-9]*)\$([sd])',text[cursor:])
        if match is None:raise ValueError('Malformed or unindexed format token')
        index,kind=match.groups()
        if int(index)>16:raise ValueError('Too many format arguments')
        if index in types and types[index]!=kind:raise ValueError('Inconsistent type for one argument')
        types[index]=kind;tokens.append(match[0]);cursor+=len(match[0])
    if types and set(map(int,types))!=set(range(1,max(map(int,types))+1)):
        raise ValueError('Format argument indices must be contiguous')
    return sorted(tokens)
def validate_catalog(entries):
    keys=set();english=set()
    if not isinstance(entries,list) or not entries:raise ValueError('Empty catalog')
    for entry in entries:
        if not isinstance(entry,dict) or not all(k in entry for k in ('key','en','rw')):
            raise ValueError('Missing catalog fields')
        key=entry['key']
        if not isinstance(key,str) or not re.fullmatch(r'ui_[a-z0-9_]+',key):raise ValueError('Invalid resource key')
        signatures=[format_signature(entry[locale]) for locale in ('en','rw')]
        if key in keys or entry['en'] in english:raise ValueError('Duplicate UI key or source phrase')
        if signatures[0]!=signatures[1]:raise ValueError('Placeholder mismatch: '+key)
        keys.add(key);english.add(entry['en'])
def generated():
    source=json.loads((ROOT/'contracts/ui-copy.json').read_text())
    entries=source['entries'];validate_catalog(entries)
    native=ROOT/'native/burimunsi/app/src/main'
    ids='package rw.ikanisa.burimunsi.ui\n\nimport app.cool.mobile.R\n\n// Generated from contracts/ui-copy.json. Do not hand-edit.\ninternal val UiStringIds:Map<String,Int> = mapOf(\n'
    ids+=''.join('    '+json.dumps(e['en'],ensure_ascii=False).replace('$','\\$')+' to R.string.'+e['key']+',\n' for e in entries)+')\n'
    result={native/'kotlin/rw/ikanisa/burimunsi/ui/UiStringIds.kt':ids}
    def escape(text):return html.escape(text,quote=False).replace('\\','\\\\').replace("'","\\'").replace('"','\\"').replace('\n','\\n')
    for language,directory in [('en','values'),('rw','values-rw')]:
        result[native/f'res/{directory}/ui_strings.xml']='<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'+''.join(f'    <string name="{e["key"]}">{escape(e[language])}</string>\n' for e in entries)+'</resources>\n'
    return result
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');a=p.parse_args();mismatches=[]
    for path,text in generated().items():
        if a.check:
            if not path.exists() or path.read_text()!=text:mismatches.append(str(path.relative_to(ROOT)))
        else:path.parent.mkdir(parents=True,exist_ok=True);path.write_text(text)
    if mismatches:print('Outdated generated UI resources: '+', '.join(mismatches));sys.exit(1)
    print('UI catalog and generated resources verified.' if a.check else 'UI resources generated.')
