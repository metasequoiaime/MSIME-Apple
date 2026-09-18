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
    $global:NoticeProbeFail = $false
    function global:git {
        $global:LASTEXITCODE = 0
        if ($args[2] -eq 'rev-parse') { return ('a' * 40) }
        if ($args[2] -ne 'show' -or $args[3] -notlike (('a' * 40) + ':*')) { throw 'Unexpected git notice request' }
        if ($global:NoticeProbeFail) { $global:LASTEXITCODE = 1; return }
        return "synthetic committed notice $($args[3])"
    }
    $entry = Join-Path $PSScriptRoot '../Collect-Notices.ps1'
    & $entry -RepoRoot $root -DependencyPrefixes @($prefix) -SupplementalNotices @($supplement)
    $output = Join-Path $root 'target/windows-notices/THIRD_PARTY_NOTICES.txt'
    $first = [IO.File]::ReadAllText($output)
    if (-not $first.Contains('synthetic extra notice') -or -not $first.Contains('synthetic dependency copyright') -or
        -not $first.Contains('helpcode/NOTICE.md') -or $first.Contains($root)) { throw 'Notice content/provenance mismatch' }
    & $entry -RepoRoot $root -DependencyPrefixes @($prefix) -SupplementalNotices @($supplement)
    if ([IO.File]::ReadAllText($output) -ne $first) { throw 'Notice generation is not deterministic' }
    foreach ($failure in @('git', 'license')) {
        $global:NoticeProbeFail = $failure -eq 'git'
        if ($failure -eq 'license') { [IO.File]::WriteAllText($license, '') }
        $rejected = $false
        try { & $entry -RepoRoot $root -DependencyPrefixes @($prefix) } catch { $rejected = $true }
        if (-not $rejected -or [IO.File]::ReadAllText($output) -ne $first) { throw 'Failed collection damaged previous notices' }
    }
    Write-Output 'Notice provenance, deterministic output and failed-input preservation passed'
} finally {
    Remove-Item Function:/git -ErrorAction SilentlyContinue
    Remove-Variable NoticeProbeFail -Scope Global -ErrorAction SilentlyContinue
    if (Test-Path $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
