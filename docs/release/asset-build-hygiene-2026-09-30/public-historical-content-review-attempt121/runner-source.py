import hashlib,json,subprocess,os,difflib
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
BASE=ROOT/'docs/release/asset-build-hygiene-2026-09-30/public-historical-content-review-attempt113'
P=ROOT/'docs/release/asset-build-hygiene-2026-09-30/public-historical-content-review-attempt121'
SOURCE=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-attempt113-historical-public-content')
BUILD=SOURCE/'.cache/historical-public-build-attempt121'
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
prior=json.loads((BASE/'historical-source.json').read_text());assert all(sha(SOURCE/n)==h for n,h in prior['source_sha256'].items())
P.mkdir(exist_ok=False);(P/'runner-source.py').write_bytes(Path(__file__).read_bytes())
original=(SOURCE/'scripts/public_app_media.rb').read_text()
line="      raise 'App screenshots need recapturing: runtime changed' unless manifest.fetch('runtime_sha256') == runtime_fingerprint"
assert original.count(line)==1
instrumented=original.replace(line,"      # Historical content reconstruction only: dated stored captures retained; current-runtime freshness is not asserted.")
(P/'historical_content_only_media.rb').write_text(instrumented)
wrapper="require " + json.dumps(str(P/'historical_content_only_media.rb')) + "\n$LOADED_FEATURES << " + json.dumps(str(SOURCE/'scripts/public_app_media.rb')) + "\nload " + json.dumps(str(SOURCE/'scripts/public_static_site_build.rb')) + "\n"
(P/'historical-content-only-wrapper.rb').write_text(wrapper)
env={k:v for k,v in os.environ.items() if k in {'HOME','USER','LOGNAME','PATH','TMPDIR','LANG','LC_ALL','LC_CTYPE'}};env['PUBLIC_BUILD_DIR']=str(BUILD)
with (P/'build.stdout').open('wb') as out,(P/'build.stderr').open('wb') as err:code=subprocess.run(['ruby',str(P/'historical-content-only-wrapper.rb')],cwd=SOURCE,env=env,stdout=out,stderr=err).returncode
assert all(sha(SOURCE/n)==h for n,h in prior['source_sha256'].items())
record={'status':'pass' if code==0 else 'fail','build_exit_code':code,'historical_source_git_commit':prior['git_commit'],'historical_source_manifest_sha256':sha(BASE/'historical-source.json'),'historical_source_unchanged':True,'instrumented_media_sha256':sha(P/'historical_content_only_media.rb'),'wrapper_sha256':sha(P/'historical-content-only-wrapper.rb'),'removed_guard_exactly':'Historical runtime screenshot freshness guard only; native image provenance/hash/dimensions and all original builder content retained.','scope':'Explicit historical content reconstruction. Instrumented helper is separate QA evidence; dated screenshots are not asserted current and historical styling/design is not restored as active authority.'}
(P/'execution.json').write_text(json.dumps(record,indent=2)+'\n')
print('HISTORICAL CONTENT ONLY BUILD',code,flush=True)
if code:raise SystemExit(code)
normalizer=r'''require "json"
require "cgi"
require "digest"
build, baseline = ARGV
hashes = JSON.parse(File.read(baseline)).fetch("hashes")
rows=hashes.to_h do |route, expected|
  html=File.read(File.join(build, route.delete_prefix("/"), "index.html")).gsub(/<script\b.*?<\/script>/mi," ").gsub(/<style\b.*?<\/style>/mi," ")
  if html.include?('class="mobile-menu-actions"')
    html=html.sub(%r{<div class="header-actions">\s*<a[^>]*>Get the App</a>\s*</div>}, "")
  end
  text=CGI.unescapeHTML(html.gsub(/<[^>]+>/,"\n")).lines.map{|line|line.gsub(/\s+/," ").strip}.reject(&:empty?).join("\n").gsub(/© \d{4}/,"© YEAR")
  [route,{"text"=>text,"sha256"=>Digest::SHA256.hexdigest(text),"expected"=>expected}]
end
puts JSON.generate(rows)
'''
(P/'visible-text-normalizer.rb').write_text(normalizer)
for label, build in [('historical',BUILD),('current',ROOT/'.cache/public-website-build-attempt109')]:
 raw=subprocess.check_output(['ruby',str(P/'visible-text-normalizer.rb'),str(build),str(ROOT/'docs/release/public-website-content-baseline.json')],env=env)
 (P/(label+'-visible-text.json')).write_bytes(raw)
old=json.loads((P/'historical-visible-text.json').read_text());new=json.loads((P/'current-visible-text.json').read_text());rows=[]
(P/'route-diffs').mkdir()
for route, row in old.items():
 n=route.strip('/').replace('/','-') or 'home';changes=list(difflib.unified_diff(row['text'].splitlines(),new[route]['text'].splitlines(),fromfile='historical'+route,tofile='current'+route,lineterm=''))
 (P/'route-diffs'/(n+'.diff')).write_text('\n'.join(changes)+'\n')
 rows.append({'route':route,'historical_matches_baseline':row['sha256']==row['expected'],'historical_sha256':row['sha256'],'current_sha256':new[route]['sha256'],'current_matches_historical':row['sha256']==new[route]['sha256'],'removed_lines':[x[1:] for x in changes if x.startswith('-') and not x.startswith('---')],'added_lines':[x[1:] for x in changes if x.startswith('+') and not x.startswith('+++')],'diff_sha256':sha(P/'route-diffs'/(n+'.diff'))})
report={'status':'pass' if all(x['historical_matches_baseline'] for x in rows) else 'fail','routes':rows,'historical_html_files':len(list(BUILD.rglob('*.html'))),'current_html_files':len(list((ROOT/'.cache/public-website-build-attempt109').rglob('*.html'))),'baseline_sha256':sha(ROOT/'docs/release/public-website-content-baseline.json'),'historical_visible_text_sha256':sha(P/'historical-visible-text.json'),'current_visible_text_sha256':sha(P/'current-visible-text.json'),'scope':'Exact normalized visible-text comparison with historical baseline, preserving current route differences and all old bytes. No current baseline approval or product/visual acceptance.'}
(P/'content-comparison.json').write_text(json.dumps(report,indent=2)+'\n')
print('HISTORICAL BASELINE MATCHES',sum(x['historical_matches_baseline'] for x in rows),'/',len(rows),flush=True)
