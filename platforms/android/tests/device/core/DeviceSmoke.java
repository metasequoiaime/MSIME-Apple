package app.msime.client.test;

import android.accessibilityservice.AccessibilityServiceInfo;
import android.app.Activity;
import android.app.Instrumentation;
import android.app.UiAutomation;
import android.content.Intent;
import android.graphics.Rect;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.MotionEvent;
import android.view.InputDevice;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityWindowInfo;
import java.util.function.Predicate;

/** Device-only synthetic acceptance; reads both editor and IME accessibility windows. */
public class DeviceSmoke extends Instrumentation {
    protected UiAutomation automation;
    protected String stage = "launch";
    @Override public void onCreate(Bundle arguments) { super.onCreate(arguments); start(); }
    @Override public void onStart() {
        Bundle result = new Bundle();
        try {
            automation = getUiAutomation();
            AccessibilityServiceInfo info = automation.getServiceInfo();
            info.flags |= AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS;
            automation.setServiceInfo(info);
            runChecks();
            result.putString("stream", "MSIME_DEVICE_SMOKE_PASSED: " + successDescription() + "\n");
            finish(Activity.RESULT_OK, result);
        } catch (Exception | AssertionError error) {
            // Only fixed test-stage messages, never serialize editor contents.
            result.putString("stream", "MSIME_DEVICE_SMOKE_FAILED: " + stage + " (" + error.getClass().getSimpleName() + ")" + (error instanceof AssertionError ? " " + error.getMessage() : "") + "\n");
            finish(Activity.RESULT_CANCELED, result);
        }
    }
    protected String successDescription() {
        return "phrase commit, Traditional Chinese display/commit, deletion and password direct input";
    }
    protected void runChecks() throws Exception {
            Intent intent = new Intent(getTargetContext(), EditorActivity.class);
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
            startActivitySync(intent);
            stage = "plain focus";
            tap(field("msime-test-plain"));
            stage = "typing";
            for (String key : new String[] {"n", "i", "h", "a", "o"}) tap(key(key));
            stage = "phrase composition";
            await(field("msime-test-plain").and(node -> equalsText("nihao", node.getText())));
            stage = "phrase commit key";
            tap(key("空格"));
            stage = "phrase commit result";
            await(field("msime-test-plain").and(node -> equalsText("你好", node.getText())));
            stage = "deletion";
            tap(key("⌫"));
            await(field("msime-test-plain").and(node -> equalsText("你", node.getText())));
            stage = "simplified output baseline";
            AccessibilityNodeInfo script = await(scriptState());
            if (equalsText("繁", script.getText())) {
                tap(key("繁"));
                await(key("简").and(AccessibilityNodeInfo::isEnabled));
            }
            stage = "traditional output switch";
            tap(key("简"));
            await(key("繁").and(AccessibilityNodeInfo::isEnabled));
            stage = "traditional candidate display";
            for (String key : new String[] {"s", "h", "u", "r", "u", "f", "a"}) tap(key(key));
            await(imeTextContains("輸入法"));
            stage = "traditional commit key";
            tap(key("空格"));
            stage = "traditional commit result";
            await(field("msime-test-plain").and(node -> equalsText("你輸入法", node.getText())));
            stage = "restore simplified output";
            tap(key("繁"));
            await(key("简").and(AccessibilityNodeInfo::isEnabled));
            stage = "password focus action";
            tap(field("msime-test-password"));
            stage = "password field focus";
            await(field("msime-test-password").and(AccessibilityNodeInfo::isFocused));
            stage = "password direct mode";
            await(imeTextContains("直接输入"));
            stage = "password direct input";
            tap(key("n"));
            await(field("msime-test-password").and(node -> node.getText() != null && node.getText().length() == 1));
    }
    protected Predicate<AccessibilityNodeInfo> field(String description) {
        return node -> equalsText("app.msime.client.test", node.getPackageName()) && equalsText(description, node.getContentDescription());
    }
    protected Predicate<AccessibilityNodeInfo> key(String text) {
        return node -> equalsText("app.msime.client.preview", node.getPackageName()) && equalsText(text, node.getText());
    }
    protected Predicate<AccessibilityNodeInfo> scriptState() {
        return node -> equalsText("app.msime.client.preview", node.getPackageName())
            && node.isEnabled() && (equalsText("简", node.getText()) || equalsText("繁", node.getText()));
    }
    protected Predicate<AccessibilityNodeInfo> imeTextContains(String text) {
        return node -> equalsText("app.msime.client.preview", node.getPackageName())
            && node.getText() != null && node.getText().toString().contains(text);
    }
    protected static boolean equalsText(String expected, CharSequence actual) { return actual != null && expected.contentEquals(actual); }
    protected AccessibilityNodeInfo find(AccessibilityNodeInfo node, Predicate<AccessibilityNodeInfo> match) {
        if (node == null) return null;
        if (node.isVisibleToUser() && match.test(node)) return node;
        for (int index = 0; index < node.getChildCount(); index++) {
            AccessibilityNodeInfo found = find(node.getChild(index), match);
            if (found != null) return found;
        }
        return null;
    }
    private AccessibilityNodeInfo findAny(AccessibilityNodeInfo node,
                                           Predicate<AccessibilityNodeInfo> match) {
        if (node == null) return null;
        if (match.test(node)) return node;
        for (int index = 0; index < node.getChildCount(); index++) {
            AccessibilityNodeInfo found = findAny(node.getChild(index), match);
            if (found != null) return found;
        }
        return null;
    }
    protected AccessibilityNodeInfo await(Predicate<AccessibilityNodeInfo> match) {
        long deadline = SystemClock.uptimeMillis() + 15000;
        do {
            for (AccessibilityWindowInfo window : automation.getWindows()) {
                AccessibilityNodeInfo found = find(window.getRoot(), match);
                if (found != null) return found;
            }
            SystemClock.sleep(100);
        } while (SystemClock.uptimeMillis() < deadline);
        throw new AssertionError("Expected synthetic UI state was not observed");
    }
    private AccessibilityNodeInfo awaitAny(Predicate<AccessibilityNodeInfo> match) {
        long deadline = SystemClock.uptimeMillis() + 15000;
        do {
            for (AccessibilityWindowInfo window : automation.getWindows()) {
                AccessibilityNodeInfo found = findAny(window.getRoot(), match);
                if (found != null) return found;
            }
            SystemClock.sleep(100);
        } while (SystemClock.uptimeMillis() < deadline);
        throw new AssertionError("Expected synthetic control was not observed");
    }
    protected void tap(Predicate<AccessibilityNodeInfo> match) throws java.util.concurrent.TimeoutException {
        AccessibilityNodeInfo target = awaitAny(match);
        automation.waitForIdle(500, 5000);
        target = awaitAny(match);
        // Android 15 can reject synthetic coordinates over IME and instrumentation windows.
        // Accessibility click still invokes the real product control and InputConnection path.
        if (equalsText("app.msime.client.preview", target.getPackageName())
                && target.isClickable()) {
            if (!target.performAction(AccessibilityNodeInfo.ACTION_CLICK))
                throw new AssertionError("Synthetic control action failed");
            SystemClock.sleep(150);
            return;
        }
        if (!target.isVisibleToUser()) target = await(match);
        Rect bounds = new Rect();
        target.getBoundsInScreen(bounds);
        long now = SystemClock.uptimeMillis();
        MotionEvent down = MotionEvent.obtain(now, now, MotionEvent.ACTION_DOWN, bounds.centerX(), bounds.centerY(), 0);
        MotionEvent up = MotionEvent.obtain(now, now + 50, MotionEvent.ACTION_UP, bounds.centerX(), bounds.centerY(), 0);
        down.setSource(InputDevice.SOURCE_TOUCHSCREEN);
        up.setSource(InputDevice.SOURCE_TOUCHSCREEN);
        try {
            boolean pressed = automation.injectInputEvent(down, true);
            boolean released = automation.injectInputEvent(up, true);
            if (!pressed || !released) throw new AssertionError("Touch injection failed");
        } finally { down.recycle(); up.recycle(); }
        SystemClock.sleep(150);
    }
    protected void tapSymbol(String symbol) throws java.util.concurrent.TimeoutException {
        tap(key("符号"));
        tap(key(symbol));
        tap(key("字母"));
    }
}
