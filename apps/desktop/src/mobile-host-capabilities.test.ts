import { expect, test } from "vitest";
import { cloudDictionaryCapabilities, isMobileHost } from "./mobile-host-capabilities";

test("mobile capability checks use the declared host platform", () => {
  expect(isMobileHost("android")).toBe(true);
  expect(isMobileHost("ios")).toBe(true);
  expect(isMobileHost("macos")).toBe(false);
  expect(isMobileHost(undefined)).toBe(false);
});

test("cloud dictionary snapshots distinguish mobile queue and macOS native paths", () => {
  expect(cloudDictionaryCapabilities("android")).toEqual({ snapshot: true, snapshotNative: false });
  expect(cloudDictionaryCapabilities("ios")).toEqual({ snapshot: true, snapshotNative: false });
  expect(cloudDictionaryCapabilities("macos")).toEqual({ snapshot: true, snapshotNative: true });
  expect(cloudDictionaryCapabilities("windows")).toEqual({ snapshot: false, snapshotNative: false });
});
