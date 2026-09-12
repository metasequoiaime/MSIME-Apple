package app.msime.client.test;

import android.content.Intent;
import android.graphics.Rect;
import android.view.accessibility.AccessibilityNodeInfo;
import java.util.function.Predicate;

/** Device-only acceptance for the full-surface Apple-style tools panel. */
public final class MoreToolsDeviceSmoke extends DeviceSmoke {
    @Override protected String successDescription() {
        return "full-surface tools grouping, feedback state and keyboard return";
    }

    @Override protected void runChecks() throws Exception {
        Intent intent = new Intent(getTargetContext(), EditorActivity.class);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
        startActivitySync(intent);
        stage = "more tools focus";
        tap(field("msime-test-plain"));
        stage = "more tools open";
        tap(key("更多"));
        AccessibilityNodeInfo panel = await(toolPanel());
        stage = "more tools primary cards";
        Rect panelBounds = new Rect();
        panel.getBoundsInScreen(panelBounds);
        for (String title : new String[] {"剪贴板历史", "AI 润色", "语音结果"}) {
            AccessibilityNodeInfo card = await(tool(title));
            Rect cardBounds = new Rect();
            card.getBoundsInScreen(cardBounds);
            if (cardBounds.width() <= panelBounds.width() / 2)
                throw new AssertionError("Primary tool is not a full-width card");
            int expectedHeight = Math.round(48 * getTargetContext()
                .getResources().getDisplayMetrics().density);
            if (Math.abs(cardBounds.height() - expectedHeight) > 2)
                throw new AssertionError("Primary card height mismatch");
        }
        stage = "more tools feedback cards";
        AccessibilityNodeInfo sound = await(tool("按键音"));
        AccessibilityNodeInfo haptics = await(tool("按键振动"));
        if (!validFeedbackState(sound) || !validFeedbackState(haptics))
            throw new AssertionError("Feedback state was not exposed");
        String originalSound = sound.getStateDescription().toString();
        String changedSound = "已开启".equals(originalSound) ? "已关闭" : "已开启";
        stage = "more tools feedback update";
        tap(tool("按键音"));
        await(toolWithState("按键音", changedSound));
        tap(tool("按键音"));
        await(toolWithState("按键音", originalSound));
        stage = "more tools return";
        tap(tool("返回键盘"));
        await(key("n").and(AccessibilityNodeInfo::isClickable));
    }

    private boolean validFeedbackState(AccessibilityNodeInfo node) {
        CharSequence state = node.getStateDescription();
        return state != null && (equalsText("已开启", state) || equalsText("已关闭", state))
            && node.isSelected() == equalsText("已开启", state);
    }

    private Predicate<AccessibilityNodeInfo> toolPanel() {
        return node -> equalsText("app.msime.client.preview", node.getPackageName())
            && equalsText("更多工具", node.getContentDescription());
    }

    private Predicate<AccessibilityNodeInfo> tool(String description) {
        return node -> equalsText("app.msime.client.preview", node.getPackageName())
            && equalsText(description, node.getContentDescription());
    }

    private Predicate<AccessibilityNodeInfo> toolWithState(String description, String state) {
        return tool(description).and(node -> equalsText(state, node.getStateDescription()));
    }
}
