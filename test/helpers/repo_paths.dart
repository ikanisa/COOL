import 'dart:io';

Directory repoRoot() {
  var dir = Directory.current;
  while (true) {
    final hasRepoApps = Directory('${dir.path}/apps/admin').existsSync();
    final hasSupabase = Directory(
      '${dir.path}/supabase/migrations',
    ).existsSync();
    if (hasRepoApps && hasSupabase) {
      return dir;
    }

    final parent = dir.parent;
    if (parent.path == dir.path) {
      return Directory.current;
    }
    dir = parent;
  }
}

File repoFile(String relativePath) => File('${repoRoot().path}/$relativePath');

Directory repoDir(String relativePath) =>
    Directory('${repoRoot().path}/$relativePath');
