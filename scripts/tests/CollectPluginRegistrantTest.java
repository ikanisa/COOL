import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;

/** Actual adapter mutation controls, using the pinned tool-generated input. */
public final class CollectPluginRegistrantTest {
    private static int checks;

    private static void check(boolean condition, String name) {
        if (!condition) throw new AssertionError(name);
        checks++;
    }

    private static void rejects(String source, boolean omit, String name) {
        try {
            CollectPluginRegistrant.render(source, omit);
            throw new AssertionError(name);
        } catch (IllegalArgumentException expected) {
            checks++;
        }
    }

    private static void rejectsDirectory(Path path, String name) throws Exception {
        try {
            CollectPluginRegistrant.validateDirectory(path);
            throw new AssertionError(name);
        } catch (IllegalArgumentException expected) {
            checks++;
        }
    }

    private static byte[] metadata() {
        return ByteBuffer.allocate(90).putInt(0x00051607).putInt(0x00020000)
            .put("Mac OS X        ".getBytes(StandardCharsets.US_ASCII)).putShort((short) 2)
            .putInt(9).putInt(50).putInt(32).putInt(2).putInt(82).putInt(8)
            .put(new byte[32]).put("metadata".getBytes(StandardCharsets.US_ASCII)).array();
    }

    public static void main(String[] args) throws Exception {
        Path input = Path.of(args[0]);
        String original = Files.readString(input);
        String gateway = CollectPluginRegistrant.render(original, true);
        String normal = CollectPluginRegistrant.render(original, false);
        check(normal.equals(original), "Other flavor preserves every input byte");
        check(!gateway.contains("flutter_local_notifications"), "Gateway omits notification name");
        check(!gateway.contains("FlutterLocalNotificationsPlugin"), "Gateway omits notification class");
        check(!gateway.contains("firebase_messaging"), "Gateway omits Firebase messaging name");
        check(!gateway.contains("FlutterFirebaseMessagingPlugin"), "Gateway omits Firebase messaging class");
        check(gateway.contains("SharePlusPlugin"), "Other plugin registration retained");
        check(gateway.contains("FlutterFirebaseCorePlugin"), "Firebase registration retained");
        String notificationBlock = original.substring(
            original.lastIndexOf("    try {", original.indexOf("new com.dexterous.flutterlocalnotifications")),
            original.indexOf("    }\n", original.indexOf("Error registering plugin flutter_local_notifications")) + 6);
        String messagingBlock = original.substring(
            original.lastIndexOf("    try {", original.indexOf("new io.flutter.plugins.firebase.messaging")),
            original.indexOf("    }\n", original.indexOf("Error registering plugin firebase_messaging")) + 6);
        check(gateway.equals(original.replace(notificationBlock, "").replace(messagingBlock, "")), "Only two exact notification blocks removed");
        rejects(original.replace("@Keep", "@Deprecated"), true, "Envelope drift rejected");
        rejects(original.replace("catch (Exception e)", "catch (Throwable e)"), true, "Block drift rejected");
        rejects(original.replace(notificationBlock, ""), true, "Missing target rejected");
        rejects(original.replace(notificationBlock, notificationBlock + notificationBlock), true, "Duplicate target rejected");
        rejects(original.replace("plugin flutter_local_notifications,", "plugin renamed_notifications,"), true, "Renamed target rejected");
        rejects(original.replace("new com.dexterous.flutterlocalnotifications.FlutterLocalNotificationsPlugin()", "new com.unknown.Notifications()"), true, "Changed target class rejected");
        rejects(original.replace(messagingBlock, ""), true, "Missing Firebase messaging target rejected");
        rejects(original.replace(messagingBlock, messagingBlock + messagingBlock), true, "Duplicate Firebase messaging rejected");
        rejects(original.replace("plugin firebase_messaging,", "plugin renamed_messaging,"), true, "Renamed Firebase messaging rejected");
        rejects(original.replace("new io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingPlugin()", "new com.unknown.Messaging()"), true, "Changed Firebase messaging class rejected");
        rejects(original.replace("  }\n}\n", "    unexpected();\n  }\n}\n"), true, "Unknown tail rejected");
        rejects(original.replace("\n", "\r\n"), true, "Unknown line ending rejected");
        rejects(original.replace("    try {", "    /* mutation */ try {"), false, "Other variants also validate template");
        Path temporary = Files.createTempDirectory("collect-registrant-test");
        try {
            Path output = temporary.resolve("io/flutter/plugins/GeneratedPluginRegistrant.java");
            CollectPluginRegistrant.main(new String[]{input.toString(), output.toString(), "true"});
            check(Files.readString(output).equals(gateway), "Actual CLI writes filtered source");
            check(Files.readString(input).equals(original), "Actual CLI leaves tool input intact");
            CollectPluginRegistrant.main(new String[]{input.toString(), output.toString(), "false"});
            check(java.util.Arrays.equals(Files.readAllBytes(input), Files.readAllBytes(output)), "Actual other-flavor output byte-identical");

            Path directory = temporary.resolve("main-java");
            Path generated = directory.resolve("io/flutter/plugins/GeneratedPluginRegistrant.java");
            Files.createDirectories(generated.getParent());
            Files.write(generated, Files.readAllBytes(input));
            Path[] sidecars = {
                directory.resolve("._io"), directory.resolve("io/._flutter"),
                directory.resolve("io/flutter/._plugins"), generated.resolveSibling("._GeneratedPluginRegistrant.java"),
            };
            for (Path path : sidecars) Files.write(path, metadata());
            check(CollectPluginRegistrant.validateDirectory(directory).equals(generated), "Verified file and directory AppleDouble sidecars are admitted");
            CollectPluginRegistrant.main(new String[]{"--check-directory", directory.toString()});
            checks++;
            CollectPluginRegistrant.main(new String[]{generated.toString(), output.toString(), "true"});
            check(Files.readString(output).equals(gateway), "Generator validates the same metadata-bearing input directory");
            check(Files.readString(generated).equals(original), "Metadata-aware generation preserves original source bytes");
            for (Path path : sidecars)
                check(java.util.Arrays.equals(Files.readAllBytes(path), metadata()), "Metadata bytes remain untouched");

            Path extra = directory.resolve("Unexpected.java");
            Files.writeString(extra, "class Unexpected {}\n");
            rejectsDirectory(directory, "An extra Java source is still rejected");
            byte[] before = Files.readAllBytes(output);
            try {
                CollectPluginRegistrant.main(new String[]{generated.toString(), output.toString(), "true"});
                throw new AssertionError("Generator must reject extra source before writing");
            } catch (IllegalArgumentException expected) {
                checks++;
            }
            check(java.util.Arrays.equals(before, Files.readAllBytes(output)), "Rejected generation preserves previous output");
            Files.delete(extra);
            Path orphan = directory.resolve("._orphan.java");
            Files.write(orphan, metadata());
            rejectsDirectory(directory, "Structurally valid metadata without a companion is rejected");
            Files.delete(orphan);
            Path sidecar = sidecars[3];
            Files.writeString(sidecar, "class HiddenSource {}\n");
            rejectsDirectory(directory, "AppleDouble-looking name cannot hide source text");
            for (String mutation : new String[]{"magic", "version", "header", "duplicate", "overlap", "truncated", "bounds"}) {
                byte[] malformed = metadata();
                ByteBuffer bytes = ByteBuffer.wrap(malformed);
                switch (mutation) {
                    case "magic" -> bytes.putInt(0, 0x00051600);
                    case "version" -> bytes.putInt(4, 0x00010000);
                    case "header" -> bytes.putInt(30, 0);
                    case "duplicate" -> bytes.putInt(38, 9);
                    case "overlap" -> bytes.putInt(42, 51);
                    case "bounds" -> bytes.putInt(46, 1000);
                    case "truncated" -> malformed = java.util.Arrays.copyOf(malformed, 40);
                }
                Files.write(sidecar, malformed);
                rejectsDirectory(directory, "Malformed metadata rejected: " + mutation);
            }
            Files.write(sidecar, metadata());
            Path alias = temporary.resolve("aliased-java");
            Files.createSymbolicLink(alias, directory);
            rejectsDirectory(alias, "Symlink main/java root rejected");
            Files.delete(alias);
            alias = directory.resolve("aliased-package");
            Files.createSymbolicLink(alias, generated.getParent());
            rejectsDirectory(directory, "Symlink package directory rejected");
            Files.delete(alias);
            alias = directory.resolve("aliased.java");
            Files.createSymbolicLink(alias, generated);
            rejectsDirectory(directory, "Additional symlink file rejected");
            Files.delete(alias);
            Files.delete(sidecar);
            Files.createSymbolicLink(sidecar, sidecars[0]);
            rejectsDirectory(directory, "Metadata symlink cannot receive exemption");
            Files.delete(sidecar);
            Files.write(sidecar, metadata());
            Files.delete(generated);
            Files.createSymbolicLink(generated, input.toAbsolutePath());
            rejectsDirectory(directory, "Generated registrant symlink rejected");
            Files.delete(generated);
            Files.write(generated, Files.readAllBytes(input));
            check(CollectPluginRegistrant.validateDirectory(directory).equals(generated), "Restored exact source remains admissible");
        } finally {
            try (var files = Files.walk(temporary)) {
                files.sorted(java.util.Comparator.reverseOrder()).forEach(path -> {
                    try { Files.delete(path); } catch (Exception error) { throw new RuntimeException(error); }
                });
            }
        }
        System.out.println("PASS " + checks + " actual registrant controls");
    }
}
