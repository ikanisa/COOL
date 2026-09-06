#!/usr/bin/env python3
"""Source inventory for full-surface review; this never writes acceptance.

The route matrices remain the executable authority. Static call sites identify
review work, not proof of runtime reachability, behavior or visual fidelity.
"""
import argparse
import hashlib
import json
import re
from collections import Counter
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parents[2]
SCOPE = ('lib/app', 'lib/features', 'lib/shared/widgets', 'lib/core/widgets', 'lib/admin')
CALLS = re.compile(
    r'\b(showModalBottomSheet|showDialog|showCollectConfirmationSheet|'
    r'showCollectCountryPicker|PopupMenuButton|DropdownButtonFormField|'
    r'SwitchListTile|CheckboxListTile|RadioListTile|ChoiceChip|SegmentedButton|'
    r'TextField|TextFormField|CollectButton|IconButton|CollectListTile|'
    r'InkWell|GestureDetector|Image\.(?:asset|network|memory)|CircleAvatar|'
    r'QrImageView|SnackBar|LoadingSkeleton|CollectErrorState|CollectEmptyState)'
    r'(?:<[^;()]*>)?(?:\.[a-zA-Z_]+)?\s*\('
)
WIDGET = re.compile(
    r'\bclass\s+(\w+)(?:<[^>{}]*>)?\s+extends\s+'
    r'(StatelessWidget|StatefulWidget|ConsumerWidget|ConsumerStatefulWidget|'
    r'State|ConsumerState|CustomPainter|InheritedWidget)\b'
)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def location(path, text, offset):
    return {'file': str(path.relative_to(ROOT)), 'line': text.count('\n', 0, offset) + 1}


def surface(path):
    value = str(path)
    if '/admin/' in value:
        return 'admin'
    if '/landing/' in value:
        return 'website'
    if '/shared/' in value or '/theme/' in value:
        return 'shared'
    return 'mobile'


def state_specs(path, kind):
    text = path.read_text()
    # Constructors in the declared constant matrices; constructor definitions
    # cannot match the three literal positional values.
    pattern = re.compile(
        rf'_{kind}Spec\(\s*[\'\"]([^\'\"]+)[\'\"]\s*,\s*'
        r'[\'\"]([^\'\"]+)[\'\"]\s*,\s*[\'\"]([^\'\"]+)[\'\"]'
    )
    return [dict(name=m[1], route=m[2], declared_marker_or_kind=m[3],
                 **location(path, text, m.start())) for m in pattern.finditer(text)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', required=True)
    parser.add_argument('--test-results')
    args = parser.parse_args()
    sources = sorted({p for directory in SCOPE for p in (ROOT / directory).rglob('*.dart')} |
                     {ROOT / 'lib/main_public.dart', ROOT / 'lib/main_admin.dart'})
    units, calls, icons = [], [], []
    for path in sources:
        text = path.read_text()
        for match in WIDGET.finditer(text):
            units.append(dict(name=match[1], base=match[2], surface=surface(path),
                              **location(path, text, match.start())))
        for match in CALLS.finditer(text):
            calls.append(dict(kind=match[1], surface=surface(path),
                              **location(path, text, match.start())))
        for match in re.finditer(r'\b(CollectIcons|CollectSemanticIcons|Icons|CupertinoIcons|FontAwesomeIcons)\.(\w+)', text):
            if match[2].startswith('_'):
                continue  # Namespace constructors are not rendered glyphs.
            icons.append(dict(symbol=f'{match[1]}.{match[2]}', surface=surface(path),
                              **location(path, text, match.start())))

    comparisons = json.loads((ROOT / 'docs/release/mobile-design/revolut-surface-comparisons-2026-09-05.json').read_text())
    website_elements = []
    class PublicElements(HTMLParser):
        in_body = False
        def handle_starttag(self, tag, attrs):
            if tag == 'body':
                self.in_body = True
            if not self.in_body or tag in ('script', 'style'):
                return
            attrs = dict(attrs)
            website_elements.append(dict(tag=tag, classes=attrs.get('class', ''),
                                         role=attrs.get('role'), href=attrs.get('href'),
                                         file=self.source, line=self.getpos()[0], route=self.route))
        def handle_endtag(self, tag):
            if tag == 'body':
                self.in_body = False
    sitemap = ROOT / 'build/public_web/sitemap.xml'
    if sitemap.exists():
        for url in re.findall(r'<loc>([^<]+)</loc>', sitemap.read_text()):
            route = urlparse(url).path or '/'
            page = ROOT / 'build/public_web' / route.strip('/') / 'index.html'
            if page.exists():
                parser = PublicElements()
                parser.source, parser.route = str(page.relative_to(ROOT)), route
                parser.feed(page.read_text())
    assets = []
    for directory in ('assets', 'web/public/app-screens', 'web/icons', 'android/app/src/main/res', 'ios/Runner/Assets.xcassets'):
        for path in sorted((ROOT / directory).rglob('*')):
            if not path.is_file() or path.name.startswith('.'):
                continue
            if path.suffix.lower() not in ('.png', '.jpg', '.jpeg', '.webp', '.svg', '.ttf', '.otf', '.woff', '.woff2', '.xml'):
                continue
            if path.name == 'data_extraction_rules.xml':
                continue  # Android data-access configuration, not a UI asset.
            rel = str(path.relative_to(ROOT))
            kind = ('font' if path.suffix in ('.ttf', '.otf', '.woff', '.woff2') else
                    'app-screenshot' if '/app-screens/' in rel else
                    'marketing-image' if '/marketing/' in rel else
                    'platform-style' if path.suffix == '.xml' else 'own-product-icon')
            entry = dict(file=rel, kind=kind, bytes=path.stat().st_size, sha256=sha(path),
                         comparison='required own identity adaptation' if kind == 'own-product-icon' else
                         'unchanged native app capture; example data; verified source and image hashes' if kind == 'app-screenshot' else
                         'owner-directed Rwanda editorial; generated illustrative scene' if kind == 'marketing-image' else
                         'surface-specific font or platform adapter')
            if path.suffix.lower() in ('.png', '.jpg', '.jpeg', '.webp'):
                from PIL import Image
                with Image.open(path) as im:
                    entry['width'], entry['height'] = im.size
            assets.append(entry)

    tests = []
    if args.test_results:
        starts, suites = {}, {}
        for line in Path(args.test_results).read_text().splitlines():
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not isinstance(event, dict):
                continue
            if event.get('type') == 'suite':
                suites[event['suite']['id']] = event['suite']['path']
            elif event.get('type') == 'testStart':
                starts[event['test']['id']] = event['test']
            elif event.get('type') == 'testDone' and event['testID'] in starts:
                start = starts[event['testID']]
                if event.get('hidden', False):
                    continue
                tests.append(dict(name=start['name'], result=event['result'],
                                  skipped=event.get('skipped', False),
                                  source=suites.get(start.get('suiteID'), start.get('root_url', start.get('url')))))

    routes = state_specs(ROOT / 'integration_test/mobile_route_matrix_device_uat_test.dart', 'Route')
    states = state_specs(ROOT / 'integration_test/mobile_material_state_matrix_device_uat_test.dart', 'State')
    report = dict(
        schema_version=1,
        generated_at=datetime.now(timezone.utc).isoformat(),
        scope='Every source-declared UI unit, interaction call site, runtime asset and executable route/state in mobile, Admin and public web.',
        limitations=[
            'Static call sites include alternative branches and may include unused widgets; they are not runtime coverage.',
            'Test success is behavioral evidence for the named test, not visual approval or a pixel-equivalence score.',
            'Native OS permissions, keyboards, pickers, sharing and external payment apps retain platform UI.',
            'Exact current native fonts, unseen native source states and authenticated Business geometry remain unverified.',
        ],
        source_files=[dict(file=str(p.relative_to(ROOT)), sha256=sha(p)) for p in sources],
        mobile_routes=routes, mobile_states=states,
        admin_routes=comparisons['admin_routes'],
        website_routes=comparisons['website_routes'],
        website_share_states=comparisons.get('website_share_states', []),
        ui_units=units, interaction_call_sites=calls,
        icon_symbols=sorted(set(i['symbol'] for i in icons)), icon_call_sites=icons,
        assets=assets, behavioral_tests=tests, website_dom_elements=website_elements,
        counts=dict(source_files=len(sources), ui_units=len(units),
                    ui_units_by_base=dict(Counter(u['base'] for u in units)),
                    interaction_call_sites=len(calls), icon_symbols=len(set(i['symbol'] for i in icons)),
                    assets=len(assets), website_dom_elements=len(website_elements),
                    mobile_routes=len(routes), mobile_states=len(states),
                    admin_route_viewports=len(comparisons['admin_routes']),
                    website_route_viewports=len(comparisons['website_routes']),
                    test_results=dict(Counter(t['result'] for t in tests))),
        acceptance='unverified; see MOBILE-DESIGN-100 and the per-case comparison register',
    )
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'output': str(out), **report['counts']}))


if __name__ == '__main__':
    main()
