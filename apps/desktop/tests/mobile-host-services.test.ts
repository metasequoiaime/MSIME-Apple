import { expect, test, vi } from "vitest";
import {
  createMobileHostServices,
  type MobileHostServiceDependencies,
} from "../src/mobile-host-services";

function dependencies() {
  const invokeMock = vi.fn(async () => undefined);
  const listenMock = vi.fn(async () => vi.fn());
  const navigateVoice = vi.fn();
  const value: MobileHostServiceDependencies = {
    invoke: invokeMock as unknown as MobileHostServiceDependencies["invoke"],
    listen: listenMock as unknown as MobileHostServiceDependencies["listen"],
    navigateVoice,
  };
  return { value, invokeMock, listenMock, navigateVoice };
}

test("Android and iOS share Tauri account, community, AI and skin services", async () => {
  const androidDependencies = dependencies();
  const iosDependencies = dependencies();
  const android = createMobileHostServices("android", androidDependencies.value);
  const ios = createMobileHostServices("ios", iosDependencies.value);

  for (const services of [android, ios]) {
    expect(services.account).toBeDefined();
    expect(services.chat).toBeDefined();
    expect(services.aiAssistant).toBeDefined();
    expect(services.communitySkins).toBeDefined();
    expect(services.communityResources).toBeDefined();
    expect(services.aiSkins).toBeDefined();
    expect(services.customSkinLibrary).toBeDefined();
    expect(services.touchKeyboardSchemes).toBe(true);
    expect(services.customTouchKeyboardSkins).toBe(true);
    expect(services.mobileKeyboardFeedback).toBeDefined();
  }

  await android.communitySkins?.list(0, "杉");
  await ios.communitySkins?.list(0, "杉");
  expect(androidDependencies.invokeMock).toHaveBeenCalledWith("community_skin_list", { offset: 0, search: "杉" });
  expect(iosDependencies.invokeMock).toHaveBeenCalledWith("community_skin_list", { offset: 0, search: "杉" });
});

test("platform-only mobile actions stay explicit", async () => {
  const androidDependencies = dependencies();
  const iosDependencies = dependencies();
  const android = createMobileHostServices("android", androidDependencies.value);
  const ios = createMobileHostServices("ios", iosDependencies.value);

  expect(android.account?.appleLogin).toBeUndefined();
  expect(android.openVoice).toBeUndefined();
  expect(android.home?.openKeyboard).toBeDefined();
  expect(android.home?.showInputMethodPicker).toBeDefined();
  expect(ios.account?.appleLogin).toBeDefined();
  expect(ios.openVoice).toBeDefined();
  expect(ios.home).toBeUndefined();

  await android.openSystemKeyboardSettings?.();
  await ios.openSystemKeyboardSettings?.();
  await ios.account?.appleLogin?.();
  await ios.openVoice?.();

  expect(androidDependencies.invokeMock).toHaveBeenCalledWith("android_open_input_method_settings");
  expect(iosDependencies.invokeMock).toHaveBeenCalledWith("open_system_keyboard_settings");
  expect(iosDependencies.invokeMock).toHaveBeenCalledWith("account_apple_login");
  expect(iosDependencies.navigateVoice).toHaveBeenCalledOnce();
});
