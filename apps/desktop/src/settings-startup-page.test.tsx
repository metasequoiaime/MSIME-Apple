// @vitest-environment jsdom
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { SettingsStartupPage } from "@msime/ui";
import { afterEach, expect, it, describe, vi } from "vitest";

afterEach(cleanup);

describe("Windows settings startup page", () => {
  it("matches the native splash copy and exposes a close action", () => {
    const close = vi.fn();
    render(<SettingsStartupPage onClose={close} />);

    expect(screen.getByRole("heading", { name: "正在打开设置" })).toBeTruthy();
    expect(screen.getByRole("status").textContent).toBe("冷启动可能需要稍等片刻");
    expect(screen.getByRole("main", { name: "设置加载中" }).getAttribute("aria-busy")).toBe("true");
    fireEvent.click(screen.getByRole("button", { name: "关闭设置" }));
    expect(close).toHaveBeenCalledTimes(1);
  });

  it("does not render a close button when the host has no window control", () => {
    render(<SettingsStartupPage />);
    expect(screen.queryByRole("button", { name: "关闭设置" })).toBeNull();
  });
});
