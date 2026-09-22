// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { WelcomeFlowPage, type OnboardingActions } from "@msime/ui";

afterEach(cleanup);

function makeActions(overrides: Partial<OnboardingActions> = {}): OnboardingActions {
  return {
    prepareResources: vi.fn().mockResolvedValue(undefined),
    openSystemKeyboardSettings: vi.fn().mockResolvedValue(undefined),
    showInputMethodPicker: vi.fn().mockResolvedValue(undefined),
    ...overrides,
  };
}

test("starts on the welcome step", () => {
  render(
    <WelcomeFlowPage actions={makeActions()} onComplete={vi.fn().mockResolvedValue(undefined)} />,
  );

  expect(screen.getByRole("heading", { name: "欢迎使用水杉" })).toBeTruthy();
  expect(screen.getByText("1 / 4")).toBeTruthy();
  expect(screen.getByRole("button", { name: "开始设置" })).toBeTruthy();
});

test("prepares resources before entering the Android setup step", async () => {
  const actions = makeActions();
  render(<WelcomeFlowPage actions={actions} onComplete={vi.fn().mockResolvedValue(undefined)} />);

  fireEvent.click(screen.getByRole("button", { name: "开始设置" }));

  await waitFor(() => expect(actions.prepareResources).toHaveBeenCalledOnce());
  expect(await screen.findByRole("heading", { name: "启用键盘" })).toBeTruthy();
  expect(screen.getByText("2 / 4")).toBeTruthy();
});

test("exposes Android system settings and input method picker actions", async () => {
  const actions = makeActions();
  render(<WelcomeFlowPage actions={actions} onComplete={vi.fn().mockResolvedValue(undefined)} />);
  fireEvent.click(screen.getByRole("button", { name: "开始设置" }));
  await screen.findByRole("heading", { name: "启用键盘" });

  fireEvent.click(screen.getByRole("button", { name: "打开系统设置" }));
  await waitFor(() => expect(actions.openSystemKeyboardSettings).toHaveBeenCalledOnce());
  fireEvent.click(screen.getByRole("button", { name: "选择输入法" }));
  await waitFor(() => expect(actions.showInputMethodPicker).toHaveBeenCalledOnce());
});

test("adapts setup copy and actions for HarmonyOS", async () => {
  const actions = makeActions({ platform: "harmony" });
  render(<WelcomeFlowPage actions={actions} onComplete={vi.fn().mockResolvedValue(undefined)} />);
  fireEvent.click(screen.getByRole("button", { name: "开始设置" }));
  await screen.findByRole("heading", { name: "启用键盘" });

  expect(screen.getByText(/HarmonyOS 中启用并选择水杉输入法/)).toBeTruthy();
  expect(screen.getByText("前往 HarmonyOS 的系统输入法设置。")).toBeTruthy();
  expect(screen.getByText(/系统设置页面由 HarmonyOS 管理/)).toBeTruthy();
  expect(screen.queryByText(/Android/)).toBeNull();

  fireEvent.click(screen.getByRole("button", { name: "打开系统设置" }));
  await waitFor(() => expect(actions.openSystemKeyboardSettings).toHaveBeenCalledOnce());
  fireEvent.click(screen.getByRole("button", { name: "选择输入法" }));
  await waitFor(() => expect(actions.showInputMethodPicker).toHaveBeenCalledOnce());
});

test("adapts the setup step for iOS keyboard settings", async () => {
  const actions = makeActions({ platform: "ios" });
  render(<WelcomeFlowPage actions={actions} onComplete={vi.fn().mockResolvedValue(undefined)} />);
  fireEvent.click(screen.getByRole("button", { name: "开始设置" }));
  await screen.findByRole("heading", { name: "启用键盘" });
  expect(screen.getByRole("heading", { name: "添加水杉键盘" })).toBeTruthy();
  expect(screen.getByText(/通用 → 键盘 → 键盘/)).toBeTruthy();
  expect(screen.queryByRole("button", { name: "选择输入法" })).toBeNull();
});

test("lets iOS users postpone onboarding without showing Android-only actions", async () => {
  const onSkip = vi.fn().mockResolvedValue(undefined);
  const actions = makeActions({ platform: "ios" });
  render(
    <WelcomeFlowPage
      actions={actions}
      onComplete={vi.fn().mockResolvedValue(undefined)}
      onSkip={onSkip}
    />,
  );

  fireEvent.click(screen.getByRole("button", { name: "稍后设置" }));

  await waitFor(() => expect(onSkip).toHaveBeenCalledOnce());
  expect(screen.queryByRole("button", { name: "选择输入法" })).toBeNull();
});

test("passes the nine-key choice when onboarding is completed", async () => {
  const onComplete = vi.fn().mockResolvedValue(undefined);
  render(<WelcomeFlowPage actions={makeActions()} onComplete={onComplete} />);

  fireEvent.click(screen.getByRole("button", { name: "开始设置" }));
  await screen.findByRole("heading", { name: "启用键盘" });
  fireEvent.click(screen.getByRole("button", { name: "下一步" }));
  await screen.findByRole("heading", { name: "选择输入方式" });
  fireEvent.click(screen.getByRole("radio", { name: /全拼 9 键/ }));
  fireEvent.click(screen.getByRole("button", { name: "下一步" }));
  await screen.findByRole("heading", { name: "让表达更轻松" });
  fireEvent.click(screen.getByRole("button", { name: "开始使用水杉" }));

  await waitFor(() => expect(onComplete).toHaveBeenCalledWith("nine_key"));
});

test("reports a resource preparation failure", async () => {
  const actions = makeActions({
    prepareResources: vi.fn().mockRejectedValue(new Error("bootstrap")),
  });
  render(<WelcomeFlowPage actions={actions} onComplete={vi.fn().mockResolvedValue(undefined)} />);

  fireEvent.click(screen.getByRole("button", { name: "开始设置" }));

  expect((await screen.findByRole("alert")).textContent).toContain("操作失败");
  expect(screen.getByRole("heading", { name: "欢迎使用水杉" })).toBeTruthy();
});
