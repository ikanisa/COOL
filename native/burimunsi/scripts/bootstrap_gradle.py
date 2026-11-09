#!/usr/bin/env python3
"""Pinned Gradle bootstrap, no automatic download and no redistributed wrapper JAR.
Default requires a local archive. --download explicitly permits the official download.
Every use verifies the archive AND installed files before executing any Gradle code.
"""
import argparse,hashlib,json,os,pathlib,shutil,stat,subprocess,sys,tempfile,urllib.request,zipfile
VERSION='9.1.0'
SHA256='a17ddd85a26b6a7f5ddb71ff8b05fc5104c0202c6e64782429790c933686c806'
URL=f'https://services.gradle.org/distributions/gradle-{VERSION}-bin.zip'
CHECKSUM_SOURCE='https://gradle.org/release-checksums/'
LIMIT=200_000_000
class BootstrapError(ValueError):pass

def digest(path):
 h=hashlib.sha256()
 with path.open('rb') as f:
  for chunk in iter(lambda:f.read(1024*1024),b''):h.update(chunk)
 return h.hexdigest()

def checked_entries(archive,expected=SHA256,version=VERSION):
 if archive.is_symlink() or not archive.is_file():raise BootstrapError('Pinned Gradle archive absent. Run with --download, or supply --archive from a trusted download.')
 if archive.stat().st_size>LIMIT or digest(archive)!=expected:raise BootstrapError('Gradle archive checksum mismatch; nothing was executed.')
 prefix=f'gradle-{version}'
 with zipfile.ZipFile(archive) as z:
  entries=z.infolist();seen=set();size=0
  for row in entries:
   p=pathlib.PurePosixPath(row.filename);size+=row.file_size
   if not p.parts or p.is_absolute() or '..' in p.parts or '\\' in row.filename or p.parts[0]!=prefix or row.filename in seen:
    raise BootstrapError('Unsafe or duplicate archive path.')
   if stat.S_ISLNK(row.external_attr>>16):raise BootstrapError('Archive links are forbidden.')
   if size>1_000_000_000:raise BootstrapError('Archive expands beyond allowed size.')
   seen.add(row.filename)
  if f'{prefix}/bin/gradle' not in seen:raise BootstrapError('Gradle launcher absent.')
 return entries

def verify_tree(archive,root,entries):
 expected=set()
 with zipfile.ZipFile(archive) as z:
  for row in entries:
   target=root/pathlib.PurePosixPath(row.filename)
   if any(p.is_symlink() for p in (target,*target.parents) if p!=root.parent):raise BootstrapError('Installed Gradle contains a link.')
   if row.is_dir():continue
   expected.add(target.relative_to(root).as_posix())
   if not target.is_file() or target.stat().st_size!=row.file_size or digest(target)!=hashlib.sha256(z.read(row)).hexdigest():
    raise BootstrapError('Installed Gradle differs from the verified archive. Remove the installation directory before retrying.')
  installed=root/entries[0].filename.split('/')[0]
  for p in installed.rglob('*'):
   if p.is_file() and p.relative_to(root).as_posix() not in expected:raise BootstrapError('Unexpected file in Gradle installation.')

def install(archive,cache,expected=SHA256,version=VERSION):
 cache=cache.absolute();archive=archive.absolute()
 if any(p.is_symlink() for p in (cache,*cache.parents)):raise BootstrapError('Cache links are forbidden.')
 entries=checked_entries(archive,expected,version);target=cache/f'gradle-{version}'
 cache.mkdir(parents=True,exist_ok=True)
 if not target.exists():
  with tempfile.TemporaryDirectory(prefix='.gradle-unpack-',dir=cache) as staging:
   stage=pathlib.Path(staging)
   with zipfile.ZipFile(archive) as z:
    for row in entries:
     p=stage/row.filename
     if row.is_dir():p.mkdir(parents=True,exist_ok=True);continue
     p.parent.mkdir(parents=True,exist_ok=True)
     with z.open(row) as src,p.open('xb') as dst:shutil.copyfileobj(src,dst)
     p.chmod(0o755 if row.external_attr>>16&0o111 else 0o644)
   verify_tree(archive,stage,entries)
   # A concurrent installer may have won; verify its tree instead of overwriting it.
   try:os.rename(stage/f'gradle-{version}',target)
   except OSError:
    if not target.exists():raise
 verify_tree(archive,cache,entries)
 return target/'bin/gradle'

def download(destination):
 destination.parent.mkdir(parents=True,exist_ok=True)
 fd,tmp=tempfile.mkstemp(prefix='.gradle-download-',dir=destination.parent)
 try:
  with os.fdopen(fd,'wb') as out,urllib.request.urlopen(URL,timeout=45) as response:
   if not response.url.startswith('https://'):raise BootstrapError('Insecure download redirect.')
   total=0
   while True:
    chunk=response.read(1024*1024)
    if not chunk:break
    total+=len(chunk)
    if total>LIMIT:raise BootstrapError('Distribution download too large.')
    out.write(chunk)
  checked_entries(pathlib.Path(tmp));os.replace(tmp,destination)
 finally:
  if os.path.exists(tmp):os.unlink(tmp)

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--archive',type=pathlib.Path);p.add_argument('--cache',type=pathlib.Path,default=pathlib.Path(os.environ.get('BURI_GRADLE_CACHE',str(pathlib.Path.home()/'.cache/burimunsi/gradle'))));p.add_argument('--download',action='store_true');p.add_argument('--run',action='store_true');p.add_argument('args',nargs=argparse.REMAINDER);a=p.parse_args()
 archive=a.archive or pathlib.Path(os.environ.get('BURI_GRADLE_ARCHIVE',str(a.cache/f'gradle-{VERSION}-bin.zip')))
 if a.download and not archive.exists():download(archive)
 launcher=install(archive,a.cache)
 if a.run:
  args=a.args[1:] if a.args[:1]==['--'] else a.args
  project=pathlib.Path(__file__).resolve().parents[1]
  return subprocess.run([str(launcher),'-p',str(project),*args]).returncode
 print(json.dumps({'verified':True,'version':VERSION,'archive_sha256':SHA256,'launcher':str(launcher),'executed':False}));return 0
if __name__=='__main__':
 try:sys.exit(main())
 except (OSError,ValueError,zipfile.BadZipFile) as e:print(json.dumps({'verified':False,'error':str(e),'executed':False}),file=sys.stderr);sys.exit(2)
