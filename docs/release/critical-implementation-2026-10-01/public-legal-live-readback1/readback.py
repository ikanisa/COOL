#!/usr/bin/env python3
"""Bounded anonymous GET proof; no publication, credentials or request submission."""
import concurrent.futures
import difflib
import hashlib
import json
import re
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
ARTIFACT = ROOT / '.cache/public-static-current-20261002-batch4-attempt1'
ORIGIN = 'https://collect.ikanisa.com'
LEGAL = ['/privacy/', '/terms/', '/account-deletion/', '/data-deletion/', '/trust/', '/security/']
MAX_BODY = 2 * 1024 * 1024
SUPPORT_HOSTS = {'wa.me', 'api.whatsapp.com', 'www.whatsapp.com', 'whatsapp.com', 'web.whatsapp.com'}
SAFE_HEADERS = {'date', 'server', 'content-type', 'content-length', 'cache-control', 'cf-cache-status',
                'etag', 'last-modified', 'location', 'content-security-policy', 'x-content-type-options',
                'referrer-policy', 'strict-transport-security', 'cf-ray'}


def now():
    return datetime.now(timezone.utc).isoformat()


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def write(name, obj):
    (OUT / name).write_text(json.dumps(obj, indent=2, ensure_ascii=False) + '\n')


class Page(HTMLParser):
    def __init__(self, html):
        super().__init__(convert_charrefs=True)
        self.links, self.ids, self.images = [], [], []
        self.canonical, self.title, self.h1 = '', [], []
        self.text, self.legal_text = [], []
        self.stack, self.active_link = [], None
        self.feed(html)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if attrs.get('id'):
            self.ids.append(attrs['id'])
        if tag == 'link' and attrs.get('rel') == 'canonical':
            self.canonical = attrs.get('href', '')
        if tag == 'img':
            self.images.append({'src': attrs.get('src'), 'alt': attrs.get('alt')})
        if tag == 'a' and 'href' in attrs:
            self.active_link = {'href': attrs['href'], 'label_parts': [], 'class': attrs.get('class', '')}
            self.links.append(self.active_link)
        if tag not in {'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'param', 'source', 'track', 'wbr'}:
            self.stack.append((tag, 'legal-content' in attrs.get('class', '').split()))

    def handle_endtag(self, tag):
        if tag == 'a':
            self.active_link = None
        for i in range(len(self.stack) - 1, -1, -1):
            if self.stack[i][0] == tag:
                self.stack = self.stack[:i]
                break

    def handle_data(self, data):
        tags = [x[0] for x in self.stack]
        if any(x in tags for x in ('script', 'style')):
            return
        value = ' '.join(data.split())
        if not value:
            return
        self.text.append(value)
        if any(x[1] for x in self.stack):
            self.legal_text.append(value)
        if 'title' in tags:
            self.title.append(value)
        if 'h1' in tags:
            self.h1.append(value)
        if self.active_link is not None:
            self.active_link['label_parts'].append(value)

    def data(self):
        return {'canonical': self.canonical, 'title': ' '.join(self.title), 'h1': ' '.join(self.h1),
                'ids': self.ids, 'images': self.images,
                'links': [{**{k: v for k, v in x.items() if k != 'label_parts'},
                           'label': ' '.join(x['label_parts'])} for x in self.links],
                'visible_text': '\n'.join(self.text), 'legal_text': '\n'.join(self.legal_text)}


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def fetch(url, purpose='same_origin'):
    started = now()
    initial = urllib.parse.urldefrag(url)[0]
    current = initial
    hops = []
    body = b''
    error = None
    for i in range(4):
        parsed = urllib.parse.urlsplit(current)
        allowed = parsed.scheme == 'https' and (parsed.netloc == 'collect.ikanisa.com' if purpose == 'same_origin'
                                                 else parsed.hostname in SUPPORT_HOSTS)
        if not allowed:
            error = 'Redirect outside allowed HTTPS destination; not followed'
            break
        t0 = time.monotonic()
        req = urllib.request.Request(current, headers={'User-Agent': 'Collect-Public-Legal-Readback/1.0',
                                                      'Accept': 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.1'}, method='GET')
        try:
            try:
                response = urllib.request.build_opener(NoRedirect()).open(req, timeout=15)
            except urllib.error.HTTPError as exc:
                response = exc
            with response:
                headers = {k.lower(): v for k, v in response.headers.items() if k.lower() in SAFE_HEADERS}
                body = response.read(MAX_BODY + 1)
                status = response.code
                hops.append({'url': current, 'status': status, 'headers': headers,
                             'elapsed_seconds': round(time.monotonic() - t0, 3),
                             'body_sha256': hashlib.sha256(body).hexdigest(), 'body_bytes': len(body)})
            if len(body) > MAX_BODY:
                error = 'Body limit exceeded; bounded response rejected'
                break
            if status in {301, 302, 303, 307, 308} and headers.get('location'):
                if i == 3:
                    error = 'Maximum 3 redirects reached'
                    break
                current = urllib.parse.urljoin(current, headers['location'])
                continue
            break
        except Exception as exc:
            error = f'{type(exc).__name__}: {exc}'
            break
    parsed = urllib.parse.urlsplit(initial)
    key = re.sub(r'[^a-zA-Z0-9_-]', '-', parsed.path.strip('/') or 'root')
    key += '-' + hashlib.sha256(initial.encode()).hexdigest()[:10]
    body_path = f'responses/{key}.html'
    (OUT / 'responses').mkdir(exist_ok=True)
    (OUT / body_path).write_bytes(body)
    result = {'requested_url': initial, 'purpose': purpose, 'started_at_utc': started,
              'finished_at_utc': now(), 'method': 'GET', 'anonymous': True,
              'redirects': hops, 'final_url': current, 'final_status': hops[-1]['status'] if hops else None,
              'body_sha256': hashlib.sha256(body).hexdigest(), 'body_bytes': len(body),
              'body_path': body_path, 'error': error}
    result['page'] = Page(body.decode('utf-8', errors='replace')).data()
    return result


def run_many(urls, purpose='same_origin'):
    if len(urls) > 40:
        raise RuntimeError('More than 40 distinct URLs; widen scope only after review')
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        return {url: result for url, result in zip(urls, pool.map(lambda x: fetch(x, purpose), urls))}


started = now()
phase_path = ROOT / 'docs/release/critical-implementation-2026-10-01/public-media-batch4/static-build-execution.json'
phase = json.loads(phase_path.read_text())
tracked_paths = [Path(p) for p in phase['inputs_before']]
tracked_paths += [ROOT / p for p in ['AGENTS.md', 'deploy/public.wrangler.jsonc', 'scripts/qa/ios_delivery_guard.py',
                                     'fastlane/metadata/en-GB/privacy_url.txt']]
sources_before = {str(p.relative_to(ROOT)): sha(p) for p in sorted(set(tracked_paths))}
artifact_before = {str(p.relative_to(ARTIFACT)): sha(p) for p in sorted(ARTIFACT.rglob('*')) if p.is_file()}
original_artifact_hashes = json.loads((phase_path.parent / 'static-artifact.before.json').read_text())
source_phase_mismatches = [{'path': str(Path(p).relative_to(ROOT)), 'recorded_sha256': digest,
                          'current_sha256': sources_before[str(Path(p).relative_to(ROOT))]}
                         for p, digest in phase['inputs_before'].items()
                         if sources_before[str(Path(p).relative_to(ROOT))] != digest]
write('sources-before.json', sources_before)
write('artifact-before.json', artifact_before)
local = {}
for route in ['/'] + LEGAL:
    p = ARTIFACT / (route.strip('/') + '/index.html' if route != '/' else 'index.html')
    local[route] = {'path': str(p.relative_to(ROOT)), 'sha256': sha(p), 'page': Page(p.read_text()).data()}
write('generated-legal-graph.json', local)
local_edges = []
for route in LEGAL:
    for link in local[route]['page']['links']:
        absolute = urllib.parse.urljoin(ORIGIN + route, link['href'])
        if urllib.parse.urlsplit(absolute).netloc == 'collect.ikanisa.com':
            local_edges.append({'source_route': route, **link, 'absolute_url': absolute})
internal_urls = sorted({urllib.parse.urldefrag(x['absolute_url'])[0] for x in local_edges} | {ORIGIN + x for x in ['/'] + LEGAL})
results = run_many(internal_urls)
# Cover older legal destinations actually exposed by current live legal pages,
# while excluding unrelated store/download and arbitrary third-party marketing links.
live_edges = []
for route in LEGAL:
    for link in results[ORIGIN + route]['page']['links']:
        absolute = urllib.parse.urljoin(results[ORIGIN + route]['final_url'], link['href'])
        if urllib.parse.urlsplit(absolute).netloc == 'collect.ikanisa.com':
            live_edges.append({'source_route': route, **link, 'absolute_url': absolute})
extra_urls = sorted({urllib.parse.urldefrag(x['absolute_url'])[0] for x in live_edges} - set(results))
results.update(run_many(extra_urls))


def edge_check(edge):
    target, fragment = urllib.parse.urldefrag(edge['absolute_url'])
    row = results[target]
    page_ok = row['final_status'] == 200 and row['error'] is None
    anchor_ok = not fragment or urllib.parse.unquote(fragment) in row['page']['ids']
    return {**edge, 'final_url': row['final_url'], 'final_status': row['final_status'], 'error': row['error'],
            'fragment': fragment or None, 'anchor_present': anchor_ok if fragment else None,
            'check_scope': 'HTTP status and fragment presence only; candidate intended content and deployment parity assessed separately',
            'status': 'pass' if page_ok and anchor_ok else 'fail'}


generated_links = [edge_check(x) for x in local_edges]
live_links = [edge_check(x) for x in live_edges]
support_links = []
for origin_label, pages in [('generated', local), ('live', {r: results[ORIGIN + r] for r in LEGAL})]:
    for route, row in pages.items():
        if route not in LEGAL:
            continue
        for link in row['page']['links']:
            href = link['href']
            parsed = urllib.parse.urlsplit(href)
            if parsed.scheme == 'mailto':
                support_links.append({'origin': origin_label, 'source_route': route, **link,
                                      'address': parsed.path, 'query': parsed.query,
                                      'address_matches_supported': parsed.path == 'info@ikanisa.com',
                                      'verification': 'URI/address only; no mail application or message'})
            elif parsed.hostname in SUPPORT_HOSTS:
                support_links.append({'origin': origin_label, 'source_route': route, **link,
                                      'phone_matches_supported': parsed.path == '/250795588248'})
support_urls = sorted({x['href'] for x in support_links if x['href'].startswith('https:')})
support_results = run_many(support_urls, 'support')
write('live-responses.json', results)
write('generated-links-live-check.json', generated_links)
write('live-legal-links-check.json', live_links)
write('support-links.json', {'links': support_links, 'anonymous_gets': support_results,
                             'no_message_sent': True, 'mailto_delivery_unknown': True})
comparisons = []
for route in ['/'] + LEGAL:
    live = results[ORIGIN + route]
    current = local[route]
    old = live['page']
    expected = current['page']
    normalized_live = old['legal_text'] if route != '/' else old['visible_text']
    normalized_local = expected['legal_text'] if route != '/' else expected['visible_text']
    filename = (route.strip('/') or 'root') + '.visible-text.diff'
    (OUT / filename).write_text(''.join(difflib.unified_diff(normalized_live.splitlines(True),
        normalized_local.splitlines(True), fromfile=ORIGIN + route, tofile=current['path'])))
    comparisons.append({'route': route, 'live_url': live['final_url'], 'live_status': live['final_status'],
                        'live_sha256': live['body_sha256'], 'candidate_path': current['path'],
                        'candidate_sha256': current['sha256'], 'bytes_equal': live['body_sha256'] == current['sha256'],
                        'legal_visible_text_equal' if route != '/' else 'root_visible_text_equal': normalized_live == normalized_local,
                        'live_canonical': old['canonical'], 'candidate_canonical': expected['canonical'],
                        'canonical_equal': old['canonical'] == expected['canonical'],
                        'live_h1': old['h1'], 'candidate_h1': expected['h1'],
                        'candidate_hero_images': expected['images'], 'live_hero_images': old['images'],
                        'visible_text_diff': filename})
write('candidate-live-comparison.json', comparisons)
sources_after = {str(p.relative_to(ROOT)): sha(p) for p in sorted(set(tracked_paths))}
artifact_after = {str(p.relative_to(ARTIFACT)): sha(p) for p in sorted(ARTIFACT.rglob('*')) if p.is_file()}
write('sources-after.json', sources_after)
write('artifact-after.json', artifact_after)
summary = {'scope': 'PD-05 public legal live readback and limited PD-04 public root/deployment observation',
           'started_at_utc': started, 'finished_at_utc': now(), 'public_url': ORIGIN,
           'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
           'method': 'anonymous bounded GET only', 'bounds': {'max_body_bytes': MAX_BODY, 'timeout_seconds_per_hop': 15,
                    'max_redirects': 3, 'concurrency': 4, 'retries': 0},
           'same_origin_get_count': len(results), 'support_get_count': len(support_results),
           'generated_legal_internal_link_count': len(generated_links),
           'generated_link_result_scope': 'HTTP/fragment checks only, not intended-content, visual, interaction or source/deployment acceptance',
           'generated_legal_internal_link_failures': [x for x in generated_links if x['status'] != 'pass'],
           'live_legal_internal_link_count': len(live_links),
           'live_legal_internal_link_failures': [x for x in live_links if x['status'] != 'pass'],
           'response_failures': [{k: v for k, v in x.items() if k != 'page'} for x in results.values()
                                 if x['final_status'] != 200 or x['error']],
           'source_file_count': len(sources_before), 'sources_untouched': sources_before == sources_after,
           'current_inputs_match_prior_static_build_record': not source_phase_mismatches,
           'prior_static_build_input_mismatches': source_phase_mismatches,
           'candidate_file_count': len(artifact_before), 'candidate_untouched': artifact_before == artifact_after,
           'candidate_matches_original_artifact_hashes': artifact_before == original_artifact_hashes,
           'candidate_direct_entries_compared': comparisons,
           'public_candidate_parity': 'not established; sampled public bytes differ from current local artifact',
           'authenticated_cloudflare_deployment_metadata': 'not observed',
           'provider_publication_or_mutation': False, 'account_or_data_requests': False,
           'legal_approval': 'not established', 'rendered_browser_visual_and_interaction_acceptance': 'not observed',
           'support_delivery_and_privacy_erasure_lifecycle_acceptance': 'not exercised'}
write('readback-summary.json', summary)
print(json.dumps({k: v for k, v in summary.items() if k not in ['candidate_direct_entries_compared',
                 'generated_legal_internal_link_failures', 'live_legal_internal_link_failures', 'response_failures']}, indent=2))
print('GENERATED_LINK_FAILURES', len(summary['generated_legal_internal_link_failures']))
print('LIVE_LINK_FAILURES', len(summary['live_legal_internal_link_failures']))
print('RESPONSE_FAILURES', [(x['requested_url'], x['final_status'], x['error']) for x in summary['response_failures']])
