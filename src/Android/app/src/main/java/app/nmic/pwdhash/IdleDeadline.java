package app.nmic.pwdhash;

/** Caller supplies SystemClock.elapsedRealtime(), which includes device sleep. */
public final class IdleDeadline {
    public static final long TIMEOUT_MILLIS = 300_000L;
    private long deadline;

    public void touch(long now) { deadline = now + TIMEOUT_MILLIS; }
    public boolean isExpired(long now) { return deadline != 0 && now >= deadline; }
    public void reset() { deadline = 0; }
}
