"""Validate actual template contracts and emit escaped synthetic HTML previews.

This deliberately does not claim Go-template execution or email-client delivery.
"""
from datetime import datetime, timezone
import hashlib
import html
from html.parser import HTMLParser
import json
from pathlib import Path
import re
from urllib.parse import parse_qs, urlsplit

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parent.parent
SUBSTITUTIONS = {'SiteURL': 'https://platform-admin.collect.ikanisa.com', 'Token': '012345', 'TokenHash': 'a' * 64}
EXPECTED = {
    'invite': ('Your invitation to Collect', 'Join Collect', {'SiteURL'}, 'Open Collect'),
    'magic_link': ('Your Collect sign-in code', 'Your sign-in code', {'Token'}, None),
    'confirmation': ('Your Collect sign-in code', 'Your sign-in code', {'Token'}, None),
    'recovery': ('Reset your Collect password', 'Reset your password', {'SiteURL', 'TokenHash'}, 'Reset password'),
}


class Email(HTMLParser):
    def __init__(self):
        super().__init__()
        self.tags = []
        self.text = []
        self.headings = []
        self.links = []
        self.current_link = None
        self.heading = False
        self.ignored = 0
        self.language = None

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        self.tags.append(tag)
        if tag == 'html':
            self.language = attrs.get('lang')
        if tag in ('head', 'style'):
            self.ignored += 1
        if tag == 'h1':
            self.heading = True
        if tag == 'a':
            self.current_link = {'href': attrs.get('href'), 'label': ''}
        assert not any(name.lower().startswith('on') for name in attrs), 'Executable event attribute'

    def handle_endtag(self, tag):
        if tag in ('head', 'style'):
            self.ignored -= 1
        if tag == 'h1':
            self.heading = False
        if tag == 'a' and self.current_link is not None:
            self.links.append(self.current_link)
            self.current_link = None

    def handle_data(self, data):
        if not self.ignored:
            self.text.append(data)
        if self.heading:
            self.headings.append(data)
        if self.current_link is not None:
            self.current_link['label'] += data


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate():
    payload = json.loads((ROOT / 'auth-template-config.json').read_text())
    expected_fields = {prefix + name + suffix for name in EXPECTED for prefix, suffix in [('mailer_subjects_', ''), ('mailer_templates_', '_content')]}
    assert set(payload) == expected_fields, 'Unexpected or missing Auth config fields'
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    output = PROJECT / 'docs/implementation/supabase-uat/previews' / stamp
    output.mkdir(parents=True)
    results = []
    for name, (subject, heading, variables, action) in EXPECTED.items():
        source = (ROOT / (name + '.html')).read_text()
        assert payload['mailer_subjects_' + name] == subject
        assert payload['mailer_templates_' + name + '_content'] == source
        references = re.findall(r'{{\s*\.([A-Za-z]+)\s*}}', source)
        assert set(references) == variables, (name, references)
        assert '{{' not in re.sub(r'{{\s*\.[A-Za-z]+\s*}}', '', source), 'Unsupported Go template action'
        assert '.ConfirmationURL' not in source and 'access_token' not in source and 'refresh_token' not in source
        assert 'Collect Admin' not in source and 'Revolut' not in source
        rendered = re.sub(r'{{\s*\.([A-Za-z]+)\s*}}', lambda match: html.escape(SUBSTITUTIONS[match[1]], quote=True), source)
        email = Email()
        email.feed(rendered)
        assert email.language == 'en' and email.headings == [heading]
        assert not set(email.tags) & {'script', 'iframe', 'form', 'input', 'img', 'link', 'object'}
        visible = ''.join(email.text)
        assert 'info@ikanisa.com' in visible
        assert [item for item in email.links if item['href'] == 'mailto:info@ikanisa.com'] == [{'href': 'mailto:info@ikanisa.com', 'label': 'info@ikanisa.com'}]
        actions = [item for item in email.links if not item['href'].startswith('mailto:')]
        if action:
            assert len(actions) == 1 and actions[0]['label'] == action
            url = urlsplit(actions[0]['href'])
            assert url.scheme == 'https' and url.netloc == 'platform-admin.collect.ikanisa.com' and not url.query
            if name == 'invite':
                assert url.fragment == '/admin/login'
                assert 'You have been invited to Collect.' in visible and 'does not sign you in' in visible
                assert 'password' not in visible.lower() and 'TokenHash' not in source
            else:
                path, _, query = url.fragment.partition('?')
                assert path == '/admin/setup' and parse_qs(query) == {'token': [SUBSTITUTIONS['TokenHash']], 'invite': ['false']}
                assert SUBSTITUTIONS['TokenHash'] not in visible
            assert actions[0]['href'] not in visible, 'Raw action URL is visibly printed'
        else:
            assert actions == [] and visible.count(SUBSTITUTIONS['Token']) == 1
            assert '5 minutes' in visible and 'Never share your code' in visible
            if name == 'confirmation':
                assert 'confirm your email and continue' in visible
                assert references == ['Token'], 'Confirmation must contain only the managed OTP'
        assert '{{' not in rendered
        target = output / (name + '.html')
        target.write_text(rendered)
        results.append({'template': name, 'source_sha256': sha(ROOT / (name + '.html')), 'subject': subject,
            'allowed_variables': sorted(variables), 'primary_action': actions[0] if actions else None,
            'preview': str(target), 'preview_sha256': sha(target), 'contract': 'pass'})
    receipt = {'format': 'collect.supabase.auth-template-contract-validation.v1', 'at': datetime.now(timezone.utc).isoformat(),
        'project_id': 'rrlduytparvsjfmegalh', 'templates': results, 'source_inputs': {name: sha(ROOT / name) for name in ('build_templates.py', 'validate_templates.py', 'auth-template-config.json')},
        'method': 'Strict variable/action allowlist, escaped synthetic substitution, parsed HTML and actual Auth/client URL contracts',
        'actual_Go_template_engine_executed': False, 'browser_visual_review_completed': False, 'email_client_render_verified': False,
        'remote_auth_configuration_applied': False, 'provider_sends': 0, 'real_token_or_account_values': False}
    path = output / 'validation.json'
    path.write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'receipt': str(path), 'sha256': sha(path), 'template_contracts_passed': len(results), 'preview_directory': str(output), 'provider_sends': 0}))


if __name__ == '__main__':
    validate()
