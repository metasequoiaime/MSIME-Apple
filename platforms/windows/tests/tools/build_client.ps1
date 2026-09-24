# Test real orchestration with command probes; no compiler, signer or installer runs.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('msime-client-build-' + [Guid]::NewGuid())
$originalLocation = (Get-Location).Path
$originalPrefix = $env:CMAKE_PREFIX_PATH
$originalTarget = $env:CARGO_TARGET_DIR
$originalDebug = $env:CARGO_PROFILE_RELEASE_DEBUG
. (Join-Path $PSScriptRoot 'pe_fixture.ps1')
try {
    $desktopSymbols = Join-Path $fixture 'target/x86_64-pc-windows-msvc/release/msime_desktop.pdb'
    New-Item -ItemType Directory -Force (Split-Path -Parent $desktopSymbols) | Out-Null
    [IO.File]::WriteAllText($desktopSymbols, 'synthetic symbols')
    $settingsSymbols = Join-Path $fixture 'target/windows-full/x64/bin/MSIME.Settings.pdb'
    New-Item -ItemType Directory -Force (Split-Path -Parent $settingsSymbols) | Out-Null
    [IO.File]::WriteAllText($settingsSymbols, 'synthetic WinUI symbols')
    foreach ($arch in @('x86', 'x64')) {
        foreach ($dll in @('MetasequoiaImeTsf.dll', 'msime_host_api.dll')) {
            Write-PEFixture (Join-Path $fixture "target/windows-full/$arch/bin/$dll") $arch dll
        }
    }
    foreach ($exe in @('MetasequoiaImeServer.exe', 'MetasequoiaImeWatchdog.exe', 'msime-client-prepare.exe',
        'MetasequoiaImeDictionaryReplay.exe', 'msime-client-settings.exe', 'MSIME Client Preview.exe')) {
        Write-PEFixture (Join-Path $fixture "target/windows-full/x64/bin/$exe") x64 exe
    }
    foreach ($relative in @('Cargo.toml', 'vendor/MSIME-Engine/CMakeLists.txt',
        'platforms/windows/CMakeLists.txt', 'platforms/windows/tsf/CMakeLists.txt',
        'platforms/windows/settings/MSIME.Settings.vcxproj', 'apps/desktop/package.json')) {
        $path = Join-Path $fixture $relative
        New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
        [IO.File]::WriteAllText($path, 'synthetic')
    }
    $x64 = Join-Path $fixture 'deps x64'
    $x86 = Join-Path $fixture 'deps x86'
    New-Item -ItemType Directory $x64, $x86 | Out-Null
    Write-PEFixture (Join-Path $x64 'bin/synthetic-runtime.dll') x64 dll
    Write-PEFixture (Join-Path $x86 'bin/synthetic-runtime.dll') x86 dll
    function global:Invoke-ClientCommandProbe {
        param([string]$Name, [object[]]$Values)
        $global:ClientBuildCalls.Add(@{ Name = $Name; Values = $Values; Prefix = $env:CMAKE_PREFIX_PATH })
        $global:LASTEXITCODE = if ($global:ClientBuildCalls.Count -eq $global:ClientBuildFailAt) { 19 } else { 0 }
    }
    function global:cargo { Invoke-ClientCommandProbe cargo $args }
    function global:cmake { Invoke-ClientCommandProbe cmake $args }
    function global:pnpm { Invoke-ClientCommandProbe pnpm $args }
    function global:msbuild { Invoke-ClientCommandProbe msbuild $args }
    $entry = Join-Path $PSScriptRoot '../../Build-Client.ps1'
    $global:ClientBuildCalls = [Collections.Generic.List[object]]::new()
    $global:ClientBuildFailAt = 0
    & $entry -RepoRoot $fixture -X64Dependencies $x64 -X86Dependencies $x86 -TargetVersion '2026.9.1'
    $count = $global:ClientBuildCalls.Count
    $desktopCall = @($global:ClientBuildCalls | Where-Object { $_.Name -eq 'pnpm' -and $_.Values -contains 'tauri' })[0]
    $desktopArgs = $desktopCall.Values
    $configIndex = [Array]::IndexOf($desktopArgs, '--config')
    if ($configIndex -lt 0 -or (Get-Content -LiteralPath $desktopArgs[$configIndex + 1] -Raw | ConvertFrom-Json).version -ne '2026.9.1') {
        throw 'Tauri version override missing or incorrect'
    }
    foreach ($arch in @('x86', 'x64')) {
        & (Join-Path $PSScriptRoot '../../Test-PortableExecutable.ps1') `
            -LiteralPath (Join-Path $fixture "target/windows-full/$arch/bin/synthetic-runtime.dll") -Architecture $arch -Kind dll
    }
    if ($count -ne 18) { throw "Unexpected build stage count: $count" }
    if ($global:ClientBuildCalls[17].Values[-1] -ne (Join-Path $fixture 'target/windows-full/x64/bin/MSIME Client Preview.pdb')) {
        throw 'Desktop PDB did not follow staged executable name'
    }
    foreach ($index in @(0, 1, 2, 3, 4, 5, 6, 7, 8, 13, 14, 15, 16, 17)) {
        if ($global:ClientBuildCalls[$index].Prefix -ne $x64) { throw 'Incorrect x64 dependency scope' }
    }
    foreach ($index in @(9, 10, 11, 12)) {
        if ($global:ClientBuildCalls[$index].Prefix -ne $x86) { throw 'Incorrect x86 dependency scope' }
    }
    if ($global:ClientBuildCalls[1].Values -notcontains 'x64' -or
        $global:ClientBuildCalls[1].Values -notcontains '-DMSIME_SERVER_UIACCESS=ON' -or
        $global:ClientBuildCalls[10].Values -contains '-DMSIME_SERVER_UIACCESS=ON' -or
        $global:ClientBuildCalls[10].Values -notcontains 'Win32' -or
        $global:ClientBuildCalls[11].Values -notcontains 'msime-tsf' -or
        $global:ClientBuildCalls[15].Values -notcontains '--no-bundle' -or
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
    $global:ClientBuildCalls.Clear()
    $global:ClientBuildFailAt = 0
    foreach ($invalid in @('1.2', '01.2.3', '65536.0.0', '1.2.3.4', '1.2.3-beta', 'not-a-version')) {
        $rejected = $false
        try { & $entry -RepoRoot $fixture -X64Dependencies $x64 -X86Dependencies $x86 -TargetVersion $invalid }
        catch { $rejected = $_.Exception.Message -like 'TargetVersion must*' }
        if (-not $rejected -or $global:ClientBuildCalls.Count -ne 0) { throw 'Invalid version reached build tools' }
    }
    & $entry -RepoRoot $fixture -X64Dependencies $x64 -X86Dependencies $x86
    if ($global:ClientBuildCalls[15].Values -contains '--config') { throw 'Development version was overridden' }
    $global:ClientBuildCalls.Clear()
    Remove-Item -LiteralPath $desktopSymbols
    $rejected = $false
    try { & $entry -RepoRoot $fixture -X64Dependencies $x64 -X86Dependencies $x86 }
    catch { $rejected = $_.Exception.Message -eq 'Expected one Tauri desktop PDB output' }
    if (-not $rejected) { throw 'Missing desktop symbols accepted' }
    [IO.File]::WriteAllText($desktopSymbols, 'synthetic symbols')
    $alternateSymbols = Join-Path (Split-Path -Parent $desktopSymbols) 'msime-desktop.pdb'
    [IO.File]::WriteAllText($alternateSymbols, 'synthetic alternate symbols')
    $rejected = $false
    try { & $entry -RepoRoot $fixture -X64Dependencies $x64 -X86Dependencies $x86 }
    catch { $rejected = $_.Exception.Message -eq 'Expected one Tauri desktop PDB output' }
    if (-not $rejected) { throw 'Ambiguous desktop symbols accepted' }
    Remove-Item -LiteralPath $alternateSymbols
    Write-PEFixture (Join-Path $fixture 'target/windows-full/x86/bin/msime_host_api.dll') x64 dll
    $rejected = $false
    try { & $entry -RepoRoot $fixture -X64Dependencies $x64 -X86Dependencies $x86 }
    catch { $rejected = $_.Exception.Message -eq 'PE architecture mismatch' }
    if (-not $rejected) { throw 'Build accepted mixed-architecture output' }
    if ((Get-Location).Path -ne $originalLocation -or $env:CMAKE_PREFIX_PATH -ne $originalPrefix -or
        $env:CARGO_TARGET_DIR -ne $originalTarget -or $env:CARGO_PROFILE_RELEASE_DEBUG -ne $originalDebug) {
        throw 'PE verification failure leaked caller environment'
    }
    Write-Output 'Client build orchestration: targets, dependency scopes, failure stages and PE gate passed'
} finally {
    Remove-Item Function:/cargo, Function:/cmake, Function:/pnpm, Function:/msbuild, Function:/Invoke-ClientCommandProbe -ErrorAction SilentlyContinue
    Remove-Variable ClientBuildCalls, ClientBuildFailAt -Scope Global -ErrorAction SilentlyContinue
    if (Test-Path $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
