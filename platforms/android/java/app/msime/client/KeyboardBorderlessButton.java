package app.msime.client;

import android.content.Context;
import android.graphics.drawable.Drawable;
import android.widget.Button;

/** Button whose shortcut-bar face stays plain while the shared host still styles its text. */
public final class KeyboardBorderlessButton extends Button {
    public KeyboardBorderlessButton(Context context) {
        super(context);
        super.setBackground(null);
    }

    @Override public void setBackground(Drawable background) {
        // The scheme shortcut follows Apple's plain toolbar treatment. Its parent still owns the
        // hit target and skin text color; the common style pass must not put the box back.
    }
}
