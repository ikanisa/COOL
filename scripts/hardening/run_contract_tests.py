#!/usr/bin/env python3
"""Compile the actual dependency-free TS modules and run Node behavioral tests.
No Deno or live database equivalence is implied. Build output is disposable.
"""
import argparse, pathlib, re, shutil, subprocess, tempfile, os

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--output');args=parser.parse_args()
    root=pathlib.Path(__file__).resolve().parents[2]
    modules=['production_contract','signed_sms_hook','integrity_policy','roster_file_policy','receipt_ingestion','hash']
    for tool in ['tsc','node']:
        if not shutil.which(tool): raise SystemExit(f'Required tool unavailable: {tool}')
    with tempfile.TemporaryDirectory(prefix='collect-contract-') as work:
        work=pathlib.Path(work)
        for name in modules:
            original=(root/f'supabase/functions/_shared/{name}.ts').read_text()
            # Rewrite import suffixes only for tsc emit; no implementation body changes.
            converted=re.sub(r'(from\s+[\'"][^\'"\n]+)\.ts([\'"])',r'\1.js\2',original)
            (work/f'{name}.ts').write_text(converted)
        result=subprocess.run(['tsc','--strict','--target','ES2022','--module','commonjs','--lib','ES2022,DOM','--outDir',str(work/'compiled'),*[str(work/f'{x}.ts') for x in modules]],capture_output=True,text=True)
        output=result.stdout+result.stderr
        if result.returncode:
            print(output);raise SystemExit(result.returncode)
        env=os.environ.copy();env['COLLECT_COMPILED_MODULES']=str(work/'compiled')
        result=subprocess.run(['node','--test',str(root/'scripts/hardening/contracts.test.cjs')],capture_output=True,text=True,env=env)
        output+='TypeScript strict compilation: PASS\n'+result.stdout+result.stderr
        print(output)
        if args.output: pathlib.Path(args.output).write_text(output)
        raise SystemExit(result.returncode)
if __name__=='__main__':main()
