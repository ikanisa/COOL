from pathlib import Path
import datetime,hashlib,json,os,subprocess
root=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
packet=root/'docs/release/asset-build-hygiene-2026-09-30/public-current-inter-content-20261001-attempt2'
output=root/'.cache/public-current-inter-static-20261001-attempt2'
assert not packet.exists() and not output.exists()
packet.mkdir()
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
contract_path=root/'docs/release/public-website-current-content-contract.json'
contract_before=contract_path.read_bytes()
contract=json.loads(contract_before)
prior=root/'docs/release/asset-build-hygiene-2026-09-30/public-content-source-rebind-20261001-attempt1'
assert contract_before==(prior/'current-content-contract.before.json').read_bytes()
assert sha(root/'scripts/public_static_site_build.rb')=='d0326289f1c374dcd7456d9517ad263a037de8e8adebe9fb0f013d6e49472ace'
assert (root/'scripts/public_static_site_build.rb').read_bytes()==(prior/'builder-current.rb').read_bytes()
assert contract['legal_release_approved'] is False and contract['publication_approved'] is False
sources=list(contract['reviewed_source_sha256'])+[
 'scripts/public_website_quality_gate.sh','scripts/qa/public_content_contract.rb','scripts/qa/public_static_routes.rb','scripts/public_app_media.rb','scripts/public_photography.rb',
 'docs/release/public-website-content-baseline.json','docs/release/asset-build-hygiene-2026-09-30/public-historical-content-review-attempt121/content-comparison.json',
 'web/public/revolut.css','web/public/app-screens/manifest.json','web/public/app-screens/capture-provenance.json','assets/brand/APPROVED_PRODUCT_VISUAL_ASSETS.sha256','assets/typefaces/Inter-Variable.ttf','assets/typefaces/OFL-Inter.txt']
before={name:sha(root/name) for name in sorted(set(sources))}
(packet/'source-before.json').write_text(json.dumps(before,indent=2)+'\n')
(packet/'runner-source.py').write_bytes(Path(__file__).read_bytes())
(packet/'current-content-contract.before.json').write_bytes(contract_before)
(packet/'builder-change.diff').write_bytes((prior/'builder.diff').read_bytes())
execution={'kind':'current_inter_public_static_content_acceptance','started_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'scope':'One successful-source current static output, exact15 generated page/alias visible-copy hashes, reviewed builder-only font asset copy-list delta, unchanged historical baseline and no legal/publication/design/hosted approval.','build_output':str(output),'previous_failure_packets':[str(prior.relative_to(root)),'docs/release/asset-build-hygiene-2026-09-30/public-current-inter-content-20261001-attempt1'],'commands':[]}

def run(name,argv,env=None):
 with (packet/(name+'.stdout')).open('w') as out,(packet/(name+'.stderr')).open('w') as err:
  result=subprocess.run(argv,cwd=root,env=env,stdout=out,stderr=err)
 execution['commands'].append({'name':name,'command':argv,'exit_code':result.returncode,'stdout_sha256':sha(packet/(name+'.stdout')),'stderr_sha256':sha(packet/(name+'.stderr'))})
 if result.returncode:
  raise RuntimeError(name+' failed: '+(packet/(name+'.stderr')).read_text())
 return (packet/(name+'.stdout')).read_text()

try:
 env=dict(os.environ,PUBLIC_BUILD_DIR=str(output),PUBLIC_INDEXNOW_KEY='')
 run('static-build',['ruby','scripts/public_static_site_build.rb'],env)
 ruby="""require './scripts/qa/public_content_contract'; require './scripts/qa/public_static_routes'; dir=ARGV.fetch(0); expected=JSON.parse(File.read('docs/release/public-website-current-content-contract.json')).fetch('hashes'); catalog=PublicStaticRoutes.extract(File.read(PublicStaticRoutes::SOURCE)); declared=catalog.select { |r| [:page,:alias].include?(r[:kind].to_sym) }.map { |r| r[:path] }.sort; actual_routes=Dir.glob(File.join(dir,'**','*.html')).map { |p| p.delete_prefix(dir).delete_suffix('index.html') }.reject { |r| ['/app/','/c/','/group-link/'].include?(r) }.sort; rows=actual_routes.map do |route| path=File.join(dir,route.delete_prefix('/'),'index.html'); bytes=File.binread(path); visible=PublicContentContract.visible_text(bytes.force_encoding('UTF-8')); digest=Digest::SHA256.hexdigest(visible); {route:route,html_sha256:Digest::SHA256.file(path).hexdigest,visible_text_sha256:digest,expected_sha256:expected[route],matches_reviewed_copy:digest==expected[route]} end; result={status:actual_routes==expected.keys.sort&&declared==actual_routes&&rows.all? { |r| r[:matches_reviewed_copy] } ? 'pass':'fail',generated_routes:actual_routes,declared_page_alias_routes:declared,rows:rows,legal_release_approved:false,publication_approved:false}; puts JSON.pretty_generate(result); exit(result[:status]=='pass' ? 0:1)"""
 proof=json.loads(run('visible-content',['ruby','-r','json','-r','digest','-e',ruby,str(output)]))
 (packet/'content-routes.json').write_text(json.dumps(proof,indent=2)+'\n')
 assert len(proof['rows'])==15 and proof['status']=='pass'
 assert {name:sha(root/name) for name in before}==before,'Source drift during static generation/content proof'
 changed=[name for name,digest in contract['reviewed_source_sha256'].items() if sha(root/name)!=digest]
 assert changed==['scripts/public_static_site_build.rb'],changed
 old=contract['reviewed_source_sha256']['scripts/public_static_site_build.rb'];new=sha(root/'scripts/public_static_site_build.rb')
 assert old=='37b27f0bb2ef64df53ab08db44bf33434213e6b04ea7374d1a20b0b628a41d46' and contract_before.count(old.encode())==1
 assert contract_path.read_bytes()==contract_before,'Current contract changed before narrow mutation'
 updated=contract_before.replace(old.encode(),new.encode())
 assert json.loads(updated)['hashes']==contract['hashes']
 contract_path.write_bytes(updated)
 (packet/'current-content-contract.after.json').write_bytes(updated)
 binding={'status':'pass','change':'Only reviewed_source_sha256.scripts/public_static_site_build.rb is updated after actual generated15-route visible text and catalog exactly match the reviewed contract. The builder diff removes exactly two deleted unlicensed Aeonik assets from the copy list; no route, renderer or product/legal source edit.','old_builder_sha256':old,'new_builder_sha256':new,'current_contract_before_sha256':hashlib.sha256(contract_before).hexdigest(),'current_contract_after_sha256':sha(contract_path),'changed_contract_fields':['reviewed_source_sha256.scripts/public_static_site_build.rb'],'visible_text_route_count':15,'visible_text_hashes_unchanged':True,'route_catalog_unchanged':True,'other_five_reviewed_source_hashes_unchanged':True,'historical_baseline_sha256':before['docs/release/public-website-content-baseline.json'],'historical_comparison_sha256':before['docs/release/asset-build-hygiene-2026-09-30/public-historical-content-review-attempt121/content-comparison.json'],'historical_bytes_unchanged':True,'legal_release_approved':False,'publication_approved':False,'helper_unchanged_sha256':before['scripts/qa/public_content_contract.rb'],'media_publication_receipt':'docs/release/asset-build-hygiene-2026-09-30/public-current-inter-media-20261001-attempt2/publication/publication.json','static_output':str(output),'generated_route_proof_sha256':sha(packet/'content-routes.json')}
 (packet/'source-binding.json').write_text(json.dumps(binding,indent=2)+'\n')
 quality=json.loads(run('static-quality',['bash','scripts/public_website_quality_gate.sh','--json'],env))
 (packet/'static-quality.json').write_text(json.dumps(quality,indent=2)+'\n')
 assert quality['status']=='pass' and quality['summary']=={'total':55,'passed':55,'failed':0},quality['summary']
 after={name:sha(root/name) for name in before}
 assert after==before,'Source drift during acceptance'
 assert contract_path.read_bytes()==updated
 (packet/'source-after.json').write_text(json.dumps(after,indent=2)+'\n')
 output_map={str(p.relative_to(output)):sha(p) for p in sorted(output.rglob('*')) if p.is_file()}
 (packet/'static-output-files.json').write_text(json.dumps(output_map,indent=2)+'\n')
 assert not any('Aeonik' in p for p in output_map)
 execution.update(status='pass',generated_content_routes=15,content_hashes_unchanged=True,static_checks=quality['summary'],sources_unchanged=True,current_contract_narrow_change=True,output_file_count=len(output_map),output_manifest_sha256=sha(packet/'static-output-files.json'),legal_release_approved=False,publication_approved=False)
except Exception as error:
 execution.update(status='fail',error=str(error))
finally:
 execution['finished_at']=datetime.datetime.now(datetime.timezone.utc).isoformat()
 (packet/'execution.json').write_text(json.dumps(execution,indent=2)+'\n')
 print(json.dumps(execution,indent=2))
if execution['status']!='pass':raise SystemExit(1)
