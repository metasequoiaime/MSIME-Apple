$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Join-Path ([IO.Path]::GetTempPath()) ('msime-notices-' + [Guid]::NewGuid())
try {
    $prefix = Join-Path $root 'deps'
    New-Item -ItemType Directory -Force (Join-Path $prefix 'share/synthetic-lib') | Out-Null
    $license = Join-Path $prefix 'share/synthetic-lib/copyright'
    [IO.File]::WriteAllText($license, 'synthetic dependency copyright')
    $supplement = Join-Path $root 'extra.txt'
    [IO.File]::WriteAllText($supplement, 'synthetic extra notice')
    # Collect-Notices.ps1 reads a prepared Engine tree whose marker names the commit engine-lock.json pins, plus the OpenCC license compiled into the host library.
    $pin = 'a' * 40
    [IO.File]::WriteAllText((Join-Path $root 'engine-lock.json'), "{ `"commit`": `"$pin`" }")
    $engine = Join-Path $root 'vendor/MSIME-Engine'
    $marker = Join-Path $engine '.msime-engine-lock'
    foreach ($relative in @('NOTICE.md', 'LICENSE', 'dictionary/NOTICE.md', 'dictionary/makecikudb/LICENSE',
        'helpcode/NOTICE.md', 'voice/LICENSE', 'handwriting/models/HandwritingModel-LICENSE.txt',
        'handwriting/third_party/zinnia/Zinnia-LICENSE.txt')) {
        $path = Join-Path $engine $relative
        New-Item -ItemType Directory -Force (Split-Path -Parent $path) | Out-Null
        [IO.File]::WriteAllText($path, "synthetic committed notice $relative")
    }
    [IO.File]::WriteAllText($marker, "$pin`nsynthetic overlay digest")
    $opencc = Join-Path $root 'crates/client-core/data/opencc/LICENSE'
    New-Item -ItemType Directory -Force (Split-Path -Parent $opencc) | Out-Null
    [IO.File]::WriteAllText($opencc, 'synthetic OpenCC license')
    $entry = Join-Path $PSScriptRoot '../../Collect-Notices.ps1'
    & $entry -RepoRoot $root -DependencyPrefixes @($prefix) -SupplementalNotices @($supplement)
    $output = Join-Path $root 'target/windows-notices/THIRD_PARTY_NOTICES.txt'
    $first = [IO.File]::ReadAllText($output)
    if (-not $first.Contains('synthetic extra notice') -or -not $first.Contains('synthetic dependency copyright') -or
        -not $first.Contains("MSIME-Engine/helpcode/NOTICE.md @ $pin") -or -not $first.Contains('synthetic OpenCC license') -or
        $first.Contains($root)) { throw 'Notice content/provenance mismatch' }
    & $entry -RepoRoot $root -DependencyPrefixes @($prefix) -SupplementalNotices @($supplement)
    if ([IO.File]::ReadAllText($output) -ne $first) { throw 'Notice generation is not deterministic' }
    foreach ($failure in @('marker', 'license')) {
        # An Engine tree prepared from another commit is refused; the marker is restored before the next case.
        if ($failure -eq 'marker') { [IO.File]::WriteAllText($marker, ('b' * 40)) }
        if ($failure -eq 'license') {
            [IO.File]::WriteAllText($marker, "$pin`nsynthetic overlay digest")
            [IO.File]::WriteAllText($license, '')
        }
        $rejected = $false
        try { & $entry -RepoRoot $root -DependencyPrefixes @($prefix) } catch { $rejected = $true }
        if (-not $rejected -or [IO.File]::ReadAllText($output) -ne $first) { throw 'Failed collection damaged previous notices' }
    }
    Write-Output 'Notice provenance, deterministic output and failed-input preservation passed'
} finally {
    if (Test-Path $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
