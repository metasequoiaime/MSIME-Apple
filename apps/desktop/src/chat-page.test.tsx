// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { ChatPage, type ChatClient, type ChatMessage } from "@msime/ui";

afterEach(cleanup);

function client(overrides: Partial<ChatClient> = {}): ChatClient {
  return {
    models: async () => ({ data: [{ id: "fixture-chat" }, { id: "fixture-fast" }], defaultModel: "fixture-chat" }),
    complete: async (_messages: ChatMessage[], _model: string) => "fixture reply",
    ...overrides,
  };
}

test("loads models, sends a message, and starts a new conversation", async () => {
  const complete = vi.fn(async (messages: ChatMessage[], model: string) => {
    expect(messages).toEqual([{ role: "user", content: "fixture prompt" }]);
    expect(model).toBe("fixture-fast");
    return "fixture reply";
  });
  const confirm = vi.spyOn(window, "confirm").mockReturnValue(true);
  render(<ChatPage client={client({ complete })} />);

  const model = await screen.findByRole("combobox", { name: "聊天模型" });
  expect((model as HTMLSelectElement).value).toBe("fixture-chat");
  fireEvent.change(model, { target: { value: "fixture-fast" } });
  fireEvent.change(screen.getByRole("textbox", { name: "聊天消息" }), { target: { value: "fixture prompt" } });
  fireEvent.click(screen.getByRole("button", { name: "发送" }));
  await screen.findByText("fixture reply");
  expect(complete).toHaveBeenCalledTimes(1);

  fireEvent.click(screen.getByRole("button", { name: "新对话" }));
  expect(confirm).toHaveBeenCalledWith("开始新对话？当前消息将被清空。");
  expect(screen.queryByText("fixture prompt")).toBeNull();
  expect(screen.queryByText("fixture reply")).toBeNull();
  confirm.mockRestore();
});

test("shows an actionable error and retries the latest user message", async () => {
  const complete = vi.fn<(messages: ChatMessage[], model: string) => Promise<string>>();
  complete.mockRejectedValueOnce({ code: "account_unavailable" }).mockResolvedValueOnce("retried reply");
  render(<ChatPage client={client({ complete })} />);
  await screen.findByRole("combobox", { name: "聊天模型" });
  fireEvent.change(screen.getByRole("textbox", { name: "聊天消息" }), { target: { value: "retry fixture" } });
  fireEvent.click(screen.getByRole("button", { name: "发送" }));
  await screen.findByRole("alert");
  fireEvent.click(screen.getByRole("button", { name: "重试" }));
  await screen.findByText("retried reply");
  expect(complete).toHaveBeenCalledTimes(2);
});

test("does not render a late response after cancellation", async () => {
  let resolveReply: (value: string) => void = () => {};
  const complete = vi.fn(() => new Promise<string>(resolve => { resolveReply = resolve; }));
  render(<ChatPage client={client({ complete })} />);
  await screen.findByRole("combobox", { name: "聊天模型" });
  fireEvent.change(screen.getByRole("textbox", { name: "聊天消息" }), { target: { value: "cancel fixture" } });
  fireEvent.click(screen.getByRole("button", { name: "发送" }));
  fireEvent.click(screen.getByRole("button", { name: "取消" }));
  resolveReply("late fixture reply");
  await waitFor(() => expect(screen.queryByText("late fixture reply")).toBeNull());
  expect(screen.queryByText("正在回复…")).toBeNull();
});

test("prompts for login when the account backend rejects model loading", async () => {
  const onLogin = vi.fn();
  render(<ChatPage client={client({ models: vi.fn().mockRejectedValue({ code: "account_unauthorized" }) })} onLogin={onLogin} />);
  expect(await screen.findByText("登录后即可与 AI 对话。")).toBeDefined();
  fireEvent.click(screen.getByRole("button", { name: "登录使用 AI" }));
  expect(onLogin).toHaveBeenCalledOnce();
});
