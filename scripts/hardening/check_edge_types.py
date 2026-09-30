#!/usr/bin/env python3
"""Strict local TypeScript checking with declared Deno and remote-SDK boundaries.
SDK declarations here intentionally do not certify the real remote SDK surface.
"""
import pathlib,subprocess,tempfile,argparse
p=argparse.ArgumentParser();p.add_argument('--output');a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[2]
files=list((root/'supabase/functions').rglob('*.ts'))
with tempfile.TemporaryDirectory(prefix='collect-type-') as t:
 d=pathlib.Path(t)/'host.d.ts'
 d.write_text('''declare namespace Deno {const env:{get(name:string):string|undefined};function serve(handler:(request:Request)=>Response|Promise<Response>):void;function test(name:string,fn:()=>void|Promise<void>):void;}
declare module "https://esm.sh/@supabase/supabase-js@2.112.0" {export function createClient(...args:unknown[]):any;}
declare module "https://deno.land/std@0.224.0/assert/mod.ts" {export function assert(value:unknown,message?:string):asserts value;export function assertEquals(actual:unknown,expected:unknown,message?:string):void;export function assertMatch(actual:string,expected:RegExp,message?:string):void;export function assertThrows(fn:()=>unknown,errorClass?:new(...args:any[])=>Error,msgIncludes?:string):unknown;}
''')
 r=subprocess.run(['tsc','--noEmit','--strict','--target','ES2022','--module','ESNext','--moduleResolution','bundler','--allowImportingTsExtensions','--lib','ES2022,DOM',str(d),*[str(x) for x in files]],capture_output=True,text=True)
 text=f'{len(files)} Edge TypeScript files checked with declared host/SDK boundaries; exit={r.returncode}\n'+r.stdout+r.stderr
 print(text)
 if a.output:pathlib.Path(a.output).write_text(text)
 raise SystemExit(r.returncode)
