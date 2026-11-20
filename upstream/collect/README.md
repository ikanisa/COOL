# Pinned Collect receiver sources

Exact original source from `ikanisa/COOL` commit `497de00bb16c86c797ebaad0f938dfd5efb42541`, fetched through the authenticated GitHub connector. All 17 Git blobs match `native/burimunsi/integration/receiver-sources.json` in the package root. No credentials, repository history, binary fonts or device data are included.

These files are extraction INPUTS, outside Gradle's compiled source sets. Do not add this tree directly as a Kotlin source directory. The build script extracts the approved receiver subset and only three queue-disposition methods from `MemberSmsJobs.kt`; its member scheduler/authentication/uploader are not emitted. See `docs/11_Receiver_Source_Closure.md`. This is not the complete Collect checkout and does not establish deployed parity.
