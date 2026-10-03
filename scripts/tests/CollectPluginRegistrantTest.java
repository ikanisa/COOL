import java.nio.file.Files;
import java.nio.file.Path;

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
