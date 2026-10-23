package android.util;

import java.util.ArrayList;
import java.util.List;

/** Local JVM log sink. Android APIs are otherwise compiled from android.jar. */
public final class Log {
    public static final List<String> messages = new ArrayList<>();
    public static int d(String tag, String message) {
        messages.add(tag + ": " + message);
        return 0;
    }
    public static int e(String tag, String message) {
        messages.add(tag + ": " + message);
        return 0;
    }
}
