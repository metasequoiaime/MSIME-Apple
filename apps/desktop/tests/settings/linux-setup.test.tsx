// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { LinuxSetupPage, type LinuxSetupClient, type LinuxSetupStatus } from "@msime/ui";

afterEach(cleanup);

const missing: LinuxSetupStatus = {
  prepared: false,
  stateDirectory: "/home/user/.config/msime-client",
  directoryOccupied: false,
  setupAvailable: true,
};

test("Linux first-run page runs setup with the download choice and streams its output", async () => {
  const client: LinuxSetupClient = {
    run: vi.fn(async (_download, onLine) => {
      onLine({ text: "词库已校验：/usr/share/msime-client/resources", error: false });
      onLine({ text: "启用用户服务失败", error: true });
      return { ...missing, prepared: true };
    }),
  };
  const onComplete = vi.fn();
  render(<LinuxSetupPage status={missing} client={client} onComplete={onComplete} />);
  expect(screen.getByText(/\/home\/user\/\.config\/msime-client/)).toBeTruthy();
  fireEvent.click(screen.getByRole("checkbox"));
  fireEvent.click(screen.getByRole("button", { name: "开始配置" }));
  await screen.findByRole("heading", { name: "配置完成" });
  expect(client.run).toHaveBeenCalledWith(true, expect.any(Function));
  const log = screen.getByRole("log", { name: "配置输出" });
  expect(log.textContent).toContain("词库已校验");
  expect(log.textContent).toContain("启用用户服务失败");
  fireEvent.click(screen.getByRole("button", { name: "进入设置" }));
  expect(onComplete).toHaveBeenCalled();
});

test("Linux first-run page keeps the output and offers a retry when setup fails", async () => {
  const client: LinuxSetupClient = {
    run: vi.fn(async (_download, onLine) => {
      onLine({ text: "词库目录不可用", error: true });
      throw { code: "setup_failed" };
    }),
  };
  render(<LinuxSetupPage status={missing} client={client} onComplete={vi.fn()} />);
  fireEvent.click(screen.getByRole("button", { name: "开始配置" }));
  expect((await screen.findByRole("alert")).textContent).toContain("查看上面的输出");
  expect(client.run).toHaveBeenCalledWith(false, expect.any(Function));
  expect(screen.getByRole("log").textContent).toContain("词库目录不可用");
  await waitFor(() =>
    expect((screen.getByRole("button", { name: "重新配置" }) as HTMLButtonElement).disabled).toBe(
      false,
    ),
  );
});

test("Linux first-run page explains why it cannot start instead of offering a failing button", () => {
  const run = vi.fn();
  const { rerender } = render(
    <LinuxSetupPage
      status={{ ...missing, directoryOccupied: true }}
      client={{ run }}
      onComplete={vi.fn()}
    />,
  );
  expect(screen.getByRole("alert").textContent).toContain("缺少 runtime-options.json");
  expect((screen.getByRole("button", { name: "开始配置" }) as HTMLButtonElement).disabled).toBe(
    true,
  );
  rerender(
    <LinuxSetupPage
      status={{ ...missing, setupAvailable: false }}
      client={{ run }}
      onComplete={vi.fn()}
    />,
  );
  expect(screen.getByRole("alert").textContent).toContain("msime-client-setup");
  expect(run).not.toHaveBeenCalled();
});
