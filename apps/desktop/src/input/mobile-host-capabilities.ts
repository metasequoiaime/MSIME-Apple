import type { HostPlatform } from "@msime/ui";

export function isMobileHost(platform: HostPlatform | undefined): boolean {
  return platform === "android" || platform === "ios";
}

export function cloudDictionaryCapabilities(platform: HostPlatform | undefined): {
  snapshot: boolean;
  snapshotNative: boolean;
} {
  return {
    snapshot: isMobileHost(platform) || platform === "macos",
    snapshotNative: platform === "macos",
  };
}
