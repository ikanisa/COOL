#!/usr/bin/env python3
"""Bind the Cloudflare Admin artifact to actual working inputs, including new files."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from urllib.parse import unquote, urlsplit

SOURCE_DIRS = ('lib', 'assets', 'web', 'deploy/admin-api/src', 'deploy/admin-api/migrations')
SOURCE_FILES = (
    'pubspec.yaml', 'pubspec.lock', '.fvmrc', 'deploy/admin.cloudflare.wrangler.jsonc',
    'deploy/admin-api/package.json', 'deploy/admin-api/package-lock.json',
    'scripts/admin_cloudflare_build.sh', 'scripts/admin_cloudflare_source.py',
    'scripts/admin_cloudflare_assets.py', 'scripts/admin_pwa_hosting_gate.sh',
    'scripts/admin_cloudflare_artifact.py', 'scripts/admin_cloudflare_preflight.py',
    'scripts/templates/admin_cloudflare_retirement_worker.js',
    'scripts/admin_cloudflare_shell.py', 'scripts/templates/admin_cloudflare_shell_worker.js',
    '.github/workflows/ci.yml',
)
IGNORED_DIRS = {'.git', '.dart_tool', '.fvm', 'build', 'node_modules', '__pycache__', '.pytest_cache'}
MAX_MANIFEST_BYTES = 64 * 1024 * 1024
SHA256 = re.compile(r'[0-9a-f]{64}\Z')
COMMIT = re.compile(r'(?:[0-9a-f]{40}|[0-9a-f]{64})\Z')


class SourceError(ValueError):
    pass


def canonical(value):
    return json.dumps(value, separators=(',', ':'), sort_keys=True, ensure_ascii=True).encode()


def relative_path(value):
    if not isinstance(value, str) or not value:
        raise SourceError('Manifest file paths must be nonempty strings')
    for candidate in (value, unquote(value)):
        if candidate.startswith('/') or '\\' in candidate or ':' in candidate or any(
            part in ('', '.', '..') for part in candidate.split('/')
        ) or any(ord(character) < 32 or ord(character) == 127 for character in candidate):
            raise SourceError('Manifest file path is unsafe')
    try:
        value.encode('utf-8', errors='strict')
    except UnicodeError as error:
        raise SourceError('Manifest file path is not valid Unicode') from error
    return value


def physical_path(path, *, directory=False, allow_missing=False):
    path = Path(os.path.abspath(Path(path).expanduser()))
    for component in (*reversed(path.parents), path):
        if component.is_symlink():
            raise SourceError(f'Physical input path contains a symlink: {component.name}')
    if allow_missing and not path.exists():
        return path
    try:
        information = path.lstat()
    except OSError as error:
        raise SourceError(f'Required physical input is unavailable: {path.name}') from error
    if directory:
        valid = stat.S_ISDIR(information.st_mode)
    else:
        valid = stat.S_ISREG(information.st_mode) and information.st_nlink == 1
    if not valid:
        raise SourceError(f'Input must be a physical regular {"directory" if directory else "file"}: {path.name}')
    return path


def parse_json(data):
    if not data or len(data) > MAX_MANIFEST_BYTES:
        raise SourceError('JSON manifest is too large')

    def unique(pairs):
        value = {}
        for key, item in pairs:
            if key in value:
                raise SourceError('JSON manifest contains duplicate keys')
            value[key] = item
        return value

    def invalid_number(value):
        raise SourceError('JSON manifest contains an invalid number')

    try:
        return json.loads(data.decode('utf-8'), object_pairs_hook=unique, parse_constant=invalid_number)
    except SourceError:
        raise
    except (ValueError, UnicodeError, RecursionError) as error:
        raise SourceError('JSON manifest is malformed') from error


def read_json(path):
    path = physical_path(path)
    if path.stat().st_size > MAX_MANIFEST_BYTES:
        raise SourceError('JSON manifest is too large')
    return parse_json(path.read_bytes())


def write_json(path, value):
    path = Path(path)
    if '..' in path.parts:
        raise SourceError('Manifest output must not contain parent traversal')
    physical_path(path, allow_missing=True)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(prefix='.admin-manifest-', dir=path.parent, delete=False) as output:
            temporary = Path(output.name)
            output.write((json.dumps(value, indent=2, ensure_ascii=True) + '\n').encode())
            output.flush()
            os.fsync(output.fileno())
        physical_path(path, allow_missing=True)
        os.replace(temporary, path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def source_files(folder):
    folder = physical_path(folder, directory=True)

    def on_error(error):
        raise SourceError('Cannot inspect the complete physical source tree') from error

    for parent, directories, names in os.walk(folder, followlinks=False, onerror=on_error):
        directories[:] = [name for name in directories if name not in IGNORED_DIRS]
        for name in directories:
            physical_path(Path(parent) / name, directory=True)
        for name in names:
            if name.startswith('._') or name == '.DS_Store':
                continue
            yield physical_path(Path(parent) / name)


def read_pubspec(path):
    path = physical_path(path)
    ruby = shutil.which('ruby')
    if not ruby:
        raise SourceError('Ruby/Psych is required to safely read declared path dependencies')
    # Use the same already-required safe YAML runtime as repository CI gates.
    # Inspect the parse tree too: YAML.safe_load alone silently keeps the last
    # duplicate key, which is not an unambiguous compiler input declaration.
    script = '''require 'yaml'; require 'json'
def inspect_keys(node)
  if node.is_a?(Psych::Nodes::Mapping)
    keys = node.children.each_slice(2).map do |key, value|
      raise 'complex key' unless key.is_a?(Psych::Nodes::Scalar)
      [key.tag, key.value]
    end
    raise 'duplicate key' unless keys.uniq.length == keys.length
  end
  (node.children || []).each { |child| inspect_keys(child) }
end
text = STDIN.read
inspect_keys(YAML.parse(text))
value = YAML.safe_load(text, permitted_classes: [], permitted_symbols: [], aliases: false)
raise 'shape' unless value.is_a?(Hash)
STDOUT.write(JSON.generate(value))
'''
    try:
        result = subprocess.run([ruby, '-e', script], input=path.read_text(encoding='utf-8'),
                                text=True, capture_output=True, timeout=15, check=False)
        if result.returncode:
            raise SourceError(f'Declared package pubspec is malformed: {path.name}')
        value = json.loads(result.stdout)
        if not isinstance(value, dict):
            raise SourceError('Declared package pubspec must contain a map')
        return value
    except (OSError, UnicodeError, subprocess.TimeoutExpired, ValueError) as error:
        if isinstance(error, SourceError):
            raise
        raise SourceError('Cannot safely read declared package pubspec') from error


def declared_path_dependencies(root, *, check_resolution=True):
    root = physical_path(root, directory=True)
    pubspec = read_pubspec(root / 'pubspec.yaml')
    overrides = pubspec.get('dependency_overrides', {})
    if not isinstance(overrides, dict):
        raise SourceError('dependency_overrides must contain a map')
    resolved = {}
    pending = [(root, pubspec, True)]
    while pending:
        owner, specification, is_root = pending.pop(0)
        sections = ('dependencies', 'dev_dependencies') if is_root else ('dependencies',)
        declarations = {}
        for section in sections:
            section_value = specification.get(section, {})
            if not isinstance(section_value, dict):
                raise SourceError('Dependency declarations must contain maps')
            declarations.update(section_value)
        if is_root:
            declarations.update(overrides)
        for name, declaration in declarations.items():
            if name in overrides:
                declaration = overrides[name]
                owner_path = root
            else:
                owner_path = owner
            if not isinstance(declaration, dict) or 'path' not in declaration:
                continue
            if not isinstance(name, str) or not re.fullmatch(r'[a-z][a-z0-9_]*', name):
                raise SourceError('Declared path package name is invalid')
            relative = relative_path(declaration['path'])
            folder = physical_path(owner_path / relative, directory=True)
            if not folder.is_relative_to(root) or folder == root:
                raise SourceError('Declared path package escapes the working source root')
            if name in resolved:
                if resolved[name] != folder:
                    raise SourceError('Path dependency has conflicting physical declarations')
                continue
            package = read_pubspec(folder / 'pubspec.yaml')
            if package.get('name') != name:
                raise SourceError('Path dependency package name differs from its declaration')
            physical_path(folder / 'lib', directory=True)
            resolved[name] = folder
            pending.append((folder, package, False))
    if check_resolution:
        config_path = root / '.dart_tool/package_config.json'
        config = read_json(config_path)
        if not isinstance(config, dict) or config.get('configVersion') != 2 or not isinstance(config.get('packages'), list):
            raise SourceError('Actual compiler package configuration is missing or malformed')
        packages = {}
        for package in config['packages']:
            if not isinstance(package, dict) or not isinstance(package.get('name'), str) or package['name'] in packages:
                raise SourceError('Actual compiler package configuration contains invalid or duplicate packages')
            packages[package['name']] = package
        for name, folder in resolved.items():
            package = packages.get(name)
            if not package or package.get('packageUri') != 'lib/' or not isinstance(package.get('rootUri'), str):
                raise SourceError(f'Actual compiler resolution is missing the declared local package: {name}')
            uri = urlsplit(package['rootUri'])
            if uri.scheme not in ('', 'file') or uri.netloc or uri.query or uri.fragment or '\\' in unquote(uri.path):
                raise SourceError('Actual local package resolution URI is unsafe')
            path = Path(unquote(uri.path))
            actual = path if path.is_absolute() else config_path.parent / path
            actual = physical_path(actual, directory=True)
            if actual != folder:
                raise SourceError(f'Actual compiler resolution differs from the declared local package: {name}')
    return resolved


def inputs(root, *, check_resolution=True, dependency_roots=None):
    root = physical_path(root, directory=True)
    paths = set()
    for directory in SOURCE_DIRS:
        paths.update(source_files(root / directory))
    folders = dependency_roots if dependency_roots is not None else declared_path_dependencies(root, check_resolution=check_resolution).values()
    for folder in folders:
        paths.update(source_files(folder))
    for name in SOURCE_FILES:
        paths.add(physical_path(root / name))
    rows = []
    for path in sorted(paths, key=lambda path: path.relative_to(root).as_posix()):
        rows.append({'path': path.relative_to(root).as_posix(), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    digest = hashlib.sha256(canonical(rows)).hexdigest()
    return {'files': rows, 'source_manifest_sha256': digest}


def validate_source_manifest(value):
    if not isinstance(value, dict) or set(value) != {'files', 'source_manifest_sha256', 'source_commit', 'source_dirty'}:
        raise SourceError('Stored Admin source manifest shape is invalid')
    if not isinstance(value['source_commit'], str) or not COMMIT.fullmatch(value['source_commit']) or type(value['source_dirty']) is not bool:
        raise SourceError('Stored Admin source identity is invalid')
    rows = value['files']
    if not isinstance(rows, list) or not rows:
        raise SourceError('Stored Admin source file inventory is empty or invalid')
    prior = None
    for row in rows:
        if not isinstance(row, dict) or set(row) != {'path', 'sha256'}:
            raise SourceError('Stored Admin source file record is invalid')
        path = relative_path(row['path'])
        if prior is not None and path <= prior:
            raise SourceError('Stored Admin source files must be sorted and unique')
        prior = path
        if not isinstance(row['sha256'], str) or not SHA256.fullmatch(row['sha256']):
            raise SourceError('Stored Admin source file hash is invalid')
    digest = hashlib.sha256(canonical(rows)).hexdigest()
    if value['source_manifest_sha256'] != digest:
        raise SourceError('Stored Admin source file-list digest is invalid')
    return value


def verify_source_manifest(root, manifest_path, *, check_resolution=True):
    recorded = validate_source_manifest(read_json(manifest_path))
    dependency_roots = None
    if not check_resolution:
        # Preflight can verify an already-built artifact without installing a
        # compiler or running YAML tools. Every local package's own pubspec was
        # captured by record; take the topmost such roots outside known source
        # trees and inspect their full inventories, including newly added files.
        # A changed declaration still changes the frozen root pubspec bytes.
        root = physical_path(root, directory=True)
        known_dirs = [root / directory for directory in SOURCE_DIRS]
        known_files = {root / name for name in SOURCE_FILES}
        outside = [root / row['path'] for row in recorded['files']
                   if root / row['path'] not in known_files and not any(
                       (root / row['path']).is_relative_to(directory) for directory in known_dirs)]
        candidates = sorted({path.parent for path in outside if path.name == 'pubspec.yaml'}, key=lambda path: (len(path.parts), str(path)))
        dependency_roots = []
        for candidate in candidates:
            if not any(candidate.is_relative_to(folder) for folder in dependency_roots):
                dependency_roots.append(candidate)
        if any(not any(path.is_relative_to(folder) for folder in dependency_roots) for path in outside):
            raise SourceError('Frozen Admin source contains inputs outside its physical closure')
    current = inputs(root, check_resolution=check_resolution, dependency_roots=dependency_roots)
    if current != {key: recorded[key] for key in current}:
        raise SourceError('Admin inputs changed during or after the build. Do not release this artifact.')
    return recorded


def record_source_manifest(root, manifest_path):
    root = physical_path(root, directory=True)
    current = inputs(root)
    current['source_commit'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    current['source_dirty'] = bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=root))
    validate_source_manifest(current)
    write_json(manifest_path, current)
    return current


def main(argv=None, *, root=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['record', 'verify'])
    parser.add_argument('manifest', type=Path)
    args = parser.parse_args(argv)
    root = Path(root) if root is not None else Path(__file__).resolve().parents[1]
    try:
        if args.mode == 'verify':
            verify_source_manifest(root, args.manifest)
            print('Admin artifact inputs match the frozen working-source manifest.')
        else:
            record_source_manifest(root, args.manifest)
    except (SourceError, OSError, subprocess.SubprocessError) as error:
        print(f'Admin source identity refused: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
