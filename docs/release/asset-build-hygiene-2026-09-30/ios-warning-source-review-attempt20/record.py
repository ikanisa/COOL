#!/usr/bin/env python3
"""Read-only source review of the preserved pre-gotrue iOS compile warnings."""
import hashlib
import json
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
BUILD = OUT.parent / "native-export-attempt18-ios"
EXPORT = Path("/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-attempt18-ios")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


facts = [
    ("retained_generated_annotation", "The generated mobile_scanner Swift bridge applies __unsafe_unretained to CVPixelBufferRef, and Clang reports the annotation ignored. Preserve the generated header; no app source or warning flag was changed. This is not a buffer-ownership runtime test."),
    ("retained_upstream_deprecated_api", "Firebase foreground notification presentation uses the deprecated Alert option when persisted alert=true. The actual SDK header retains the option and recommends List|Banner; provider/foreground delivery behavior is outside this compile evidence."),
    ("open_local_compatibility_correction", "The plugin implements the scene callback as void, but the compiled FlutterSceneLifeCycle protocol declares BOOL and documents YES if the connection was handled. Successful compilation does not establish a valid return contract. A bounded source correction and local callback regression remain required; no Firebase fork or SDK cache mutation was performed."),
    ("retained_unselected_app_capability", "file_saver Dialog uses UIApplication.keyWindow in native saveAs. Captured Collect runtime calls only FileSaver.saveFile; the plugin enters Dialog only for saveAs. Preserve the optional upstream implementation; this does not approve a future saveAs route."),
    ("retained_upstream_window_selection", "file_picker selects the key window from UIApplication.windows. The captured app disables multiple scenes. The deprecated window enumeration is retained; native picker interaction is not proven by compilation."),
    ("retained_generated_null_bridge", "Firebase sets the nullable deepLinkURLScheme property to NSNull. Its generated Pigeon serializer emits this property in an object list using the same null sentinel. The NSString declaration causes the pointer warning; no unsafe string operation on that value is shown by the reviewed bridge."),
    ("retained_unreachable_legacy_branch", "flutter_local_notifications selects List/Banner in its iOS14 availability branch and Alert only in the older branch. The captured app and Pod deployment minimum is15.5, so the warning refers to the retained legacy fallback."),
    ("retained_upstream_static_type_mismatch", "buildUserDict is declared NSDictionary but allocates and returns NSMutableDictionary. The warning occurs when assigning that mutable runtime object to a mutable variable before adding dismissIsolate. Source review explains the mismatch; no mutability cast or blanket suppression was introduced."),
    ("retained_unreachable_legacy_branch", "image_picker uses UTTypeGIF on iOS14+ and kUTTypeGIF in the older branch. Captured deployment minimum15.5 selects the modern branch."),
    ("retained_unreachable_legacy_branch", "image_picker photo-asset serialization uses UTTypeGIF on iOS14+ and the warned kUTTypeGIF only in its older branch. Captured deployment minimum15.5 selects the modern branch."),
    ("retained_upstream_deprecated_api", "The UIImagePicker image media-type list retains kUTTypeImage. This remains a typed compatibility identifier in the pinned plugin, rather than an app-source warning. Actual picker behavior is separate from compilation."),
    ("retained_upstream_deprecated_api", "The UIImagePicker video media-type list retains kUTTypeMovie. The optional video path is compiled, and its supported runtime use is not established by this warning review."),
    ("retained_upstream_fallback", "mobile_scanner uses AVCaptureDevice.devices(for:) after modern DiscoverySession candidates fail. The source comment calls it legacy, but the fallback can still be reached on newer iOS when discovery returns no device. Do not label it unreachable or claim camera acceptance."),
    ("retained_unused_binding", "The bound device value is unused after the object cast gates the zoom-event path. The retained binding preserves that conditional type check; this is not an app runtime or compiler error."),
    ("retained_deployment_bounded_availability", "permission_handler combines @available(iOS12,*) with the provisional authorization check, which Clang does not treat as an availability guard. The captured minimum15.5 already makes the referenced status available. Original source and warning are preserved."),
    ("retained_unreachable_legacy_branch", "permission_handler uses serviceSubscriberCellularProviders on iOS12+ and subscriberCellularProvider only below12. Captured deployment minimum15.5 does not select the warned branch."),
    ("retained_unreachable_legacy_branch", "share_plus uses connected UIWindowScene windows on iOS13+ and keyWindow only below13. Captured deployment minimum15.5 does not select the warned branch."),
    ("retained_tool_capability_notice", "Xcode skipped AppIntents extraction because the app declares no AppIntents framework dependency. No AppIntents capability is claimed by Collect's compile evidence."),
    ("retained_tool_environment_notice", "The Flutter/native-asset tool did not recognize SWIFT_DEBUG_INFORMATION_FORMAT inherited by the build phase. The generic-device release compile and artifact inspection passed; no SDK/tool environment was rewritten to hide this output."),
    ("retained_tool_environment_notice", "The Flutter/native-asset tool did not recognize SWIFT_DEBUG_INFORMATION_VERSION inherited by the build phase. The exact diagnostic remains retained; no warning suppression was added."),
]
inventory = json.loads((BUILD / "compiler-warning-inventory.json").read_text())
assert len(inventory["messages"]) == 24
(OUT / "source-snapshot").mkdir()
rows, hashes = [], {}
for index, message in enumerate(inventory["messages"][:20], 1):
    disposition, rationale = facts[index - 1]
    row = {"id": index, "message": message, "disposition": disposition, "source_rationale": rationale,
           "runtime_acceptance_claimed": False, "warning_suppressed": False}
    match = re.match(r"(.+?):(\d+):\d+: warning:", message)
    if match:
        source, line = Path(match[1]), int(match[2])
        target = OUT / "source-snapshot" / f"{index:02d}-{source.name}"
        shutil.copy2(source, target)
        assert sha(source) == sha(target)
        text = source.read_text().splitlines()
        row.update({"source": str(source), "source_sha256": sha(source), "line": line,
                    "preserved_source": str(target.relative_to(ROOT)),
                    "source_excerpt": [{"line": n + 1, "text": text[n]} for n in range(max(0, line - 5), min(len(text), line + 5))]})
        hashes[str(target.relative_to(ROOT))] = sha(target)
    rows.append(row)
for index, original in enumerate([4, 5, 13, 14], 21):
    rows.append({"id": index, "message": inventory["messages"][index - 1],
                 "disposition": "duplicate_swift_diagnostic_rendering", "duplicates_primary_id": original,
                 "warning_suppressed": False, "runtime_acceptance_claimed": False})
extra = {"FlutterSceneLifeCycle.h": EXPORT / "build/ios/DerivedData/Build/Products/Release-production-iphoneos/Flutter.framework/Headers/FlutterSceneLifeCycle.h",
         "captured-Podfile": EXPORT / "ios/Podfile", "captured-Info.plist": EXPORT / "ios/Runner/Info.plist",
         "captured-share_screen.dart": EXPORT / "lib/features/collections/share_screen.dart",
         "captured-FileSaverPlugin.swift": EXPORT / "third_party/file_saver/ios/file_saver/Sources/file_saver/FileSaverPlugin.swift"}
for name, source in extra.items():
    target = OUT / "source-snapshot" / name
    shutil.copy2(source, target)
    assert sha(source) == sha(target)
    hashes[str(target.relative_to(ROOT))] = sha(target)
value = {"kind": "individual_source_review_of_dated_ios_compiler_warnings", "status": "open_compatibility_item",
         "raw_unique_warning_strings": 24, "primary_diagnostics": 20, "duplicate_renderings": 4,
         "open_local_compatibility_ids": [3], "source_build": "native-export-attempt18-ios",
         "source_build_runtime_current": False, "source_review_only": True, "flutter_build_invoked": False,
         "blanket_warning_suppression": False, "native_runtime_or_release_accepted": False,
         "compiler_warning_inventory_sha256": sha(BUILD / "compiler-warning-inventory.json"),
         "preserved_build_stdout_sha256": sha(BUILD / "unsigned-ios-build.stdout"),
         "preserved_sources": hashes, "rows": rows, "recorder_sha256": sha(Path(__file__))}
(OUT / "review.json").write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
print(json.dumps({"primary": 20, "duplicate": 4, "open_ids": [3], "review_sha256": sha(OUT / "review.json")}))
