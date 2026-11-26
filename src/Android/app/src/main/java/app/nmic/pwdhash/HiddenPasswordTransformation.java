package app.nmic.pwdhash;

import android.text.Editable;
import android.text.GetChars;
import android.text.method.PasswordTransformationMethod;
import android.view.View;
import java.util.Arrays;

/** Masks immediately, including the last typed character. Reveal is hold-only. */
public final class HiddenPasswordTransformation extends PasswordTransformationMethod {
    public static final HiddenPasswordTransformation INSTANCE = new HiddenPasswordTransformation();
    private HiddenPasswordTransformation() {}
    @Override public CharSequence getTransformation(CharSequence source, View view) { return new Mask(source); }
    @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
    @Override public void onTextChanged(CharSequence s, int start, int before, int count) {}
    @Override public void afterTextChanged(Editable editable) {}

    private static final class Mask implements CharSequence, GetChars {
        private final CharSequence source;
        Mask(CharSequence source) { this.source = source; }
        @Override public int length() { return source.length(); }
        @Override public char charAt(int index) {
            if (index < 0 || index >= length()) throw new IndexOutOfBoundsException();
            return '\u2022';
        }
        @Override public CharSequence subSequence(int start, int end) {
            if (start < 0 || end < start || end > length()) throw new IndexOutOfBoundsException();
            char[] masked = new char[end - start]; Arrays.fill(masked, '\u2022'); return new String(masked);
        }
        @Override public void getChars(int start, int end, char[] destination, int offset) {
            if (start < 0 || end < start || end > length()) throw new IndexOutOfBoundsException();
            Arrays.fill(destination, offset, offset + end - start, '\u2022');
        }
        @Override public String toString() { return subSequence(0, length()).toString(); }
    }
}
