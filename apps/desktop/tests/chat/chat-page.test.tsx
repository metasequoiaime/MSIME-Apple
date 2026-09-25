// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { ChatPage, type ChatClient, type ChatMessage } from "@msime/ui";
import { answerConfirm } from "../support/confirm";

afterEach(cleanup);

function client(overrides: Partial<ChatClient> = {}): ChatClient {
  return {
    models: async () => ({
      data: [{ id: "fixture-chat" }, { id: "fixture-fast" }],
      defaultModel: "fixture-chat",
    }),
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
  render(<ChatPage client={client({ complete })} />);

  const model = await screen.findByRole("combobox", { name: "聊天模型" });
  expect((model as HTMLSelectElement).value).toBe("fixture-chat");
  fireEvent.change(model, { target: { value: "fixture-fast" } });
  fireEvent.change(screen.getByRole("textbox", { name: "聊天消息" }), {
    target: { value: "fixture prompt" },
  });
  fireEvent.click(screen.getByRole("button", { name: "发送" }));
  await screen.findByText("fixture reply");
  expect(complete).toHaveBeenCalledTimes(1);

  fireEvent.click(screen.getByRole("button", { name: "新对话" }));
  // The conversation survives until the question is answered.
  expect(screen.queryByText("fixture prompt")).toBeTruthy();
  await answerConfirm("confirm");
  expect(screen.queryByText("fixture prompt")).toBeNull();
  expect(screen.queryByText("fixture reply")).toBeNull();
});

test("a message over the host's byte bound is refused before it is sent", async () => {
  const complete = vi.fn(async () => "fixture reply");
  render(<ChatPage client={client({ complete })} />);
  await screen.findByRole("combobox", { name: "聊天模型" });
  // 6,000 CJK characters are well under maxLength but 18,000 UTF-8 bytes.
  const long = "测".repeat(6_000);
  fireEvent.change(screen.getByRole("textbox", { name: "聊天消息" }), {
    target: { value: long },
  });
  fireEvent.click(screen.getByRole("button", { name: "发送" }));
  expect((await screen.findByRole("alert")).textContent).toContain("消息过长，请精简后再发送。");
  expect(complete).not.toHaveBeenCalled();
  // The draft is kept so it can be shortened.
  expect((screen.getByRole("textbox", { name: "聊天消息" }) as HTMLTextAreaElement).value).toBe(
    long,
  );
});

test("shows an actionable error and retries the latest user message", async () => {
  const complete = vi.fn<(messages: ChatMessage[], model: string) => Promise<string>>();
  complete
    .mockRejectedValueOnce({ code: "account_unavailable" })
    .mockResolvedValueOnce("retried reply");
  render(<ChatPage client={client({ complete })} />);
  await screen.findByRole("combobox", { name: "聊天模型" });
  fireEvent.change(screen.getByRole("textbox", { name: "聊天消息" }), {
    target: { value: "retry fixture" },
  });
  fireEvent.click(screen.getByRole("button", { name: "发送" }));
  await screen.findByRole("alert");
  fireEvent.click(screen.getByRole("button", { name: "重试" }));
  await screen.findByText("retried reply");
  expect(complete).toHaveBeenCalledTimes(2);
});

test("does not render a late response after cancellation", async () => {
  let resolveReply: (value: string) => void = () => {};
  const complete = vi.fn(
    () =>
      new Promise<string>((resolve) => {
        resolveReply = resolve;
      }),
  );
  render(<ChatPage client={client({ complete })} />);
  await screen.findByRole("combobox", { name: "聊天模型" });
  fireEvent.change(screen.getByRole("textbox", { name: "聊天消息" }), {
    target: { value: "cancel fixture" },
  });
  fireEvent.click(screen.getByRole("button", { name: "发送" }));
  fireEvent.click(screen.getByRole("button", { name: "取消" }));
  resolveReply("late fixture reply");
  await waitFor(() => expect(screen.queryByText("late fixture reply")).toBeNull());
  expect(screen.queryByText("正在回复…")).toBeNull();
});

test("ignores a late model catalog after the chat page unmounts", async () => {
  let resolveModels: (value: { data: { id: string }[]; defaultModel: string }) => void = () => {};
  const models = vi.fn(
    () =>
      new Promise<{ data: { id: string }[]; defaultModel: string }>((resolve) => {
        resolveModels = resolve;
      }),
  );
  const view = render(<ChatPage client={client({ models })} />);
  view.unmount();
  resolveModels({ data: [{ id: "late-model" }], defaultModel: "late-model" });
  await Promise.resolve();
});

test("prompts for login when the account backend rejects model loading", async () => {
  const onLogin = vi.fn();
  render(
    <ChatPage
      client={client({ models: vi.fn().mockRejectedValue({ code: "account_unauthorized" }) })}
      onLogin={onLogin}
    />,
  );
  expect(await screen.findByText("登录后即可与 AI 对话。")).toBeDefined();
  const composer = screen.getByRole("textbox", { name: "聊天消息" });
  expect((composer as HTMLTextAreaElement).disabled).toBe(false);
  fireEvent.change(composer, { target: { value: "未登录也能试键盘" } });
  fireEvent.click(screen.getByRole("button", { name: "发送" }));
  expect(onLogin).toHaveBeenCalledOnce();
  expect((composer as HTMLTextAreaElement).value).toBe("未登录也能试键盘");
  fireEvent.click(screen.getByRole("button", { name: "登录使用 AI" }));
  expect(onLogin).toHaveBeenCalledTimes(2);
});

test("can autofocus the composer for the mobile keyboard tryout", async () => {
  render(<ChatPage client={client()} autoFocus />);
  const composer = await screen.findByRole("textbox", { name: "聊天消息" });
  await waitFor(() => expect(document.activeElement).toBe(composer));
});
