export type Version = { display: string; parts: number[] };

export type UpdateManifest = {
  version?: unknown;
  releaseUrl?: unknown;
  installerName?: unknown;
  installerSha256?: unknown;
  signed?: unknown;
};

export type GitHubRelease = {
  tag_name?: unknown;
  html_url?: unknown;
  draft?: unknown;
  prerelease?: unknown;
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

function isHttpsUrl(value: string): boolean {
  return value.startsWith("https://") && !/[\s"'`<>\\|&]/.test(value);
}

export function validateManifest(
  manifest: UpdateManifest,
  releasesPageUrl: string,
): ValidatedUpdate | null {
  if (typeof manifest.version !== "string" || typeof manifest.releaseUrl !== "string") return null;
  if (!isHttpsUrl(releasesPageUrl) || !isHttpsUrl(manifest.releaseUrl)) return null;
  if (
    manifest.releaseUrl !== releasesPageUrl &&
    !manifest.releaseUrl.startsWith(`${releasesPageUrl}/`)
  )
    return null;
  const version = parseVersion(manifest.version);
  if (!version) return null;
  return {
    version,
    releaseUrl: manifest.releaseUrl,
    installerName:
      typeof manifest.installerName === "string" &&
      installerNamePattern.test(manifest.installerName)
        ? manifest.installerName
        : null,
    installerSha256:
      typeof manifest.installerSha256 === "string" && sha256Pattern.test(manifest.installerSha256)
        ? manifest.installerSha256
        : null,
    signed: typeof manifest.signed === "boolean" ? manifest.signed : null,
  };
}

export function validateGitHubRelease(
  release: GitHubRelease,
  releasesPageUrl: string,
): ValidatedUpdate | null {
  if (typeof release.tag_name !== "string" || typeof release.html_url !== "string") return null;
  if (!isHttpsUrl(releasesPageUrl) || !isHttpsUrl(release.html_url)) return null;
  if (!release.html_url.startsWith(`${releasesPageUrl}/tag/`)) return null;
  const version = parseVersion(release.tag_name);
  if (!version) return null;
  return {
    version,
    releaseUrl: release.html_url,
    installerName: null,
    installerSha256: null,
    signed: null,
  };
}

/**
 * The newest published release of one platform, from the repository's release list.
 *
 * Every platform publishes to the same repository under its own tag prefix (`windows-v1.2.0`, `linux-v1.2.0`; see `.github/workflows/release-*.yml`), so the repository's single "latest" release usually belongs to another platform, and its prefixed tag is not a version. Drafts and prereleases are not offered.
 */
export function selectPlatformRelease(
  releases: readonly GitHubRelease[],
  platform: string,
  releasesPageUrl: string,
): ValidatedUpdate | null {
  const prefix = `${platform}-`;
  let newest: ValidatedUpdate | null = null;
  for (const release of releases) {
    if (!release || typeof release !== "object") continue;
    if (release.draft === true || release.prerelease === true) continue;
    if (typeof release.tag_name !== "string" || !release.tag_name.startsWith(prefix)) continue;
    const update = validateGitHubRelease(
      { tag_name: release.tag_name.slice(prefix.length), html_url: release.html_url },
      releasesPageUrl,
    );
    if (update && (!newest || compareVersions(update.version, newest.version) > 0)) newest = update;
  }
  return newest;
}

export function describeInstallerTrust(update: ValidatedUpdate): {
  warning: string | null;
  verify: { command: string; sha256: string } | null;
} {
  const name = update.installerName ?? "MetasequoiaIME_Setup_v<版本>.exe";
  return {
    warning: update.signed === false ? "该版本未经代码签名，请务必核对下面的校验值。" : null,
    verify: update.installerSha256
      ? { command: `Get-FileHash .\\${name} -Algorithm SHA256`, sha256: update.installerSha256 }
      : null,
  };
}
