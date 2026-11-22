# Collect intentionally relies on the optimized Android defaults. App-owned
# classes reached only from AndroidManifest.xml entries are retained by R8's
# manifest analysis; Flutter plugin consumer rules cover the embedding and
# registered plugins. Add narrowly scoped rules here only when a verified
# reflection or JNI boundary requires them.
