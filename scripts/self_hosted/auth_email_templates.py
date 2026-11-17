"""Prepare Admin-only email candidates from the selected public profile.

Bundled email_templates preserve the existing generic public fallback exactly.
This tool only creates a new private output directory; it never applies a
runtime configuration, replaces a bound host file or sends an Auth request."""
from pathlib import Path
import argparse
import hashlib
import html
from html.parser import HTMLParser
import json
import os
import re
import stat
from urllib.parse import urlsplit

HERE = Path(__file__).resolve().parent
PINS = {
    'auth-magic_link.html': '364ed1275a750e8c0a300f4ec7169821f39a5a7939ab5d66b803dc5b3fbc6ac1',
    'auth-confirmation.html': '54a29bfc9a6df15d2f5250b41b9d73cc99a581d08bf5577e29b19e504c51d003',
}


def need(value, message):
    if not value:
        raise ValueError(message)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def physical_file(path):
    info = path.lstat()
    need(path.is_absolute() and path.resolve(strict=True) == path and stat.S_ISREG(info.st_mode)
         and info.st_uid in (0, os.getuid()) and info.st_nlink == 1 and not info.st_mode & 0o022,
         'physical_owned_file_required')
    return path.read_bytes()


def sync(directory):
    fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def write_new(path, raw):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'wb') as handle:
        handle.write(raw)
        handle.flush()
        os.fsync(handle.fileno())
    sync(path.parent)


def selected_origin(profile, expected):
    digest = sha(json.dumps(profile, sort_keys=True, separators=(',', ':')).encode())
    need(re.fullmatch('[a-f0-9]{64}', expected) and digest == expected, 'selected_profile_hash_mismatch')
    origin = profile.get('admin_origin')
    need(isinstance(origin, str) and len(origin) <= 253, 'approved_admin_origin_required')
    parsed = urlsplit(origin)
    need(parsed.scheme == 'https' and parsed.hostname == parsed.netloc
         and re.fullmatch('[a-z0-9.-]+', parsed.netloc)
         and not parsed.path and not parsed.query and not parsed.fragment
         and parsed.username is None and parsed.password is None,
         'exact_https_Admin_origin_without_path_required')
    return origin


class Structure(HTMLParser):
    def __init__(self):
        super().__init__()
        self.styles = []
        self.links = []

    def handle_starttag(self, tag, attributes):
        attributes = dict(attributes)
        if 'style' in attributes:
            self.styles.append((tag, attributes['style']))
        if tag == 'a':
            self.links.append(attributes.get('href'))


def admin_branch(name, original, origin):
    text = original.decode('utf-8')
    title = 'Sign in to your account' if name == 'auth-magic_link.html' else 'Confirm your account'
    intro = ('Use the sign-in link or enter the one-time code in the application.'
             if name == 'auth-magic_link.html' else 'Confirm your email address to finish creating your account.')
    label = 'Sign in' if name == 'auth-magic_link.html' else 'Confirm email'
    old_link = '<p><a href="{{ .ConfirmationURL }}">' + label + '</a></p>'
    need(text.count(title) == 2 and text.count(intro) == 1 and text.count(old_link) == 1,
         'verified_original_structure_required')
    text = text.replace(title, 'Your Collect Admin sign-in code')
    text = text.replace(intro, 'Return to your original Collect Admin sign-in window and enter the one-time code below.')
    target = origin + '/#/admin/login'
    replacement = ('<p><a href="' + html.escape(target, quote=True) + '">Return to Collect Admin</a></p>\n'
                   '<p>This link opens the sign-in page; it does not sign you in. '
                   'Use your original sign-in window if it is already open.</p>')
    text = text.replace(old_link, replacement)
    before, after = Structure(), Structure()
    before.feed(original.decode('utf-8'))
    after.feed(text)
    need(before.styles == after.styles, 'existing_inline_styles_must_remain_exact')
    need(after.links == [target], 'only_non_consuming_Admin_return_link_required')
    need(text.count('{{ .Token }}') == 1 and '.ConfirmationURL' not in text
         and '.TokenHash' not in text and 'access_token' not in text and 'refresh_token' not in text,
         'Admin_code_without_verification_or_session_link_required')
    return text.encode()


def candidate(name, original, origin):
    need(name in PINS and sha(original) == PINS[name], 'live_original_hash_mismatch')
    admin = admin_branch(name, original, origin)
    # No whitespace is emitted outside the selected branch. The ELSE body is
    # the entire exact original byte sequence, including its final newline.
    opening = ('{{ if eq .RedirectTo ' + json.dumps(origin) + ' }}').encode()
    raw = opening + admin + b'{{ else }}' + original + b'{{ end }}'
    need(raw[len(opening) + len(admin) + len(b'{{ else }}'):-len(b'{{ end }}')] == original,
         'public_else_bytes_must_be_exact')
    return raw, {
        'original_sha256': PINS[name], 'candidate_sha256': sha(raw),
        'original_bytes': len(original), 'candidate_bytes': len(raw),
        'condition': 'exact eq .RedirectTo selected profile.admin_origin',
        'admin_origin': origin, 'non_consuming_return_url': origin + '/#/admin/login',
        'entire_public_else_branch_byte_identical': True,
        'existing_inline_styles_identical_in_Admin_branch': True,
        'Admin_code_retained_and_verification_link_absent': True,
        'actual_Go_template_render_verified': False,
        'actual_GoTrue_or_email_client_verified': False,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', type=Path, required=True)
    parser.add_argument('--profile-sha256', required=True)
    parser.add_argument('--output-directory', type=Path, required=True)
    args = parser.parse_args()
    value = json.loads(physical_file(args.profile))
    need(isinstance(value, dict), 'public_profile_object_required')
    profile = value.get('profile') if value.get('format') == 'collect.selfhost.release.v1' else value
    need(isinstance(profile, dict), 'selected_public_profile_required')
    origin = selected_origin(profile, args.profile_sha256)
    output = args.output_directory
    need(output.is_absolute() and output.parent.resolve(strict=True) == output.parent
         and not output.is_relative_to(HERE) and not output.exists(), 'fresh_external_candidate_required')
    parent = output.parent.lstat()
    need(stat.S_ISDIR(parent.st_mode) and parent.st_uid == os.getuid()
         and stat.S_IMODE(parent.st_mode) == 0o700, 'private_owned_output_parent_required')
    prepared = {}
    for name in PINS:
        prepared[name] = candidate(name, physical_file(HERE / 'email_templates' / name.removeprefix('auth-')), origin)
    output.mkdir(mode=0o700)
    sync(output.parent)
    for name, (raw, _) in prepared.items():
        write_new(output / name, raw)
    report = {
        'status': 'PREPARED_STATIC_BYTE_CHECKS_ONLY',
        'profile_sha256': args.profile_sha256,
        'templates': {name: item[1] for name, item in prepared.items()},
        'runtime_apply': False, 'Auth_requests': 0,
        'actual_Go_template_render_verified': False,
        'actual_GoTrue_or_email_client_verified': False,
    }
    write_new(output / 'static-byte-checks.json', (json.dumps(report, sort_keys=True, indent=2) + '\n').encode())
    print(json.dumps({'status': report['status'], 'candidate_directory': str(output),
                      'runtime_apply': False, 'actual_Go_template_render_verified': False}))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(json.dumps({'status': 'REFUSED', 'reason': str(error) if isinstance(error, ValueError) else 'template_preparation_failed',
                          'runtime_apply': False}))
        raise SystemExit(2)
