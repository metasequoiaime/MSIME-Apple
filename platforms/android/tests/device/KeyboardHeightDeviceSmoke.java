package app.msime.client.test;

import android.graphics.Rect;
import android.os.Bundle;
import android.os.ParcelFileDescriptor;
import android.os.SystemClock;
import android.util.AtomicFile;
import android.view.accessibility.AccessibilityNodeInfo;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import org.json.JSONObject;

/** Device acceptance for Apple-compatible keyboard height adjustment and persistence. */
public final class KeyboardHeightDeviceSmoke extends DeviceSmoke {
    @Override protected String successDescription() {
        return "keyboard height live preview, composition preservation, persistence and restart";
    }

    @Override protected void runChecks() throws Exception {
        File root = getTargetContext().getFilesDir();
        JSONObject options = new JSONObject(new String(Files.readAllBytes(
            new File(root, "runtime-options.json").toPath()), StandardCharsets.UTF_8));
        File directory = new File(options.getString("preferences_directory")).getCanonicalFile();
        if (!directory.toPath().startsWith(root.getCanonicalFile().toPath()))
            throw new AssertionError("Preferences escaped the preview sandbox");
        File preferences = new File(directory, "preferences.json");
        byte[] original = preferences.exists() ? Files.readAllBytes(preferences.toPath()) : null;
        long revision = original == null ? 0
            : new JSONObject(new String(original, StandardCharsets.UTF_8)).getLong("revision");
        JSONObject snapshot = new JSONObject().put("format_version", 1).put("revision", revision + 1)
            .put("preferences", new JSONObject(options.getJSONObject("preferences").toString())
                .put("touch_keyboard_height_adjustment", 0));
        try {
            stage = "baseline preferences";
            publish(preferences, snapshot.toString().getBytes(StandardCharsets.UTF_8));
            rebindInputMethod();
            openEditor();
            stage = "baseline keyboard height";
            int standard = keyHeight("n");
            stage = "composition before live resize";
            tap(key("n"));
            await(field("msime-test-plain").and(node -> equalsText("n", node.getText())));

            stage = "open keyboard settings";
            tap(key("设置"));
            AccessibilityNodeInfo slider = await(heightSlider());
            stage = "increase keyboard height";
            setProgress(slider, 48);
            long tallRevision = awaitHeightPreference(preferences, 48, revision + 2);
            stage = "return from tall setting";
            tap(description("返回键盘"));
            int tall = keyHeight("n");
            int minimumDelta = Math.round(12 * getTargetContext()
                .getResources().getDisplayMetrics().density);
            if (tall < standard + minimumDelta)
                throw new AssertionError("Positive adjustment did not enlarge key faces: "
                    + standard + " -> " + tall + ", expected delta " + minimumDelta);
            await(field("msime-test-plain").and(node -> equalsText("n", node.getText())));

            stage = "decrease keyboard height";
            tap(key("设置"));
            setProgress(await(heightSlider()), -12);
            awaitHeightPreference(preferences, -12, tallRevision + 1);
            tap(description("返回键盘"));
            int shortHeight = keyHeight("n");
            if (shortHeight >= standard)
                throw new AssertionError("Negative adjustment did not shrink key faces: "
                    + standard + " -> " + shortHeight);
            await(field("msime-test-plain").and(node -> equalsText("n", node.getText())));

            stage = "height survives input method restart";
            shell("am start -W -n app.msime.client.preview/app.msime.client.SetupActivity");
            rebindInputMethod();
            openEditor();
            int restarted = keyHeight("n");
            if (Math.abs(restarted - shortHeight) > 2)
                throw new AssertionError("Persisted height changed after restart");
        } finally {
            shell("am start -W -n app.msime.client.preview/app.msime.client.SetupActivity");
            if (original == null) Files.deleteIfExists(preferences.toPath());
            else publish(preferences, original);
        }
    }

    private void openEditor() throws Exception {
        shell("am start -W -f 0x10008000 -n app.msime.client.test/app.msime.client.test.EditorActivity");
        tap(field("msime-test-plain"));
    }

    private void rebindInputMethod() throws Exception {
        shell("ime disable app.msime.client.preview/app.msime.client.MSIMEInputService");
        shell("ime enable app.msime.client.preview/app.msime.client.MSIMEInputService");
        shell("ime set app.msime.client.preview/app.msime.client.MSIMEInputService");
        SystemClock.sleep(1000);
    }

    private int keyHeight(String label) {
        AccessibilityNodeInfo node = await(description("按键 " + label));
        Rect bounds = new Rect();
        node.getBoundsInScreen(bounds);
        return bounds.height();
    }

    private java.util.function.Predicate<AccessibilityNodeInfo> heightSlider() {
        return description("键盘高度").and(node -> node.getRangeInfo() != null);
    }

    private java.util.function.Predicate<AccessibilityNodeInfo> description(String value) {
        return node -> equalsText("app.msime.client.preview", node.getPackageName())
            && equalsText(value, node.getContentDescription());
    }

    private void setProgress(AccessibilityNodeInfo slider, float value) {
        Bundle arguments = new Bundle();
        arguments.putFloat(AccessibilityNodeInfo.ACTION_ARGUMENT_PROGRESS_VALUE, value);
        if (!slider.performAction(
                AccessibilityNodeInfo.AccessibilityAction.ACTION_SET_PROGRESS.getId(), arguments))
            throw new AssertionError("Height accessibility action failed");
    }

    private long awaitHeightPreference(File file, int expected, long minimumRevision)
            throws Exception {
        long deadline = SystemClock.uptimeMillis() + 15000;
        do {
            byte[] bytes = Files.readAllBytes(file.toPath());
            try {
                JSONObject current = new JSONObject(new String(bytes, StandardCharsets.UTF_8));
                if (current.getLong("revision") >= minimumRevision
                        && current.getJSONObject("preferences")
                            .getInt("touch_keyboard_height_adjustment") == expected) {
                    return current.getLong("revision");
                }
            } catch (RuntimeException ignored) {
                // Atomic replacement can briefly expose no complete snapshot to this polling read.
            }
            SystemClock.sleep(100);
        } while (SystemClock.uptimeMillis() < deadline);
        throw new AssertionError("Height preference was not saved");
    }

    private void shell(String command) throws Exception {
        try (var input = new ParcelFileDescriptor.AutoCloseInputStream(
                automation.executeShellCommand(command))) {
            byte[] buffer = new byte[1024];
            while (input.read(buffer) != -1) { }
        }
    }

    private void publish(File file, byte[] contents) throws Exception {
        AtomicFile target = new AtomicFile(file);
        FileOutputStream output = target.startWrite();
        try {
            output.write(contents);
            target.finishWrite(output);
        } catch (Exception error) {
            target.failWrite(output);
            throw error;
        }
    }
}
