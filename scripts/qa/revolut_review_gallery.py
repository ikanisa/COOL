#!/usr/bin/env python3
"""Build the local, complete Collect design review from retained QA evidence."""
import argparse
import hashlib
import html
import json
import re
import shutil
import subprocess
import yaml
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return json.loads(path.read_text()) if path.exists() else {}


def current_capture(entry):
    """Old product UI is not a selectable design alternative in this gallery."""
    description = ' '.join(str(entry.get(key, '')) for key in
                           ('variant', 'kind', 'caption', 'check')).lower()
    return not any(word in description for word in ('historical', 'before correction'))


def runtime_fingerprint(root=ROOT):
    """Review freshness depends on runtime bytes, separately from QA harnesses."""
    manifest = root / 'pubspec.yaml'
    config = (yaml.safe_load(manifest.read_text()) or {}).get('flutter', {}) if manifest.exists() else {}
    declared = [entry['path'] if isinstance(entry, dict) else entry for entry in config.get('assets', [])]
    declared += config.get('licenses', [])
    declared += [font['asset'] for family in config.get('fonts', []) for font in family['fonts']]
    assets = set()
    for entry in declared:
        path = root / entry
        assets.update(p for p in path.rglob('*') if p.is_file() and not p.name.startswith('.')) if path.is_dir() else assets.add(path)
    if not manifest.exists():
        assets = {p for p in (root / 'assets').rglob('*') if p.is_file() and not p.name.startswith('.')}
    paths = sorted({p for directory in ('lib', 'android/app/src', 'ios/Runner')
                    for p in (root / directory).rglob('*')
                    if p.is_file() and not p.name.startswith('.')
                    and 'GeneratedPluginRegistrant' not in p.name} |
                   assets | {p for p in (root / 'pubspec.yaml', root / 'pubspec.lock') if p.is_file()})
    return hashlib.sha256(''.join(
        str(p.relative_to(root)) + '\0' + hashlib.sha256(p.read_bytes()).hexdigest() + '\n'
        for p in paths).encode()).hexdigest()


def current_native_source():
    """Compare native runs to the checkout, never to another capture's age."""
    result = subprocess.run(
        ['ruby', str(ROOT / 'scripts/qa/mobile_design_gate.rb'), '--fingerprint', '--json'],
        check=True, capture_output=True, text=True)
    return json.loads(result.stdout)['source_sha256']


def native_run_current(run, source_sha256):
    before = read(run / 'source-before.json').get('source_sha256')
    after = read(run / 'source-after.json').get('source_sha256')
    return bool(source_sha256 and before == after == source_sha256)


def reviewed_recapture(path, digest, verified_media):
    """A fresh native capture may reproduce an unchanged screen exactly."""
    return verified_media.get(str(path)) == digest


def component_review(report, output, copy):
    """Keep the owner comparator beside the new, explicitly scoped captures."""
    entries = [dict(report['reference'], kind='Owner reference')] + [
        entry for entry in report['captures'] if current_capture(entry)]
    panels = []
    cards = []
    for entry in entries:
        source = copy(entry['path'])
        if source is None:
            raise FileNotFoundError(entry['path'])
        title = html.escape(entry['title'])
        caption = html.escape(entry['caption'])
        panels.append(f'<article><a href="{source}" target="_blank" rel="noopener">'
                      f'<img src="{source}" alt="{title}" loading="lazy"></a>'
                      f'<h2>{title}</h2><p>{caption}</p>'
                      f'<a href="{source}" target="_blank" rel="noopener">Original pixels</a></article>')
        if entry.get('kind') != 'Owner reference':
            cards.append(dict(surface='Mobile', title=entry['title'], route=entry.get('route', ''),
                              variant=entry['variant'], kind='Group card review', image=source,
                              evidence=entry['path'], check=entry['caption']))
    page = '''<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Collect · group cards</title>
<style>*{box-sizing:border-box}body{margin:0;background:#09090b;color:#f5f5f5;font:16px/1.5 system-ui,sans-serif}
main{max-width:1360px;margin:auto;padding:32px 24px}a{color:inherit}a:focus-visible{outline:3px solid #a7aaff;outline-offset:5px}
h1{font-size:clamp(32px,5vw,52px);letter-spacing:-1px;line-height:1.08;margin:24px 0 16px}header p{max-width:880px;color:#b8b8c2}
.grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:24px;margin-top:32px}article{min-width:0;background:#161618;border:1px solid #303036;border-radius:24px;padding:16px}
img{display:block;width:100%;height:660px;object-fit:contain;object-position:top;border-radius:12px;background:#222225}
h2{font-size:20px;margin:16px 0 8px}article p{color:#b8b8c2;font-size:14px;overflow-wrap:anywhere}.note{font-size:14px}
@media(max-width:1000px){.grid{grid-template-columns:repeat(2,minmax(0,1fr))}img{height:560px}}
@media(max-width:600px){main{padding:24px 16px}.grid{grid-template-columns:1fr}img{height:auto;max-height:700px}}
</style></head><body><main><header><a href="./?surface=Mobile&amp;search=RevPoints">← Complete design gallery</a>
<h1>Group cards, using your reference.</h1><p>Full Rwanda photography, a category caption, and the group’s name and real totals over a dark lower fade. Home and Groups retain their selected page colours and existing actions.</p>
<p class="note">The source image is a component comparator. Captures use synthetic fixture data and identify their platform and text scale. This local review does not certify complete mobile fidelity or production acceptance.</p></header>
<section class="grid" aria-label="Reference and Collect captures">__PANELS__</section></main></body></html>'''
    (output / 'group-cards.html').write_text(page.replace('__PANELS__', ''.join(panels)))
    return cards


def keyboard_review(report_path, output, copy):
    report = read(report_path)
    cards, panels = [], []
    for row in report['results']:
        scenario = row['scenario']
        variant = f"Android · {row['orientation']} · OS font scale {row['font_scale']}"
        status = 'Passed' if not row['failures'] else 'Finding: ' + '; '.join(row['failures'])
        frames = []
        for state in ['focused', 'action']:
            filename = row.get(state + '_capture')
            if not filename:
                continue
            path = report_path.parent / filename
            source = copy(path)
            if source is None:
                raise FileNotFoundError(path)
            title = f"{scenario['name']} · {state}"
            caption = (f"{status}. {variant}. Actual Android keyboard and OS input; "
                       'synthetic account; no action submitted. Geometry and input checks do not certify complete design fidelity.')
            cards.append(dict(surface='Mobile', title=title, route=scenario['route'],
                              variant=variant, kind='Native OS keyboard', image=source,
                              evidence=str(path.relative_to(ROOT)), check=caption))
            frames.append(f'<figure><a href="{source}"><img src="{source}" '
                          f'alt="{html.escape(title)}" loading="lazy"></a>'
                          f'<figcaption>{html.escape(state.capitalize())}</figcaption></figure>')
        anchor = f"{scenario['name']}-{row['orientation']}-{round(row['font_scale'] * 100)}"
        panels.append('<article id="' + html.escape(anchor, quote=True) + '"><h2>' + html.escape(scenario['name']) + '</h2><p>' +
                      html.escape(variant + ' · ' + status) + '</p><div class="frames">' +
                      ''.join(frames) + '</div></article>')
    page = '''<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Collect · native keyboard review</title>
<style>*{box-sizing:border-box}body{margin:0;background:#09090b;color:#f5f5f5;font:16px/1.5 system-ui}
main{max-width:1360px;margin:auto;padding:32px 24px}a{color:inherit}a:focus-visible{outline:3px solid #a7aaff;outline-offset:5px}
h1{font-size:clamp(32px,5vw,52px);line-height:1.1}header p{max-width:940px;color:#b8b8c2}
.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:24px}article{min-width:0;background:#161618;border:1px solid #303036;border-radius:24px;padding:16px}
.frames{display:flex;gap:12px}figure{min-width:0;flex:1;margin:0}img{display:block;width:100%;height:440px;object-fit:contain;object-position:top;background:#222225;border-radius:12px}
h2{font-size:20px}article p,figcaption{color:#b8b8c2;font-size:14px;overflow-wrap:anywhere}
@media(max-width:850px){main{padding:24px 16px}.grid{grid-template-columns:1fr}}
@media(max-width:500px){.frames{display:block}figure+figure{margin-top:20px}img{height:auto;max-height:740px}}
</style></head><body><main><header><a href="./">← Complete design gallery</a><h1>Forms with the real Android keyboard.</h1>
<p>Rwanda and diaspora profile and contribution forms, sign-in, group creation, invitation sign-in and group search. Portrait and landscape, normal and enlarged OS text. Images include the actual system keyboard.</p>
<p>Isolated synthetic QA app. Focus and typing use Android input; scrolling uses Flutter’s scroll controls. No OTP, profile change, group creation or payment was submitted. These checks cover input and layout usability; full reference fidelity, screen-reader and iOS acceptance remain open.</p>
</header><section class="grid" aria-label="Native keyboard checks">__PANELS__</section></main></body></html>'''
    (output / 'native-keyboard.html').write_text(page.replace('__PANELS__', ''.join(panels)))
    return cards


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--evidence', default='.cache/revolut-design-20260905')
    parser.add_argument('--website-report', default='exhaustive-website/route_rendered_qa.json')
    parser.add_argument('--component-report', default='revpoints-group-cards/review.json')
    parser.add_argument('--supplement-report', help='Repository-relative current responsive review JSON')
    parser.add_argument('--native-evidence', help='Additional repository-relative native evidence directory')
    parser.add_argument('--behavior-report', help='Repository-relative named check results, including focused reruns')
    parser.add_argument('--inventory', help='Repository-relative current source inventory')
    parser.add_argument('--keyboard-report', help='Repository-relative actual OS keyboard report')
    parser.add_argument('--matrix-report', help='Current source-bound route/state widget captures')
    parser.set_defaults(**read(ROOT / 'docs/release/mobile-design/current-review-inputs.json'))
    args = parser.parse_args()
    base = ROOT / args.evidence
    output = base / 'review'
    output.mkdir(parents=True, exist_ok=True)
    inventory_path = ROOT / args.inventory if args.inventory else base / 'exhaustive-inventory.json'
    inventory = read(inventory_path)
    cards = []
    retired = []
    runtime = runtime_fingerprint()
    retired_hashes = set(read(ROOT / 'docs/release/mobile-design/retired-design-assets.json')
                         .get('sha256', []))
    # Reuse the website's native build, source and original-image validation.
    # An equal hash alone never reinstates an old capture or another path.
    media_check = subprocess.run(['ruby', '-I', str(ROOT / 'scripts'), '-r', 'public_app_media',
        '-e', 'puts JSON.generate(PublicAppMedia.new(ARGV[0]).screens.values.to_h { |entry| [entry.fetch("source"), entry.fetch("sha256")] })', str(ROOT)],
        check=True, capture_output=True, text=True)
    verified_media = json.loads(media_check.stdout)
    current_recaptures = []

    def copy(path):
        path = Path(path)
        if not path.is_absolute():
            path = ROOT / path
        if not path.is_file():
            return None
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest in retired_hashes:
            if not reviewed_recapture(path, digest, verified_media):
                raise ValueError('Retired product design asset cannot be published: ' + str(path))
            current_recaptures.append(dict(path=str(path.relative_to(ROOT)), sha256=digest,
                reason='Fresh native capture of the current app, visually reviewed for website use; original bytes and installed bundle verified.'))
        name = digest[:16] + path.suffix
        destination = output / 'media' / name
        destination.parent.mkdir(exist_ok=True)
        if not destination.exists():
            shutil.copy2(path, destination)
        return 'media/' + name

    def evidence_path(value):
        path = Path(value)
        return path if path.is_absolute() else (ROOT if value.startswith('.cache/') else base) / path

    component = read(evidence_path(args.component_report))
    if component:
        if component.get('runtime_sha256') != runtime:
            retired.extend(dict(path=e['path'], reason='component runtime changed')
                           for e in component['captures'])
            component['captures'] = []
        cards.extend(component_review(component, output, copy))
    keyboard_current = bool(args.keyboard_report and
                            read((ROOT / args.keyboard_report).parent / 'review-runtime.json')
                            .get('runtime_sha256') == runtime)
    if keyboard_current:
        cards.extend(keyboard_review(ROOT / args.keyboard_report, output, copy))
    elif args.keyboard_report:
        (output / 'native-keyboard.html').write_text(
            '<!doctype html><title>Collect · capture refresh required</title>'
            '<a href="./">Design gallery</a><h1>Native captures need refreshing</h1>'
            '<p>The runtime has changed. Previous screenshots are no longer displayed.</p>')
    supplement = read(ROOT / args.supplement_report) if args.supplement_report else {}
    if supplement:
        panels = []
        for entry in supplement['captures']:
            if not current_capture(entry) or supplement.get('runtime_sha256') != runtime:
                retired.append(dict(path=entry['path'], reason='superseded supplement'))
                continue
            source = copy(entry['path'])
            if source is None:
                raise FileNotFoundError(entry['path'])
            cards.append(dict(surface=entry['surface'], title=entry['title'],
                              route=entry.get('route', ''), variant=entry['variant'],
                              kind=entry['kind'], image=source, evidence=entry['path'],
                              check=entry['caption']))
            if entry.get('featured'):
                panels.append('<article><a href="' + source + '"><img src="' + source +
                              '" alt="' + html.escape(entry['title']) + '"></a><h2>' +
                              html.escape(entry['title']) + '</h2><p>' +
                              html.escape(entry['caption']) + '</p></article>')
        page = '''<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Collect · responsive review</title>
<style>*{box-sizing:border-box}body{margin:0;background:#09090b;color:#f5f5f5;font:16px/1.5 system-ui}
main{max-width:1360px;margin:auto;padding:32px 24px}a{color:inherit}a:focus-visible{outline:3px solid #a7aaff;outline-offset:5px}
h1{font-size:clamp(32px,5vw,52px);line-height:1.1}header p{max-width:900px;color:#b8b8c2}
.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:24px}article{min-width:0;background:#161618;border:1px solid #303036;border-radius:24px;padding:16px}
img{display:block;width:100%;height:460px;object-fit:contain;object-position:top;background:#222225;border-radius:12px}
h2{font-size:20px}article p{color:#b8b8c2;font-size:14px;overflow-wrap:anywhere}
@media(max-width:700px){main{padding:24px 16px}.grid{grid-template-columns:1fr}img{height:auto;max-height:700px}}
</style></head><body><main><header><a href="./">← Complete design gallery</a><h1>__TITLE__</h1>
<p>__DESCRIPTION__</p><p>__SCOPE__</p></header><section class="grid" aria-label="Reviewed captures">__PANELS__</section></main></body></html>'''
        for key, value in {'TITLE': supplement['title'], 'DESCRIPTION': supplement['description'],
                           'SCOPE': supplement['scope']}.items():
            page = page.replace('__' + key + '__', html.escape(value))
        (output / 'responsive.html').write_text(page.replace('__PANELS__', ''.join(panels)))
    if args.matrix_report:
        matrix = read(ROOT / args.matrix_report)
        if matrix.get('status') != 'pass' or matrix.get('runtime_sha256') != runtime:
            raise ValueError('Current route/state matrix has not passed')
        for entry in matrix['captures']:
            path = ROOT / entry['path']
            if not current_capture(entry) or hashlib.sha256(path.read_bytes()).hexdigest() != entry['sha256']:
                raise ValueError('Invalid or obsolete matrix capture: ' + entry['path'])
            cards.append(dict(surface='Mobile', title=entry['title'], route=entry['route'],
                              variant=entry['variant'], kind='Current route / state render',
                              image=copy(path), evidence=entry['path'], check=entry['caption']))
    current_source = current_native_source()
    route_names = {r['name']: r['route'] for r in inventory['mobile_routes']}
    state_names = {r['name']: r['route'] for r in inventory['mobile_states']}
    native_runs = {}
    run_paths = list(base.glob('exhaustive-*'))
    if args.native_evidence:
        run_paths.extend((ROOT / args.native_evidence).glob('exhaustive-*'))
    for run in sorted(run_paths):
        if not run.is_dir() or not (run / 'summary.json').exists():
            continue
        summary = read(run / 'summary.json')
        if summary.get('status') != 'pass':
            continue
        if 'target' not in summary:
            continue
        settings = summary.get('variant', {})
        platform = 'iOS' if 'simulator_before' in summary else 'Android'
        key = (platform, summary['target'], settings.get('theme_mode'),
               settings.get('text_scale'), settings.get('high_contrast'),
               settings.get('reduced_motion'))
        if key not in native_runs or summary.get('generated_at', '') > native_runs[key][1].get('generated_at', ''):
            native_runs[key] = (run, summary)
    for key, (run, summary) in native_runs.items():
        platform = key[0]
        variant = summary.get('variant', {}).get('name', run.name)
        current = native_run_current(run, current_source)
        for path in sorted((run / 'screenshots').glob('*.png')):
            if not current:
                retired.append(dict(path=str(path.relative_to(ROOT)),
                                    reason='superseded native source', variant=variant))
                continue
            name = path.stem
            if name.startswith('mobile_route_'):
                case = name.removeprefix('mobile_route_')
                route = route_names.get(case, '')
                kind = 'Screen'
            elif name.startswith('mobile_state_'):
                case = name.removeprefix('mobile_state_')
                route = state_names.get(case, '')
                kind = 'Platform guard' if platform == 'iOS' and case.startswith('create-group-') else 'State / flow'
            elif name.startswith('detail_'):
                case, route, kind = name.removeprefix('detail_'), '', 'Scroll / recovery'
            else:
                continue
            cards.append(dict(surface='Mobile', title=case.replace('-', ' '),
                              route=route, variant=f'{platform} · {variant}', kind=kind,
                              image=copy(path), evidence=str(path.relative_to(ROOT)),
                              check=('Existing iOS redirect to Groups verified; group creation remains Android-only' if kind == 'Platform guard' else
                                     'Native fixture render passed; visual acceptance pending')))

    admin = read(base / 'exhaustive-admin/admin_browser_qa.json')
    login_refresh = read(base / 'admin-login-final/admin_browser_qa.json')
    login_rows = {(r['route'], r['viewport']): r for r in login_refresh.get('results', [])
                  if not r.get('failures')}
    for row in admin.get('results', []):
        row = login_rows.get((row['route'], row['viewport']), row)
        path = row.get('screenshotPath')
        if path:
            cards.append(dict(surface='Admin', title=row['route'], route=row['route'],
                              variant=row['viewport'], kind='Screen', image=copy(path),
                              check='Browser fixture route / accessibility checks', evidence=path))
    admin_flows = read(base / 'exhaustive-admin-flows/summary.json')
    for row in admin_flows.get('results', []):
        if row.get('screenshot'):
            cards.append(dict(surface='Admin', title=row['name'], route=row['route'],
                              variant=row['viewport'], kind='Dialog / flow',
                              image=copy(row['screenshot']), check=row.get('status', 'unverified'),
                              evidence=row['screenshot']))

    website = read(evidence_path(args.website_report))
    for row in website.get('results', []) + website.get('shareResults', []):
        if not row.get('screenshot'):
            continue
        cards.append(dict(surface='Website', title=row.get('scenario', row['route']), route=row['route'],
                          variant=row['viewport'], kind='Share flow' if 'scenario' in row else 'Page',
                          image=copy(row['screenshot']), full=copy(row['fullPageScreenshot']) if row.get('fullPageScreenshot') else None,
                          check='Browser checks: ' + ('pass' if not row.get('failures') else 'needs correction'),
                          evidence=row['screenshot']))
        if row.get('menuScreenshot'):
            cards.append(dict(surface='Website', title=row['route'] + ' menu', route=row['route'],
                              variant=row['viewport'], kind='Menu', image=copy(row['menuScreenshot']),
                              check='Keyboard containment / Escape / focus return', evidence=row['menuScreenshot']))

    for item in inventory['assets']:
        path = ROOT / item['file']
        cards.append(dict(surface='Assets', title=path.name, route=item['file'], variant=item['kind'],
                          kind=item['kind'], image=copy(path) if path.suffix == '.png' else None,
                          download=copy(path), check=item['comparison'], evidence=item['sha256'],
                          dimensions=f"{item.get('width', '')} × {item.get('height', '')}" if 'width' in item else f"{item['bytes']:,} bytes"))
    for item in read(base / 'icon-atlas/manifest.json').get('results', []):
        cards.append(dict(surface='Assets', title=item['symbol'],
                          route=item.get('family', 'Data-selected icon'),
                          variant='Glyph atlas', kind=item['kind'],
                          image=copy(item['image']) if item.get('image') else None,
                          check='Original bundled glyph preview; see its screen for size, colour and state' if item.get('image') else item['note'],
                          evidence=item.get('font_sha256', 'Dynamic resolver')))
    for item in inventory['ui_units']:
        cards.append(dict(surface='Elements', title=item['name'], route=f"{item['file']}:{item['line']}",
                          variant=item['surface'], kind=item['base'],
                          check='Shared palette and component contract; see the matching route/state capture'))
    for item in inventory['interaction_call_sites']:
        cards.append(dict(surface='Elements', title=item['kind'], route=f"{item['file']}:{item['line']}",
                          variant=item['surface'], kind='Control / presentation call site',
                          check='Source inventory; runtime branches require the named flow evidence'))
    for item in inventory.get('website_dom_elements', []):
        cards.append(dict(surface='Elements', title=item['tag'] + (' · ' + item['classes'] if item['classes'] else ''),
                          route=item['route'] + ((' → ' + item['href']) if item.get('href') else ''),
                          variant='Website', kind='Rendered HTML element',
                          check='Rendered page inventory; see full-page and interaction captures',
                          evidence=f"{item['file']}:{item['line']}"))
    behavior = read(ROOT / args.behavior_report) if args.behavior_report else {}
    for item in behavior.get('tests', inventory['behavioral_tests']):
        cards.append(dict(surface='Flows', title=item['name'], route=item.get('source') or '',
                          variant=item.get('variant', 'Automated fixture check'), kind='Behavior',
                          check=item['result'] + (': ' + item['note'] if item.get('note') else ''),
                          evidence=item.get('evidence')))

    payload = json.dumps(cards).replace('</', '<\\/')
    counts = {label: sum(c['surface'] == label for c in cards)
              for label in ['Mobile', 'Admin', 'Website', 'Assets', 'Elements', 'Flows']}
    (output / 'catalogue.json').write_text(json.dumps(cards, indent=2) + '\n')
    published_inventory = dict(inventory)
    if behavior:
        published_inventory['behavioral_tests'] = behavior['tests']
        published_inventory['behavioral_evidence'] = args.behavior_report
        published_inventory['counts'] = dict(inventory.get('counts', {}))
        published_inventory['counts']['test_results'] = {
            result: sum(test['result'] == result for test in behavior['tests'])
            for result in sorted({test['result'] for test in behavior['tests']})
        }
    (output / 'inventory.json').write_text(json.dumps(published_inventory, indent=2) + '\n')
    shell = '''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Collect · complete design review</title><style>
*{box-sizing:border-box}body{margin:0;background:#09090b;color:#f4f4f4;font:16px/1.5 system-ui,sans-serif}main{max-width:1560px;margin:auto;padding:40px 28px}h1{font-size:clamp(32px,5vw,54px);letter-spacing:-1.5px;line-height:1.06;margin:18px 0}p{max-width:950px;color:#b8b8c2}a{color:inherit}button,input,select{font:inherit;min-height:48px}button,select,input{border:1px solid #414147;background:#18181b;color:#f4f4f4;border-radius:28px;padding:10px 18px}button{cursor:pointer}input{min-width:0;width:100%}button[aria-selected=true]{background:#fff;color:#111}button:focus-visible,a:focus-visible,input:focus-visible,select:focus-visible{outline:3px solid #a7aaff;outline-offset:4px}.status{display:inline-block;padding:7px 14px;border-radius:30px;background:#2a2422;color:#ffc6a9;font-size:13px}.tabs{display:flex;gap:8px;flex-wrap:wrap;margin:28px 0 18px}.tools{display:grid;grid-template-columns:minmax(180px,1fr) minmax(180px,320px);gap:12px}.results{display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:24px;margin-top:24px}.results.phones{grid-template-columns:repeat(auto-fill,minmax(240px,1fr))}.card{min-width:0;padding:16px;background:#161618;border:1px solid #303036;border-radius:22px}.card h2{font-size:18px;line-height:1.3;margin:12px 0 8px;overflow-wrap:anywhere}.card p{font-size:13px;margin:8px 0;overflow-wrap:anywhere}.card .route{color:#d4d4dc}.card .kind{font-size:12px;color:#aaaab6}.card img{width:100%;height:240px;object-fit:contain;object-position:top;border-radius:12px;display:block;background:#222225}.phones .card img{height:460px}.card.assets img{height:180px;object-position:center;background:#f7f7f7;padding:20px}.links{display:flex;gap:20px;flex-wrap:wrap;font-size:14px;margin-top:12px}.empty{padding:28px;border:1px dashed #545460;border-radius:20px}.footer{margin:32px 0;color:#aaaab6;font-size:14px}.load{display:block;margin:30px auto}#count{min-height:24px}.font-preview{font-size:34px;margin:20px 0;color:#fff}.notes{border-left:2px solid #53535e;padding-left:16px}.notes p{font-size:14px;margin:6px 0}@media(max-width:600px){main{padding:28px 16px}.tools{grid-template-columns:1fr}.tabs button{padding:10px 14px}.results,.results.phones{grid-template-columns:1fr}.phones .card img{height:520px}}[hidden]{display:none!important}
</style></head><body><main><span class="status">Complete scope · local QA · visual acceptance pending</span><h1>Every screen. Every state.<br>One Collect design.</h1><p>Browse current mobile screens and flow states, Admin routes and dialogs, full website pages and menus, runtime assets, shared UI elements, and named behavioral checks.</p><div class="notes"><p>Target captures use synthetic data. Native, Business and public-web reference cohorts remain distinct.</p><p>100% fidelity is not certified: the mandatory mobile gate, exact native typography and remaining source/state comparisons stay open. No production release is implied.</p></div><nav class="tabs" role="tablist" aria-label="Review scope"></nav><div class="tools"><label><span class="sr">Search this surface</span><input type="search" id="search" placeholder="Search route, state, asset, or control"></label><label>Variant<select id="variant" style="display:block;width:100%"><option>All variants</option></select></label></div><p id="count" role="status" aria-live="polite"></p><div id="results" class="results phones"></div><button id="more" class="load">Show more</button><p class="footer"><a href="inventory.json">Complete source inventory</a> · <a href="catalogue.json">Capture and check catalogue</a>. Open a capture for its original pixels; website cards also link to the entire page.</p></main><script>
const data=__DATA__;const surfaces=['Mobile','Admin','Website','Assets','Elements','Flows'];let surface='Mobile',limit=24;const $=id=>document.getElementById(id);const results=$('results');const tabs=document.querySelector('.tabs');const e=(tag,txt,cls)=>{const n=document.createElement(tag);if(txt)n.textContent=txt;if(cls)n.className=cls;return n};const link=(href,title)=>{const a=e('a',title);a.href=href;a.target='_blank';a.rel='noopener';return a};
surfaces.forEach((name,i)=>{const b=e('button',name);b.role='tab';b.id='tab-'+name;b.setAttribute('aria-controls','results');b.onclick=()=>choose(name);b.onkeydown=ev=>{let n;if(ev.key==='ArrowRight')n=(i+1)%surfaces.length;if(ev.key==='ArrowLeft')n=(i+surfaces.length-1)%surfaces.length;if(ev.key==='Home')n=0;if(ev.key==='End')n=surfaces.length-1;if(n!==undefined){ev.preventDefault();choose(surfaces[n]);document.getElementById('tab-'+surfaces[n]).focus()}};tabs.append(b)});
function choose(name){surface=name;limit=24;document.querySelectorAll('[role=tab]').forEach(b=>{const on=b.textContent===surface;b.setAttribute('aria-selected',on);b.tabIndex=on?0:-1});$('search').value='';$('variant').replaceChildren(new Option('All variants',''));[...new Set(data.filter(d=>d.surface===surface).map(d=>d.variant))].sort().forEach(v=>$('variant').add(new Option(v,v)));results.role='tabpanel';results.setAttribute('aria-labelledby','tab-'+name);draw()}
function draw(){const query=$('search').value.trim().toLowerCase(),variant=$('variant').value;const matches=data.filter(d=>d.surface===surface&&(!variant||d.variant===variant)&&(!query||[d.title,d.route,d.kind,d.variant].join(' ').toLowerCase().includes(query)));$('count').textContent=matches.length+' '+surface.toLowerCase()+' records · showing '+Math.min(limit,matches.length);results.className='results'+(surface==='Mobile'?' phones':'');results.replaceChildren();matches.slice(0,limit).forEach(d=>{const c=e('article',null,'card'+(surface==='Assets'?' assets':''));if(d.image){const a=link(d.image,'');const img=e('img');img.src=d.image;img.alt=d.title;img.loading='lazy';a.append(img);c.append(a)}else if(d.kind==='font'){const id='font-'+d.title.replace(/[^a-z0-9]/ig,'');if(!document.getElementById(id)){const s=e('style');s.id=id;s.textContent='@font-face{font-family:"'+id+'";src:url("'+d.download+'")}';document.head.append(s)}const p=e('div','Aa 012345','font-preview');p.style.fontFamily=id;c.append(p)}c.append(e('div',d.kind+' · '+d.variant,'kind'),e('h2',d.title),e('p',d.route,'route'),e('p',d.check));if(d.dimensions)c.append(e('p',d.dimensions));const links=e('div',null,'links');if(d.image)links.append(link(d.image,'Original capture'));else if(d.download)links.append(link(d.download,'Open asset'));if(d.full)links.append(link(d.full,'Full page'));c.append(links);results.append(c)});if(!matches.length)results.append(e('p','No matching records. Try another search or variant.','empty'));$('more').hidden=limit>=matches.length}
$('search').oninput=()=>{limit=24;draw()};$('variant').onchange=()=>{limit=24;draw()};$('more').onclick=()=>{limit+=24;draw()};const initial=new URLSearchParams(location.search);choose(surfaces.includes(initial.get('surface'))?initial.get('surface'):'Mobile');$('search').value=initial.get('search')||'';draw();
</script></body></html>'''
    if component:
        shell = shell.replace('<nav class="tabs"',
                              '<p><a href="group-cards.html">New: group cards beside your RevPoints reference →</a></p><nav class="tabs"', 1)
    if supplement:
        shell = shell.replace('<nav class="tabs"',
                              '<p><a href="responsive.html">Latest: ' + html.escape(supplement['title']) + ' →</a></p><nav class="tabs"', 1)
    if keyboard_current:
        shell = shell.replace('<nav class="tabs"',
                              '<p><a href="native-keyboard.html">Latest: real Android keyboard checks →</a></p><nav class="tabs"', 1)
    (output / 'index.html').write_text(shell.replace('__DATA__', payload))
    (output / 'capture-freshness.json').write_text(json.dumps({
        'current_source_sha256': current_source,
        'runtime_sha256': runtime,
        'excluded_obsolete_captures': retired,
        'reviewed_current_native_recaptures': current_recaptures,
        'required_routes': inventory['mobile_routes'],
        'required_states': inventory['mobile_states'],
        'scope': 'Obsolete images are excluded. Route/state requirements and acceptance gates are retained.'
    }, indent=2) + '\n')
    # These are generated copies. Do not leave removed designs available at
    # their old URLs after rebuilding the visible catalogue.
    published = '\n'.join(path.read_text() for path in output.glob('*.html')) + payload
    used = set(re.findall(r'media/([0-9a-f]{16}\.[a-zA-Z0-9]+)', published))
    for path in (output / 'media').glob('*'):
        if path.is_file() and re.fullmatch(r'[0-9a-f]{16}\.[a-zA-Z0-9]+', path.name) and path.name not in used:
            path.unlink()
    print(json.dumps({'output': str(output), 'records': counts}))


if __name__ == '__main__':
    main()
