import { invoke } from "@tauri-apps/api/core";
import type { ApiCredentialTestResult, ApiCredentialTestService } from "@msime/ui";

/** Route credential probes through the platform-bounded Tauri command. */
export function testDesktopApiCredential(
  service: ApiCredentialTestService,
  config: Record<string, unknown>,
): Promise<ApiCredentialTestResult> {
  return invoke<ApiCredentialTestResult>("test_api_credential", { service, config });
}
