package app.nmic.pwdhash;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.ClipData;
import android.content.ClipDescription;
import android.content.ClipboardManager;
import android.content.Intent;
import android.content.res.Configuration;
import android.graphics.Color;
import android.graphics.Insets;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.PersistableBundle;
import android.os.SystemClock;
import android.text.Editable;
import android.text.InputType;
import android.text.TextUtils;
import android.text.TextWatcher;
import android.view.ActionMode;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.Menu;
import android.view.MenuItem;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowManager;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputMethodManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.ImageButton;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

/** A single native screen. No accounts, files, preferences, network, or history. */
public final class MainActivity extends Activity {
    private static final String CLIP_OWNER = "app.nmic.pwdhash.OWNER";
    private static final String CLIP_EXPIRES = "app.nmic.pwdhash.EXPIRES_ELAPSED";
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final IdleDeadline idle = new IdleDeadline();
    private EditText address, password, output;
    private Button copyButton;
    private TextView status, domainHint, backgroundDetail;
    private Switch clearOnBackground;
    private LinearLayout content;
    private boolean internalEdit, foreground;
    private int accent, foregroundColor, secondaryColor, cardColor;

    private final Runnable idleTask = () -> {
        if (idle.isExpired(SystemClock.elapsedRealtime())) clearSession(R.string.idle_clear_status, false);
    };
    private final Runnable clipboardTask = () -> clearOwnedClipboard(true);

    @Override public void onCreate(Bundle savedInstanceState) {
        // A recreated process/activity starts with an empty session.
        super.onCreate(null);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);
        boolean dark = (getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES;
        accent = Color.parseColor(dark ? "#6ED6B3" : "#195C47");
        foregroundColor = Color.parseColor(dark ? "#F0F5F1" : "#18271E");
        secondaryColor = Color.parseColor(dark ? "#B2C0B7" : "#56675D");
        cardColor = Color.parseColor(dark ? "#202C25" : "#FFFFFF");
        FrameLayout frame = new FrameLayout(this);
        frame.setBackgroundColor(Color.parseColor(dark ? "#141C18" : "#F2F5F2"));
        frame.setSaveEnabled(false);
        frame.setImportantForAutofill(View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS);
        if (Build.VERSION.SDK_INT >= 30) frame.setImportantForContentCapture(View.IMPORTANT_FOR_CONTENT_CAPTURE_NO_EXCLUDE_DESCENDANTS);
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setSaveEnabled(false);
        content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(dp(20), dp(12), dp(20), dp(24));
        content.setSaveEnabled(false);
        scroll.addView(content, new ScrollView.LayoutParams(-1, -2));
        frame.addView(scroll, new FrameLayout.LayoutParams(-1, -1));
        setContentView(frame);
        if (Build.VERSION.SDK_INT >= 30) getWindow().setDecorFitsSystemWindows(false);
        frame.setOnApplyWindowInsetsListener((view, insets) -> {
            if (Build.VERSION.SDK_INT >= 30) {
                Insets padding = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout() | WindowInsets.Type.ime());
                frame.setPadding(padding.left, padding.top, padding.right, padding.bottom);
            }
            return insets;
        });
        frame.requestApplyInsets();

        LinearLayout header = row();
        TextView title = label(getString(R.string.app_name), 32, foregroundColor);
        title.setTypeface(null, Typeface.BOLD);
        header.addView(title, new LinearLayout.LayoutParams(0, -2, 1));
        Button clear = button(R.string.clear, R.id.clear_all);
        clear.setContentDescription(getString(R.string.clear_all));
        clear.setOnClickListener(v -> { if (acceptInteraction()) clearSession(R.string.manual_clear_status, false); });
        header.addView(clear);
        add(header, 0);
        TextView badge = label(getString(R.string.badge), 12, accent);
        badge.setTypeface(null, Typeface.BOLD);
        add(badge, 10);
        address = field(R.string.site_address, R.string.site_address_hint, R.id.site_address, false, true);
        password = field(R.string.site_password, R.string.site_password_hint, R.id.site_password, true, true);
        domainHint = label(getString(R.string.domain_default), 12, secondaryColor);
        add(domainHint, 4);
        output = field(R.string.hashed_password, R.string.hashed_password_hint, R.id.hashed_password, true, false);

        LinearLayout actions = row();
        Button generate = button(R.string.generate, R.id.generate);
        generate.setBackground(card(accent, 14));
        generate.setTextColor(dark ? Color.parseColor("#10251A") : Color.WHITE);
        generate.setOnClickListener(v -> generate());
        copyButton = button(R.string.copy, R.id.copy_password);
        copyButton.setContentDescription(getString(R.string.copy_password));
        copyButton.setEnabled(false);
        copyButton.setOnClickListener(v -> copyPassword());
        LinearLayout.LayoutParams action = new LinearLayout.LayoutParams(0, dp(52), 1);
        action.setMarginEnd(dp(10));
        actions.addView(generate, action);
        actions.addView(copyButton, new LinearLayout.LayoutParams(0, dp(52), 1));
        add(actions, 10);
        add(label(getString(R.string.hold_hint), 12, secondaryColor), 6);
        status = label(getString(R.string.initial_status), 14, secondaryColor);
        status.setId(R.id.status);
        add(status, 8);

        clearOnBackground = new Switch(this);
        clearOnBackground.setId(R.id.clear_on_background);
        clearOnBackground.setText(R.string.background_title);
        clearOnBackground.setTextColor(foregroundColor);
        clearOnBackground.setTextSize(14);
        clearOnBackground.setChecked(true);
        clearOnBackground.setSaveEnabled(false);
        clearOnBackground.setMinHeight(dp(48));
        add(clearOnBackground, 10);
        backgroundDetail = label(getString(R.string.background_on), 12, secondaryColor);
        add(backgroundDetail, 0);
        clearOnBackground.setOnCheckedChangeListener((v, on) -> backgroundDetail.setText(on ? R.string.background_on : R.string.background_off));
        add(label(getString(R.string.clipboard_note), 12, secondaryColor), 6);
        addAbout();

        TextWatcher watcher = new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) {}
            @Override public void afterTextChanged(Editable value) { if (!internalEdit) inputsChanged(); }
        };
        address.addTextChangedListener(watcher);
        password.addTextChangedListener(watcher);
        address.setImeOptions(EditorInfo.IME_ACTION_NEXT | EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING | EditorInfo.IME_FLAG_NO_EXTRACT_UI);
        address.setOnEditorActionListener((v, id, event) -> { password.requestFocus(); return true; });
        password.setOnEditorActionListener((v, id, event) -> { generate(); return true; });
    }

    private int dp(int value) { return Math.round(value * getResources().getDisplayMetrics().density); }
    private LinearLayout row() {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL); row.setGravity(Gravity.CENTER_VERTICAL);
        return row;
    }
    private void add(View view, int top) {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, -2);
        params.topMargin = dp(top); content.addView(view, params);
    }
    private TextView label(String value, int size, int color) {
        TextView label = new TextView(this);
        label.setText(value); label.setTextSize(size); label.setTextColor(color); label.setSaveEnabled(false);
        return label;
    }
    private Button button(int text, int id) {
        Button button = new Button(this);
        button.setId(id); button.setText(text); button.setAllCaps(false); button.setTextColor(accent);
        button.setMinHeight(dp(48)); button.setSaveEnabled(false);
        return button;
    }
    private GradientDrawable card(int color, int radius) {
        GradientDrawable shape = new GradientDrawable();
        shape.setColor(color); shape.setCornerRadius(dp(radius));
        return shape;
    }

    private EditText field(int title, int hint, int id, boolean secret, boolean editable) {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL); box.setPadding(dp(16), dp(10), dp(8), dp(6));
        box.setBackground(card(cardColor, 16)); box.setSaveEnabled(false);
        TextView heading = label(getString(title), 14, secondaryColor);
        heading.setTypeface(null, Typeface.BOLD); heading.setLabelFor(id);
        box.addView(heading);
        LinearLayout line = row();
        EditText field = new EditText(this);
        field.setId(id); field.setHint(hint); field.setTextSize(18); field.setTextColor(foregroundColor);
        field.setHintTextColor(secondaryColor); field.setBackground(null);
        field.setSingleLine(true); field.setMinHeight(dp(48)); field.setPadding(0, 0, dp(4), 0);
        field.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS |
            (secret ? InputType.TYPE_TEXT_VARIATION_PASSWORD : InputType.TYPE_TEXT_VARIATION_URI));
        field.setTypeface(Typeface.DEFAULT);
        field.setImeOptions(EditorInfo.IME_ACTION_GO | EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING | EditorInfo.IME_FLAG_NO_EXTRACT_UI);
        field.setSaveEnabled(false); field.setSaveFromParentEnabled(false); field.setFreezesText(false);
        field.setImportantForAutofill(View.IMPORTANT_FOR_AUTOFILL_NO);
        if (Build.VERSION.SDK_INT >= 30) field.setImportantForContentCapture(View.IMPORTANT_FOR_CONTENT_CAPTURE_NO);
        field.setSelectAllOnFocus(false);
        if (secret) {
            field.setTransformationMethod(HiddenPasswordTransformation.INSTANCE);
            ActionMode.Callback menu = new ActionMode.Callback() {
                @Override public boolean onCreateActionMode(ActionMode mode, Menu menu) { stripCopy(menu); return editable; }
                @Override public boolean onPrepareActionMode(ActionMode mode, Menu menu) { stripCopy(menu); return editable; }
                @Override public boolean onActionItemClicked(ActionMode mode, MenuItem item) { return item.getItemId() == android.R.id.copy || item.getItemId() == android.R.id.cut || item.getItemId() == android.R.id.shareText; }
                @Override public void onDestroyActionMode(ActionMode mode) {}
            };
            field.setCustomSelectionActionModeCallback(menu); field.setCustomInsertionActionModeCallback(menu);
        }
        if (!editable) { field.setKeyListener(null); field.setFocusable(false); field.setLongClickable(false); }
        line.addView(field, new LinearLayout.LayoutParams(0, -2, 1));
        if (secret) {
            HoldButton eye = new HoldButton(field);
            eye.setId(editable ? R.id.password_reveal : R.id.output_reveal);
            eye.setContentDescription(getString(editable ? R.string.hold_password : R.string.hold_output));
            line.addView(eye, new LinearLayout.LayoutParams(dp(48), dp(48)));
        }
        box.addView(line); add(box, 10);
        return field;
    }

    private static void stripCopy(Menu menu) {
        menu.removeItem(android.R.id.copy); menu.removeItem(android.R.id.cut); menu.removeItem(android.R.id.shareText);
        for (int i = menu.size() - 1; i >= 0; i--) {
            Intent intent = menu.getItem(i).getIntent();
            if (intent != null && Intent.ACTION_PROCESS_TEXT.equals(intent.getAction())) menu.removeItem(menu.getItem(i).getItemId());
        }
    }

    private final class HoldButton extends ImageButton {
        private final EditText field;
        private int pointer = -1;
        HoldButton(EditText field) {
            super(MainActivity.this); this.field = field;
            setImageResource(R.drawable.ic_eye); setBackgroundColor(Color.TRANSPARENT);
            setPadding(dp(12), dp(12), dp(12), dp(12));
        }
        @Override public boolean onTouchEvent(MotionEvent event) {
            int action = event.getActionMasked();
            if (action == MotionEvent.ACTION_DOWN) {
                if (!acceptInteraction()) return true;
                pointer = event.getPointerId(0); getParent().requestDisallowInterceptTouchEvent(true);
                reveal(field, true);
            } else if (action == MotionEvent.ACTION_MOVE) {
                int index = event.findPointerIndex(pointer);
                boolean inside = index >= 0 && event.getX(index) >= 0 && event.getX(index) <= getWidth() && event.getY(index) >= 0 && event.getY(index) <= getHeight();
                reveal(field, inside && pointer != -1);
            } else if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL ||
                action == MotionEvent.ACTION_POINTER_UP && event.getPointerId(event.getActionIndex()) == pointer) {
                pointer = -1; reveal(field, false); getParent().requestDisallowInterceptTouchEvent(false);
                if (action == MotionEvent.ACTION_UP) performClick();
            }
            return true;
        }
        @Override public boolean performClick() { super.performClick(); return true; }
    }

    private void reveal(EditText field, boolean show) {
        int start = field.getSelectionStart(), end = field.getSelectionEnd();
        field.setTransformationMethod(show ? null : HiddenPasswordTransformation.INSTANCE);
        if (start >= 0 && end >= 0) field.setSelection(Math.min(start, field.length()), Math.min(end, field.length()));
    }
    private void hidePasswords() {
        if (password != null) reveal(password, false);
        if (output != null) reveal(output, false);
    }
    private boolean hasData() { return address != null && (address.length() != 0 || password.length() != 0 || output.length() != 0); }
    private boolean acceptInteraction() {
        if (idle.isExpired(SystemClock.elapsedRealtime())) { clearSession(R.string.idle_clear_status, false); return false; }
        if (hasData()) touch();
        return true;
    }
    private void touch() {
        idle.touch(SystemClock.elapsedRealtime()); handler.removeCallbacks(idleTask);
        handler.postDelayed(idleTask, IdleDeadline.TIMEOUT_MILLIS);
    }
    private void inputsChanged() {
        output.getText().clear(); reveal(output, false); copyButton.setEnabled(false);
        try { domainHint.setText(getString(R.string.domain_hint, LegacyPwdHash.domain(address.getText().toString()))); }
        catch (IllegalArgumentException error) { domainHint.setText(R.string.domain_default); }
        status.setText(R.string.ready_status); touch();
    }
    private void generate() {
        if (!acceptInteraction()) return;
        char[] source = new char[password.length()];
        TextUtils.getChars(password.getText(), 0, source.length, source, 0);
        try {
            String result = LegacyPwdHash.generate(address.getText().toString(), source);
            reveal(output, false); output.setText(result); copyButton.setEnabled(true); hideKeyboard();
            status.setText(result.indexOf('\0') >= 0 ? R.string.legacy_nul_status : R.string.generated_status); touch();
        } catch (IllegalArgumentException error) {
            output.getText().clear(); copyButton.setEnabled(false);
            status.setText(address.length() == 0 ? R.string.empty_address : password.length() == 0 ? R.string.empty_password : R.string.empty_address);
        } catch (IllegalStateException error) { status.setText(R.string.generation_error); }
        finally { Arrays.fill(source, '\0'); }
    }
    private void hideKeyboard() {
        View focused = getCurrentFocus();
        if (focused != null) { getSystemService(InputMethodManager.class).hideSoftInputFromWindow(focused.getWindowToken(), 0); focused.clearFocus(); }
    }
    private void copyPassword() {
        if (!acceptInteraction() || output.length() == 0) return;
        ClipData clip = ClipData.newPlainText("PwdHash", output.getText().toString());
        PersistableBundle extras = new PersistableBundle();
        extras.putBoolean("android.content.extra.IS_SENSITIVE", true);
        extras.putString(CLIP_OWNER, getPackageName());
        extras.putLong(CLIP_EXPIRES, SystemClock.elapsedRealtime() + 60_000L);
        clip.getDescription().setExtras(extras);
        getSystemService(ClipboardManager.class).setPrimaryClip(clip);
        handler.removeCallbacks(clipboardTask); handler.postDelayed(clipboardTask, 60_000L);
        hidePasswords(); status.setText(R.string.copied_status);
    }
    private void clearOwnedClipboard(boolean onlyExpired) {
        if (!foreground || !hasWindowFocus()) return;
        ClipboardManager clipboard = getSystemService(ClipboardManager.class);
        ClipDescription description = clipboard.getPrimaryClipDescription();
        PersistableBundle extras = description == null ? null : description.getExtras();
        if (extras == null || !getPackageName().equals(extras.getString(CLIP_OWNER))) return;
        long remaining = extras.getLong(CLIP_EXPIRES) - SystemClock.elapsedRealtime();
        if (!onlyExpired || remaining <= 0) clipboard.clearPrimaryClip();
        else { handler.removeCallbacks(clipboardTask); handler.postDelayed(clipboardTask, remaining); }
    }
    private void clearSession(int reason, boolean keepCopy) {
        if (address == null) return;
        hidePasswords(); hideKeyboard(); internalEdit = true;
        try { address.getText().clear(); password.getText().clear(); output.getText().clear(); }
        finally { internalEdit = false; }
        copyButton.setEnabled(false); domainHint.setText(R.string.domain_default); status.setText(reason);
        handler.removeCallbacks(idleTask); idle.reset();
        if (!keepCopy) clearOwnedClipboard(false);
    }

    private void addAbout() {
        Button toggle = button(R.string.about, R.id.about_credits);
        add(toggle, 8);
        LinearLayout details = new LinearLayout(this);
        details.setOrientation(LinearLayout.VERTICAL); details.setPadding(dp(16), dp(12), dp(16), dp(16));
        details.setBackground(card(cardColor, 16)); details.setVisibility(View.GONE);
        details.addView(label(getString(R.string.author), 14, foregroundColor));
        Button contact = button(R.string.contact, View.generateViewId());
        contact.setOnClickListener(v -> openExternal(Intent.ACTION_SENDTO, "mailto:pwdhash@nmic.app", R.string.no_email_app));
        details.addView(contact, new LinearLayout.LayoutParams(-1, -2));
        Button source = button(R.string.source_url, View.generateViewId());
        source.setOnClickListener(v -> openExternal(Intent.ACTION_VIEW, "https://pwdhash.github.io/website/", R.string.no_browser));
        details.addView(source, new LinearLayout.LayoutParams(-1, -2));
        details.addView(label(getString(R.string.contributors), 12, secondaryColor));
        TextView heading = label(getString(R.string.license_heading), 14, foregroundColor);
        heading.setTypeface(null, Typeface.BOLD); details.addView(heading);
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(getAssets().open("ThirdPartyNotices.txt"), StandardCharsets.UTF_8))) {
            StringBuilder text = new StringBuilder(); String line;
            while ((line = reader.readLine()) != null) text.append(line).append('\n');
            details.addView(label(text.toString(), 12, secondaryColor));
        } catch (java.io.IOException ignored) { /* Build validation checks the bundled notice. */ }
        add(details, 0);
        toggle.setOnClickListener(v -> {
            if (!acceptInteraction()) return;
            hidePasswords(); hideKeyboard();
            boolean expanded = details.getVisibility() != View.VISIBLE;
            details.setVisibility(expanded ? View.VISIBLE : View.GONE);
            toggle.setText(expanded ? R.string.about_hide : R.string.about);
        });
    }
    private void openExternal(String action, String uri, int unavailable) {
        if (!acceptInteraction()) return;
        hidePasswords(); hideKeyboard();
        try { startActivity(new Intent(action, Uri.parse(uri))); }
        catch (ActivityNotFoundException error) { status.setText(unavailable); }
    }

    @Override public boolean dispatchTouchEvent(MotionEvent event) {
        if (!acceptInteraction()) return true;
        return super.dispatchTouchEvent(event);
    }
    @Override public boolean dispatchKeyEvent(KeyEvent event) {
        if (!acceptInteraction()) return true;
        return super.dispatchKeyEvent(event);
    }
    @Override protected void onResume() {
        super.onResume(); foreground = true; hidePasswords();
        if (idle.isExpired(SystemClock.elapsedRealtime())) clearSession(R.string.idle_clear_status, false);
    }
    @Override public void onWindowFocusChanged(boolean focused) {
        super.onWindowFocusChanged(focused);
        if (focused) {
            if (idle.isExpired(SystemClock.elapsedRealtime())) clearSession(R.string.idle_clear_status, false);
            clearOwnedClipboard(true);
        } else hidePasswords();
    }
    @Override protected void onPause() { hidePasswords(); foreground = false; super.onPause(); }
    @Override protected void onStop() {
        if (clearOnBackground != null && clearOnBackground.isChecked()) clearSession(R.string.background_clear_status, true);
        else if (idle.isExpired(SystemClock.elapsedRealtime())) clearSession(R.string.idle_clear_status, true);
        super.onStop();
    }
    @Override protected void onSaveInstanceState(Bundle state) { state.clear(); }
    @Override public void onLowMemory() { clearSession(R.string.manual_clear_status, false); super.onLowMemory(); }
    @Override protected void onDestroy() {
        clearSession(R.string.manual_clear_status, true); handler.removeCallbacksAndMessages(null); super.onDestroy();
    }
}
