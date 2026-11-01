# Verified Android build prerequisites — 2026-11-01

The missing local Android prerequisites are installed under the task-owned
`toolchains/android-bootstrap-20261101` directory. **This receipt establishes
tool availability and byte identity, not an application build or device test.**
The Mobile agent owns the subsequent Kotlin tests and unsigned QA artifact.

The machine's package database, application source, Gradle dependency locks,
signing configuration, Firebase configuration and provider settings were not
changed by this bootstrap.

## Installed versions and verification

| Component | Installed identity | Verification |
|---|---|---|
| OpenJDK/JRE | Ubuntu `17.0.20+8-1~24.04`, amd64 | Existing Ubuntu archive keyring verifies the retained `noble-updates` InRelease signature; its signed uncompressed Packages digest matches; exact JDK and JRE `.deb` sizes/SHA-256 values match. Both packages were extracted locally, without a global package installation. |
| Java compiler | `javac 17.0.20` | Actual compiler version invocation succeeds. |
| Android command-line tools | Revision 22.0, archive build 15859902 | Official Android Studio Linux archive SHA-256 independently checked before extraction. The exact archive hash is `4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583`. |
| Android platform | API 36, revision 2 | Official repository archive checksum and size independently verified; 11,342 installed payload files compared. |
| Android build tools | 36.0.0 | Official archive independently verified; 168 installed payload files compared. Actual `aapt2 version` reports `2.20-13193326`. |
| Platform tools | 37.0.1 | Official archive independently verified; 12 installed payload files compared. Actual ADB reports `37.0.1-15733141`. |
| NDK | 28.2.13676358, r28c | Official archive independently verified; 8,449 installed payload file/link identities compared. Actual Android clang reports 19.0.1. |

In total, **19,971 SDK payload files/link identities** were compared with the
independently downloaded official archives. Android's repository metadata uses
SHA-1 for those four archive checksums; the receipt also records independently
computed SHA-256 hashes of the exact retained archives. This distinction is
explicit. The command-line-tools archive and Ubuntu packages have independently
published SHA-256 identities.

The JDK uses the machine's existing operating-system libraries and certificate
trust. Package configuration links with an extracted target were redirected to
that package-owned target inside the local JDK extraction. No system CA or
global Java installation was changed.

## Build handoff

The complete path mapping is in
`toolchains/android-bootstrap-20261101/environment.json`. For this workspace:

```sh
export COLLECT_ANDROID_TOOLCHAIN=/workspace/scratch/2d330cc6dfd0/toolchains/android-bootstrap-20261101
export JAVA_HOME="$COLLECT_ANDROID_TOOLCHAIN/jdk-root/usr/lib/jvm/java-17-openjdk-amd64"
export ANDROID_HOME="$COLLECT_ANDROID_TOOLCHAIN/sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_USER_HOME="$COLLECT_ANDROID_TOOLCHAIN/android-user"
export GRADLE_USER_HOME="$COLLECT_ANDROID_TOOLCHAIN/gradle-user"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
```

The isolated Gradle user home contains this environment's ordinary HTTP/HTTPS
proxy settings. They contain no proxy credentials. The project configuration
was not edited to inject machine-specific networking. The existing project
wrapper remains authoritative for Gradle 9.1.0 and its pinned distribution hash.
No Gradle or Flutter application build was started by the bootstrap agent.

The ordinary SDK development licenses presented for the explicitly requested
free prerequisite packages were accepted within this isolated SDK. No account,
device registration, store upload, signing key or external provider was used.

## Actual readback correction

SDK Manager 22 reported all four packages installed, but file-level readback
found that `build-tools/36.0.0` contained its tools under an extra `android-16`
directory and an unrelated `android-ndk-r28c` subtree. The expected direct
`source.properties` and tool paths were absent. The bootstrap therefore did
not accept the manager's status message as proof of usable tools.

The failed build-tools tree was preserved outside the SDK. The normal package
directory was reconstructed from the independently checksum-verified official
build-tools archive; the manager's original package identity XML was retained.
All 168 payload files then matched the archive, and `aapt2` executed successfully.
The final verified SDK does not retain that mixed layout.

Two local harness corrections are also recorded. A `subprocess.run` input setup
error stopped before the first package installation. The first independent NDK
comparison mistakenly compared symlink payload text with the target file's
bytes; that comparison was corrected, the original NDK restored, and all 8,449
expected file/link identities verified. The temporary partial reconstruction
was removed only after retaining its full file/hash manifest, exact archive,
failed script and diagnostic note, recovering about 1.8 GB. The confirmed SDK
layout repair was confined to build-tools.

## Durable evidence and boundary

`android-toolchain-bootstrap.json` combines the signed Ubuntu chain, archive
identities, installed package/readback results, actual version outputs, script
and log hashes, environment paths and correction notes. Detailed download
scripts and logs remain in the task-owned toolchain directory. The subsequent
verified archive cleanup below preserves exact byte identities and official
URLs after removing reproducible download copies. The safe combined initial
receipt SHA-256 is:

`c28746026dcbc877c9b11b1015d877915f1d26ce8711c430d78199fc3a7f55d1`

This does not certify an APK, Kotlin test result, emulator, physical device,
release signing, Google Play delivery, notifications, SMS permission approval or
production behavior. Those require their own observed results.

Primary installation references:

- [Official Android Studio command-line-tools download and checksums](https://developer.android.com/studio).
- [Official SDK Manager package installation and explicit SDK-root options](https://developer.android.com/tools/sdkmanager).
- [Official Android repository metadata](https://dl.google.com/android/repository/repository2-3.xml).

## Retention source-gate follow-up

During bootstrap, the exhaustive source gate identified stale projections in
two retention test files. Their mock included all current private relations
but assigned generic column strings to the new SMS admission map, while still
expecting the earlier six shared classes and SQL14 private profile.

Only those two test fixtures and expectations were corrected. The current
fixture now provides the exact map signature and current private profile,
asserts the original six plus all thirteen additive shared classes, and keeps
explicit historical SQL11/14 private profiles. All original policy refusal,
scope-change, shared-copy blocking, current-account and recent-email checks
remain. A malformed map signature and missing stopped-admission dependency are
also rejected. **All ten targeted source cases passed**, with the source-bound
receipt and exact TAP in `retention-current25-source-fixtures.json` and
`retention-current25-source-fixtures.tap`. No runtime or migration was changed
to obtain that result. The Mobile agent owns the final exhaustive source gate.

## Subsequent space reclamation during the actual build

The active compilation later required additional disk space. Cleanup was
confined to explicitly identified, checksum-verified download copies in this
agent's toolchain directory. No installed SDK/JDK file, extracted Gradle
runtime, dependency/transform cache, application source, other toolchain,
repository or database cluster was removed.

| Recorded cleanup | Download bytes removed | Observed free space before | Observed free space after |
|---|---:|---:|---:|
| Seven verified official archives and three proved duplicate NDK prefixes | 2,385,830,174 | 3,050,598,400 | 5,423,239,168 |
| Verified Gradle 9.1.0-all distribution ZIP; extracted runtime retained | 232,491,070 | 429,379,584 | 744,079,360 |

The exact file identities, expected and observed checksums, open-handle checks
and removed paths are retained in `android-toolchain-archive-cleanup.json` and
`android-additional-archive-cleanup.json`. Critical installed-tool hashes were
identical before/after the first cleanup. The Gradle ZIP matched the project's
exact distribution checksum, had no observed open handle, and had an installed
Gradle runtime alongside it. Concurrent build writes and other process activity
affect the net free-space readings; these are observations at each cleanup,
not a promise of remaining capacity. Unique failed build-tools evidence and
unverified failed download evidence were preserved.

## Subsequent build-installed SDK additions

The actual Gradle build installed **API 34 revision 3** and **API 35 revision 2**
for pinned plugin subprojects after the initial four-package qualification.
Their installed package XML and source properties match the corresponding
current records in the retained official repository metadata. Obsolete API 34
revision 2 metadata is explicitly excluded.

The separate independent archive/payload verifier did not finish successfully
during the resource/service degradation. Its API 35 download contained
63,488,000 bytes against an expected 64,273,788, so it was refused and retained
as failed evidence. The supplemental receipt,
`android-sdk-build-additions.json`, records **metadata verified, independent
payload qualification incomplete**. It does not extend the original
four-package/19,971-file qualification to the complete later build toolchain.
No installed SDK or active build cache was changed by that verification, and
no duplicate download was started during the resource constraint. Application
build success remains a separate result owned by the Mobile build workflow.
