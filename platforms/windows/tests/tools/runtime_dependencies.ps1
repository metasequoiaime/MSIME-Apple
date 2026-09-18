$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'pe_fixture.ps1')
$root = Join-Path ([IO.Path]::GetTempPath()) ('msime-runtime-deps-' + [Guid]::NewGuid())
$prefix = Join-Path $root 'dependency prefix'
$destination = Join-Path $root 'output'
$copy = Join-Path $PSScriptRoot '../Copy-RuntimeDependencies.ps1'
try {
    New-Item -ItemType Directory -Force $prefix, $destination | Out-Null
    & $copy -DependencyPrefix $prefix -Destination $destination -Architecture x64
    Write-PEFixture (Join-Path $prefix 'bin/first.dll') x64 dll
    Write-PEFixture (Join-Path $prefix 'debug/bin/debug-only.dll') x64 dll
    [IO.File]::WriteAllText((Join-Path $prefix 'bin/notes.txt'), 'synthetic excluded data')
    & $copy -DependencyPrefix $prefix -Destination $destination -Architecture x64
    & $copy -DependencyPrefix $prefix -Destination $destination -Architecture x64
    if (@(Get-ChildItem $destination).Count -ne 1 -or -not (Test-Path (Join-Path $destination 'first.dll'))) {
        throw 'Dependency selection mismatch'
    }
    Write-PEFixture (Join-Path $prefix 'bin/second.dll') x64 dll
    Write-PEFixture (Join-Path $prefix 'bin/wrong.dll') x86 dll
    $rejected = $false
    try { & $copy -DependencyPrefix $prefix -Destination $destination -Architecture x64 } catch { $rejected = $true }
    if (-not $rejected -or (Test-Path (Join-Path $destination 'second.dll'))) { throw 'Wrong architecture did not stop preflight' }
    Remove-Item -LiteralPath (Join-Path $prefix 'bin/wrong.dll')
    [IO.File]::WriteAllText((Join-Path $destination 'second.dll'), 'synthetic existing sentinel')
    $rejected = $false
    try { & $copy -DependencyPrefix $prefix -Destination $destination -Architecture x64 } catch { $rejected = $true }
    if (-not $rejected -or [IO.File]::ReadAllText((Join-Path $destination 'second.dll')) -ne 'synthetic existing sentinel') {
        throw 'Conflicting destination replaced'
    }
    Write-Output 'Runtime dependency selection, architecture preflight and conflict preservation passed'
} finally {
    if (Test-Path $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
