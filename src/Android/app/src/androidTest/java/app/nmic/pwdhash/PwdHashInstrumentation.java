package app.nmic.pwdhash.test;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Intent;
import android.graphics.Bitmap;
import android.os.Bundle;
import android.os.ParcelFileDescriptor;
import android.os.PersistableBundle;
import android.os.SystemClock;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.Switch;
import app.nmic.pwdhash.HiddenPasswordTransformation;
import app.nmic.pwdhash.IdleDeadline;
import app.nmic.pwdhash.LegacyPwdHash;
import app.nmic.pwdhash.MainActivity;
import app.nmic.pwdhash.R;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.concurrent.atomic.AtomicReference;
import org.json.JSONArray;
import org.json.JSONObject;

/** Device checks with synthetic inputs only; uses no external test libraries. */
public final class PwdHashInstrumentation extends Instrumentation {
    private MainActivity activity;
    private boolean screenshotsOnly;
    private final StringBuilder results = new StringBuilder();
    private interface MainTask { void run() throws Exception; }

    @Override public void onCreate(Bundle arguments) {
        super.onCreate(arguments);
        screenshotsOnly = arguments != null && "true".equals(arguments.getString("screenshots"));
        start();
    }
    @Override public void onStart() {
        if (screenshotsOnly) { captureStoreScreenshots(); return; }
        Bundle report = new Bundle();
        int resultCode = Activity.RESULT_CANCELED;
        try {
            referenceCases();
            Intent launch = new Intent(getTargetContext(), MainActivity.class);
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
            activity = (MainActivity)startActivitySync(launch);
            waitForFocus();
            onMain(() -> {
                activity.getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                check((activity.getWindow().getAttributes().flags & WindowManager.LayoutParams.FLAG_SECURE) != 0, "Screenshot protection missing");
                check(!field(R.id.site_password).isSaveEnabled(), "Password state restoration enabled");
                check(field(R.id.site_password).getTransformationMethod() instanceof HiddenPasswordTransformation, "Password not hidden");
                populate();
                check(((Button)activity.findViewById(R.id.copy_password)).isEnabled(), "Copy should be enabled");
                String previousPassword = field(R.id.site_password).getText().toString();
                field(R.id.site_address).setText("different.example.org");
                check(field(R.id.site_password).getText().toString().equals(previousPassword), "Address edit lost password");
                check(field(R.id.hashed_password).length() == 0 && !activity.findViewById(R.id.copy_password).isEnabled(), "Stale result remained copyable");
                tap(R.id.generate);
                View eye = activity.findViewById(R.id.password_reveal);
                motion(eye, MotionEvent.ACTION_DOWN);
                check(field(R.id.site_password).getTransformationMethod() == null, "Hold did not reveal");
                field(R.id.site_password).getText().insert(3, "X");
                check(field(R.id.hashed_password).length() == 0, "Password edit retained stale result");
                motion(eye, MotionEvent.ACTION_UP);
                check(field(R.id.site_password).getTransformationMethod() instanceof HiddenPasswordTransformation, "Release did not hide");
                check(field(R.id.site_password).getText().toString().equals("SynXtheticPassword9!"), "Reveal/edit lost existing text");
                field(R.id.site_password).getText().insert(4, "Y");
                check(field(R.id.site_password).getText().toString().equals("SynXYtheticPassword9!"), "Hidden editing lost text");
                motion(eye, MotionEvent.ACTION_DOWN); motion(eye, MotionEvent.ACTION_CANCEL);
                check(field(R.id.site_password).getTransformationMethod() instanceof HiddenPasswordTransformation, "Cancelled hold remained revealed");
                tap(R.id.generate);
                String expected = LegacyPwdHash.generate(field(R.id.site_address).getText().toString(), field(R.id.site_password).getText().toString().toCharArray());
                check(field(R.id.hashed_password).getText().toString().equals(expected), "UI generated a different result");
            });
            passed("screen privacy, input reuse, stale-result prevention, and hold/edit/release");

            onMain(() -> {
                tap(R.id.copy_password);
                ClipboardManager clipboard = activity.getSystemService(ClipboardManager.class);
                PersistableBundle extras = clipboard.getPrimaryClipDescription().getExtras();
                check(extras != null && extras.getBoolean("android.content.extra.IS_SENSITIVE"), "Copy missing sensitive flag");
                check("app.nmic.pwdhash".equals(extras.getString("app.nmic.pwdhash.OWNER")), "Copy ownership missing");
                check(clipboard.getPrimaryClip().getItemAt(0).getText().toString().equals(field(R.id.hashed_password).getText().toString()), "Copied result differs");
                extras.putLong("app.nmic.pwdhash.EXPIRES_ELAPSED", SystemClock.elapsedRealtime() - 1);
                ClipData expired = clipboard.getPrimaryClip(); expired.getDescription().setExtras(extras); clipboard.setPrimaryClip(expired);
                java.lang.reflect.Method clear = MainActivity.class.getDeclaredMethod("clearOwnedClipboard", boolean.class);
                clear.setAccessible(true); clear.invoke(activity, true);
                check(!clipboard.hasPrimaryClip(), "Expired own clipboard item remained");
                tap(R.id.copy_password);
                clipboard.setPrimaryClip(ClipData.newPlainText("Synthetic test replacement", "Synthetic newer copy"));
                tap(R.id.clear_all);
                check(clipboard.getPrimaryClip().getItemAt(0).getText().toString().equals("Synthetic newer copy"), "Clear deleted a newer clipboard item");
                clipboard.clearPrimaryClip();
            });
            passed("sensitive clipboard flags, exact copy, expiration, and newer-copy preservation");

            onMain(() -> { populate(); activity.moveTaskToBack(true); });
            waitFor(() -> field(R.id.site_password).length() == 0, "Default background clearing failed");
            bringBack(); waitForFocus();
            onMain(() -> {
                ((Switch)activity.findViewById(R.id.clear_on_background)).setChecked(false);
                populate(); activity.moveTaskToBack(true);
            });
            SystemClock.sleep(500);
            bringBack(); waitForFocus();
            onMain(() -> {
                check(field(R.id.site_password).getText().toString().equals("SyntheticPassword9!"), "Background keep option lost inputs");
                java.lang.reflect.Field deadline = MainActivity.class.getDeclaredField("idle"); deadline.setAccessible(true);
                ((IdleDeadline)deadline.get(activity)).touch(SystemClock.elapsedRealtime() - IdleDeadline.TIMEOUT_MILLIS - 1);
                tap(R.id.generate);
                check(field(R.id.site_password).length() == 0 && field(R.id.site_address).length() == 0, "Expired action exposed previous session");
                populate();
                Bundle saved = new Bundle(); saved.putString("synthetic", "placeholder");
                java.lang.reflect.Method save = MainActivity.class.getDeclaredMethod("onSaveInstanceState", Bundle.class); save.setAccessible(true); save.invoke(activity, saved);
                check(saved.isEmpty(), "Activity persisted its session");
                tap(R.id.about_credits); tap(R.id.about_credits); tap(R.id.clear_all);
            });
            passed("real background/foreground modes, expired-action rejection, empty saved state, and credits");
            report.putString("stream", results.toString());
            report.putString("result", "PASS");
            resultCode = Activity.RESULT_OK;
        } catch (Throwable error) {
            report.putString("stream", results + "FAIL: " + error + "\n" + android.util.Log.getStackTraceString(error));
            report.putString("result", "FAIL");
        } finally {
            if (activity != null) runOnMainSync(() -> { activity.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON); activity.finish(); });
        }
        finish(resultCode, report);
    }

    /** Test APK only: capture synthetic inputs, then restore protection and clear. */
    private void captureStoreScreenshots() {
        Bundle report = new Bundle();
        int resultCode = Activity.RESULT_CANCELED;
        try {
            Intent launch = new Intent(getTargetContext(), MainActivity.class);
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
            activity = (MainActivity)startActivitySync(launch);
            waitForFocus();
            onMain(() -> {
                check((activity.getWindow().getAttributes().flags & WindowManager.LayoutParams.FLAG_SECURE) != 0,
                        "Normal app must block screenshots");
                activity.getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                field(R.id.site_address).setText("example.com");
                field(R.id.site_password).setText("ExampleOnly123!");
                tap(R.id.generate);
                activity.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_SECURE);
            });
            saveScreenshot("01-generated-hidden.png");
            onMain(() -> motion(activity.findViewById(R.id.output_reveal), MotionEvent.ACTION_DOWN));
            saveScreenshot("02-hold-to-reveal.png");
            onMain(() -> {
                motion(activity.findViewById(R.id.output_reveal), MotionEvent.ACTION_UP);
                ((Switch)activity.findViewById(R.id.clear_on_background)).setChecked(false);
            });
            saveScreenshot("03-keep-while-switching.png");
            report.putString("result", "PASS");
            report.putString("stream", "Captured three screens using example.com / ExampleOnly123! only.\n");
            resultCode = Activity.RESULT_OK;
        } catch (Throwable error) {
            report.putString("result", "FAIL");
            report.putString("stream", android.util.Log.getStackTraceString(error));
        } finally {
            if (activity != null) runOnMainSync(() -> {
                activity.getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);
                activity.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                tap(R.id.clear_all);
                activity.finish();
            });
        }
        finish(resultCode, report);
    }

    private void saveScreenshot(String filename) throws Exception {
        waitForIdleSync();
        SystemClock.sleep(750);
        Bitmap image = getUiAutomation().takeScreenshot();
        check(image != null, "Android did not supply a screenshot");
        File directory = new File(getTargetContext().getCacheDir(), "store-screenshots");
        check(directory.isDirectory() || directory.mkdirs(), "Cannot create screenshot cache");
        try (FileOutputStream output = new FileOutputStream(new File(directory, filename))) {
            image.setHasAlpha(false);
            check(image.compress(Bitmap.CompressFormat.PNG, 100, output), "Cannot save screenshot");
        } finally { image.recycle(); }
    }

    private void referenceCases() throws Exception {
        byte[] bytes;
        try (InputStream input = getContext().getAssets().open("reference-vectors.json"); ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[8192]; int read;
            while ((read = input.read(buffer)) >= 0) output.write(buffer, 0, read);
            bytes = output.toByteArray();
        }
        JSONArray vectors = new JSONArray(new String(bytes, StandardCharsets.UTF_8));
        for (int i = 0; i < vectors.length(); i++) {
            JSONObject vector = vectors.getJSONObject(i);
            char[] password = vector.getString("password").toCharArray();
            try {
                String domain;
                try { domain = LegacyPwdHash.domain(vector.getString("address")); }
                catch (IllegalArgumentException error) { check(vector.isNull("domain"), "Unexpected invalid address in case " + i); continue; }
                check(domain.equals(vector.getString("domain")), "Domain mismatch in case " + i);
                check(LegacyPwdHash.derive(domain, password).equals(vector.getString("result")), "Hash mismatch in case " + i);
            } finally { Arrays.fill(password, '\0'); }
        }
        passed(vectors.length() + " original-JavaScript cases on the Android device");
    }
    private EditText field(int id) { return activity.findViewById(id); }
    private void tap(int id) { activity.findViewById(id).performClick(); }
    private void populate() {
        field(R.id.site_address).setText("example.com"); field(R.id.site_password).setText("SyntheticPassword9!"); tap(R.id.generate);
    }
    private void motion(View view, int action) {
        long now = SystemClock.uptimeMillis();
        MotionEvent event = MotionEvent.obtain(now, now, action, 10, 10, 0);
        try { view.dispatchTouchEvent(event); } finally { event.recycle(); }
    }
    private static void check(boolean condition, String message) { if (!condition) throw new AssertionError(message); }
    private void passed(String name) { results.append("PASS: ").append(name).append('\n'); }
    private void onMain(MainTask task) throws Exception {
        AtomicReference<Throwable> failure = new AtomicReference<>();
        runOnMainSync(() -> { try { task.run(); } catch (Throwable error) { failure.set(error); } });
        if (failure.get() != null) throw new AssertionError(failure.get());
    }
    private interface Condition { boolean test(); }
    private void waitFor(Condition condition, String message) throws Exception {
        long end = SystemClock.elapsedRealtime() + 15_000L;
        while (SystemClock.elapsedRealtime() < end) {
            boolean[] ready = {false}; onMain(() -> ready[0] = condition.test());
            if (ready[0]) return;
            SystemClock.sleep(50);
        }
        throw new AssertionError(message);
    }
    private void waitForFocus() throws Exception { waitFor(() -> activity.hasWindowFocus(), "Unlock the Android phone and leave PwdHash in the foreground"); }
    private void bringBack() throws Exception {
        try (ParcelFileDescriptor command = getUiAutomation().executeShellCommand("am start -W -n app.nmic.pwdhash/.MainActivity -f 0x10020000"); InputStream output = new ParcelFileDescriptor.AutoCloseInputStream(command)) {
            byte[] buffer = new byte[1024]; while (output.read(buffer) >= 0) { /* Drain command result; no user data. */ }
        }
    }
}
