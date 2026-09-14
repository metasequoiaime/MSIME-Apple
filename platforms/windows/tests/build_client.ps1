# Test real orchestration with command probes; no compiler, signer or installer runs.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('msime-client-build-' + [Guid]::NewGuid())
$originalLocation = (Get-Location).Path
$originalPrefix = $env:CMAKE_PREFIX_PATH
$originalTarget = $env:CARGO_TARGET_DIR
$originalDebug = $env:CARGO_PROFILE_RELEASE_DEBUG
try {
    foreach ($relative in @('Cargo.toml', 'vendor/MSIME-Engine/CMakeLists.txt',
        'platforms/windows/CMakeLists.txt', 'platforms/windows/tsf/CMakeLists.txt', 'apps/desktop/package.json')) {
        $path = Join-Path $fixture $relative
        New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
        [IO.File]::WriteAllText($path, 'synthetic')
    }
    $x64 = Join-Path $fixture 'deps x64'
    $x86 = Join-Path $fixture 'deps x86'
    New-Item -ItemType Directory $x64, $x86 | Out-Null
    function global:Invoke-ClientCommandProbe {
        param([string]$Name, [object[]]$Values)
        $global:ClientBuildCalls.Add(@{ Name = $Name; Values = $Values; Prefix = $env:CMAKE_PREFIX_PATH })
        $global:LASTEXITCODE = if ($global:ClientBuildCalls.Count -eq $global:ClientBuildFailAt) { 19 } else { 0 }
    }
    function global:cargo { Invoke-ClientCommandProbe cargo $args }
    function global:cmake { Invoke-ClientCommandProbe cmake $args }
    function global:pnpm { Invoke-ClientCommandProbe pnpm $args }
    $entry = Join-Path $PSScriptRoot '../Build-Client.ps1'
    $global:ClientBuildCalls = [Collections.Generic.List[object]]::new()
    $global:ClientBuildFailAt = 0
    & $entry -RepoRoot $fixture -X64Dependencies $x64 -X86Dependencies $x86
    $count = $global:ClientBuildCalls.Count
    if ($count -ne 15) { throw "Unexpected build stage count: $count" }
    foreach ($index in @(0, 1, 2, 3, 4, 5, 6, 11, 12, 13, 14)) {
        if ($global:ClientBuildCalls[$index].Prefix -ne $x64) { throw 'Incorrect x64 dependency scope' }
    }
    foreach ($index in @(7, 8, 9, 10)) {
        if ($global:ClientBuildCalls[$index].Prefix -ne $x86) { throw 'Incorrect x86 dependency scope' }
    }
    if ($global:ClientBuildCalls[1].Values -notcontains 'x64' -or
        $global:ClientBuildCalls[8].Values -notcontains 'Win32' -or
        $global:ClientBuildCalls[9].Values -notcontains 'msime-tsf' -or
        $global:ClientBuildCalls[13].Values -notcontains '--no-bundle' -or
        $global:ClientBuildCalls[2].Values -notcontains 'RelWithDebInfo') { throw 'Build target mismatch' }
    for ($failure = 1; $failure -le $count; $failure++) {
        $global:ClientBuildCalls.Clear()
        $global:ClientBuildFailAt = $failure
        $rejected = $false
        try { & $entry -RepoRoot $fixture -X64Dependencies $x64 -X86Dependencies $x86 }
        catch { $rejected = $_.Exception.Message -match 'Client build command failed: .* \(19\)' }
        if (-not $rejected -or $global:ClientBuildCalls.Count -ne $failure) { throw 'Build continued after failure' }
        if ((Get-Location).Path -ne $originalLocation -or $env:CMAKE_PREFIX_PATH -ne $originalPrefix -or
            $env:CARGO_TARGET_DIR -ne $originalTarget -or
            $env:CARGO_PROFILE_RELEASE_DEBUG -ne $originalDebug) { throw 'Build leaked caller environment' }
    }
    Write-Output 'Client build orchestration: targets, dependency scopes and all failure stages passed'
} finally {
    Remove-Item Function:/cargo, Function:/cmake, Function:/pnpm, Function:/Invoke-ClientCommandProbe -ErrorAction SilentlyContinue
    Remove-Variable ClientBuildCalls, ClientBuildFailAt -Scope Global -ErrorAction SilentlyContinue
    if (Test-Path $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
