export type Version = { display: string; parts: number[] };

export type UpdateManifest = {
  version?: unknown;
  releaseUrl?: unknown;
  installerName?: unknown;
  installerSha256?: unknown;
  signed?: unknown;
};

export type ValidatedUpdate = {
  version: Version;
  releaseUrl: string;
  installerName: string | null;
  installerSha256: string | null;
  signed: boolean | null;
};

export function parseVersion(value: string): Version | null {
  const match = value.trim().match(/^v?(\d+(?:\.\d+)*)(?:[-+].*)?$/i);
  if (!match?.[1]) return null;
  return { display: match[1], parts: match[1].split(".").map(Number) };
}

export function compareVersions(left: Version, right: Version): number {
  const length = Math.max(left.parts.length, right.parts.length);
  for (let index = 0; index < length; index += 1) {
    const difference = (left.parts[index] ?? 0) - (right.parts[index] ?? 0);
    if (difference !== 0) return difference;
  }
  return 0;
}

const installerNamePattern = /^MetasequoiaIME_Setup_v[\w.-]+\.exe$/i;
const sha256Pattern = /^[0-9a-f]{64}$/i;

export function validateManifest(manifest: UpdateManifest, releasesPageUrl: string): ValidatedUpdate | null {
  if (typeof manifest.version !== "string" || typeof manifest.releaseUrl !== "string") return null;
  if (manifest.releaseUrl !== releasesPageUrl && !manifest.releaseUrl.startsWith(`${releasesPageUrl}/`)) return null;
  const version = parseVersion(manifest.version);
  if (!version) return null;
  return {
    version,
    releaseUrl: manifest.releaseUrl,
    installerName: typeof manifest.installerName === "string" && installerNamePattern.test(manifest.installerName) ? manifest.installerName : null,
    installerSha256: typeof manifest.installerSha256 === "string" && sha256Pattern.test(manifest.installerSha256) ? manifest.installerSha256 : null,
    signed: typeof manifest.signed === "boolean" ? manifest.signed : null,
  };
}

export function describeInstallerTrust(update: ValidatedUpdate): { warning: string | null; verify: { command: string; sha256: string } | null } {
  const name = update.installerName ?? "MetasequoiaIME_Setup_v<版本>.exe";
  return {
    warning: update.signed === false ? "该版本未经代码签名，请务必核对下面的校验值。" : null,
    verify: update.installerSha256 ? { command: `Get-FileHash .\\${name} -Algorithm SHA256`, sha256: update.installerSha256 } : null,
  };
}
