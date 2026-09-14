$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('msime-package-' + [Guid]::NewGuid())
function Write-Fixture([string]$Relative, [string]$Text = 'fixture') {
    $path = Join-Path $fixture $Relative
    New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
    [IO.File]::WriteAllText($path, $Text)
}
try {
    $installer = Join-Path $fixture 'installer'
    New-Item -ItemType Directory -Force -Path $installer | Out-Null
    Copy-Item (Join-Path $PSScriptRoot '../Prepare-PackageFiles.ps1') $installer
    Copy-Item (Join-Path $PSScriptRoot '../Get-VerifiedDesktopResources.ps1') $installer
    Copy-Item (Join-Path $PSScriptRoot '../msime_setup.iss') $installer
    Copy-Item (Join-Path $PSScriptRoot '../config.default.toml') $installer
    Copy-Item (Join-Path $PSScriptRoot '../assets') $installer -Recurse
    foreach ($file in @(
        'server/build-release/bin/Release/MetasequoiaImeServer.exe',
        'server/build-release/bin/Release/MetasequoiaImeServer.pdb',
        'server/build-release/bin/Release/MetasequoiaImeWatchdog.exe',
        'server/build-release/bin/Release/MetasequoiaImeWatchdog.pdb',
        'server/build-release/bin/Release/MetasequoiaImeDictionaryReplay.exe',
        'server/build-release/bin/Release/MetasequoiaImeDictionaryReplay.pdb',
        'server/build-release/bin/Release/MetasequoiaImeServerTests.exe',
        'server/build-release/bin/Release/MetasequoiaImeServerTests.pdb',
        'server/build-release/bin/Release/test_webview_contract.exe',
        'server/build-release/bin/Release/test_webview_contract.pdb',
        'server/build-release/bin/Release/windows-first-run.exe',
        'server/build-release/bin/Release/nested/windows-server-launch.exe',
        'server/build-release/bin/Release/nested/windows-server-launch.pdb',
        'server/build-release/bin/Release/msime-client-prepare.exe',
        'server/build-release/bin/Release/msime-client-prepare.pdb',
        'windows/build32-release/Release/MetasequoiaImeTsf.dll',
        'windows/build32-release/Release/MetasequoiaImeTsf.pdb',
        'windows/build64-release/Release/MetasequoiaImeTsf.dll',
        'windows/build64-release/Release/MetasequoiaImeTsf.pdb',
        'THIRD_PARTY_NOTICES.txt',
        'LICENSE',
        'target/release/msime-desktop.exe',
        'vendor/MSIME-Engine/handwriting/models/handwriting-zh_CN.model',
        'vendor/MSIME-Engine/handwriting/models/HandwritingModel-LICENSE.txt',
        'vendor/MSIME-Engine/handwriting/provenance.json',
        'server/assets/config/config.toml',
        'server/src/resource/MetasequoiaIME.ico',
        'vendor/MetasequoiaImeEngine/helpcode/helpcodes/helpcode.txt',
        'MetasequoiaImeDict/out/msime.db',
        'MetasequoiaImeDict/out/others.db',
        'MetasequoiaImeDict/out/dict_japanese.dat',
        'MetasequoiaImeDict/source/mozc_dictionary_oss/README.txt',
        'ui-html/webview2/shared/runtime.js',
        'ui-html/webview2/candwnd/index.html',
        'ui-html/webview2/menu/index.html',
        'ui-html/webview2/ftb/index.html',
        'ui-html/webview2/settings/ime-settings/dist/index.html'
    )) { Write-Fixture $file }
    Write-Fixture 'windows/build32-release/Release/msime_host_api.dll' 'synthetic x86 host'
    Write-Fixture 'windows/build64-release/Release/msime_host_api.dll' 'synthetic x64 host'
    Write-Fixture 'server/assets/tables/pinyin.txt' 'xing'
    Write-Fixture 'MetasequoiaImeDict/out/dictionary-manifest.json' '{"manifest_version":1}'
    $english = Join-Path $fixture 'MetasequoiaImeDict/out/english.db'
    python -c "import sqlite3,sys; sqlite3.connect(sys.argv[1]).execute('CREATE TABLE english_words(word TEXT,display TEXT,weight INTEGER,PRIMARY KEY(word,display))')" $english
    if ($LASTEXITCODE -ne 0) { throw 'Failed to create packaging fixture' }
    $artifacts = @(
        foreach ($name in @('msime.db', 'english.db', 'others.db', 'dict_japanese.dat',
                            'mozc_dictionary_oss_README.txt', 'dictionary-manifest.json')) {
            Write-Fixture "target/desktop-resources/$name" "synthetic pinned $name"
            $path = Join-Path $fixture "target/desktop-resources/$name"
            @{ name = $name; size = (Get-Item $path).Length; sha256 = (Get-FileHash $path).Hash.ToLowerInvariant() }
        }
    )
    Write-Fixture 'resources/desktop-dictionary.lock.json' (@{
        source_commit = ('a' * 40); artifacts = $artifacts
    } | ConvertTo-Json -Depth 5)
    Write-Fixture 'target/desktop-resources/unlisted-private-file.txt' 'synthetic excluded data'
    Write-Fixture 'server/build-release/bin/Release/resources/stale.txt' 'synthetic stale bundle'
    & (Join-Path $installer 'Prepare-PackageFiles.ps1') -RepoRoot $fixture -TargetVersion '2026.9.1'
    foreach ($artifact in $artifacts) {
        $path = Join-Path $installer "server_exe/resources/$($artifact.name)"
        if ((Get-FileHash $path).Hash -ne $artifact.sha256) { throw 'Packaged resource hash mismatch' }
    }
    if (Test-Path (Join-Path $installer 'server_exe/resources/unlisted-private-file.txt')) {
        throw 'Packaged an unlisted resource'
    }
    if (Test-Path (Join-Path $installer 'server_exe/resources/stale.txt')) {
        throw 'Packaged unverified native build resources'
    }
    $pinned = Join-Path $fixture 'target/desktop-resources/msime.db'
    $originalPinned = [IO.File]::ReadAllText($pinned)
    foreach ($bad in @('short', ('x' * $originalPinned.Length))) {
        [IO.File]::WriteAllText($pinned, $bad)
        $rejected = $false
        try { & (Join-Path $installer 'Prepare-PackageFiles.ps1') -RepoRoot $fixture } catch { $rejected = $true }
        if (-not $rejected) { throw 'Invalid pinned resource accepted' }
        if ([IO.File]::ReadAllText((Join-Path $installer 'server_exe/resources/msime.db')) -ne $originalPinned) {
            throw 'Failed resource preflight damaged previous staging'
        }
    }
    [IO.File]::WriteAllText($pinned, $originalPinned)
    foreach ($file in @('app_data/html/webview2/shared/runtime.js', 'app_data/dictionary-manifest.json',
                         'tsf_dll/32/MetasequoiaImeTsf.dll', 'tsf_dll/32/MetasequoiaImeTsf.pdb',
                         'tsf_dll/64/MetasequoiaImeTsf.dll', 'tsf_dll/64/MetasequoiaImeTsf.pdb',
                         'server_exe/MetasequoiaImeServer.pdb',
                         'server_exe/MetasequoiaImeWatchdog.exe',
                         'server_exe/MetasequoiaImeWatchdog.pdb',
                         'server_exe/MetasequoiaImeDictionaryReplay.pdb',
                         'server_exe/msime-client-settings.exe',
                         'server_exe/msime-client-prepare.exe',
                         'server_exe/msime-client-prepare.pdb',
                         'server_exe/handwriting/handwriting-zh_CN.model',
                         'server_exe/handwriting/HandwritingModel-LICENSE.txt',
                         'server_exe/handwriting/provenance.json',
                         'app_data/helpcodes/helpcode.txt', 'THIRD_PARTY_NOTICES.txt', 'LICENSE.txt')) {
        if (-not (Test-Path (Join-Path $installer $file))) { throw "Missing packaged file: $file" }
    }
    foreach ($testFile in @(
        'server_exe/MetasequoiaImeServerTests.exe',
        'server_exe/MetasequoiaImeServerTests.pdb',
        'server_exe/test_webview_contract.exe',
        'server_exe/test_webview_contract.pdb',
        'server_exe/windows-first-run.exe',
        'server_exe/nested/windows-server-launch.exe',
        'server_exe/nested/windows-server-launch.pdb'
    )) {
        if (Test-Path (Join-Path $installer $testFile)) { throw "Packaged a test file: $testFile" }
    }
    $serverPdbFixture = Join-Path $fixture 'server/build-release/bin/Release/MetasequoiaImeServer.pdb'
    Remove-Item $serverPdbFixture -Force
    $rejected = $false
    try { & (Join-Path $installer 'Prepare-PackageFiles.ps1') -RepoRoot $fixture } catch { $rejected = $_.Exception.Message -match 'PDB' }
    if (-not $rejected) { throw 'Missing production PDB was accepted' }
    [IO.File]::WriteAllText($serverPdbFixture, 'fixture')
    $database = Join-Path $installer 'app_data/msime.db'
    [IO.File]::WriteAllText($database, 'preserved user data')
    foreach ($arch in @('32', '64')) {
        $expected = if ($arch -eq '32') { 'synthetic x86 host' } else { 'synthetic x64 host' }
        $packagedHost = Join-Path $installer "tsf_dll/$arch/msime_host_api.dll"
        if ([IO.File]::ReadAllText($packagedHost) -ne $expected) { throw 'TSF Host DLL architecture mapping mismatch' }
        $sourceHost = Join-Path $fixture "windows/build$arch-release/Release/msime_host_api.dll"
        Remove-Item -LiteralPath $sourceHost
        foreach ($lightMode in @($false, $true)) {
            $rejected = $false
            try { & (Join-Path $installer 'Prepare-PackageFiles.ps1') -RepoRoot $fixture -Light:$lightMode }
            catch { $rejected = $_.Exception.Message -match 'msime_host_api.dll' }
            if (-not $rejected) { throw 'Missing TSF Host DLL accepted' }
            if ([IO.File]::ReadAllText($database) -ne 'preserved user data' -or
                [IO.File]::ReadAllText($packagedHost) -ne $expected) { throw 'Missing Host DLL damaged previous staging' }
        }
        [IO.File]::WriteAllText($sourceHost, $expected)
    }
    $watchdog = Join-Path $fixture 'server/build-release/bin/Release/MetasequoiaImeWatchdog.exe'
    Remove-Item -LiteralPath $watchdog
    $rejected = $false
    try { & (Join-Path $installer 'Prepare-PackageFiles.ps1') -RepoRoot $fixture -Light } catch { $rejected = $_.Exception.Message -match 'Watchdog' }
    if (-not $rejected) { throw 'Missing watchdog was accepted' }
    if ([IO.File]::ReadAllText($database) -ne 'preserved user data') { throw 'Missing watchdog damaged previous staging' }
    [IO.File]::WriteAllText($watchdog, 'fixture')
    $desktop = Join-Path $fixture 'target/release/msime-desktop.exe'
    Remove-Item -LiteralPath $desktop
    $rejected = $false
    try { & (Join-Path $installer 'Prepare-PackageFiles.ps1') -RepoRoot $fixture -Light } catch { $rejected = $_.Exception.Message -match 'Tauri' }
    if (-not $rejected) { throw 'Missing Tauri shell was accepted' }
    if ([IO.File]::ReadAllText($database) -ne 'preserved user data') { throw 'Missing shell damaged previous staging' }
    [IO.File]::WriteAllText($desktop, 'fixture')
    & (Join-Path $installer 'Prepare-PackageFiles.ps1') -RepoRoot $fixture -TsfDirectory windows -ServerDirectory server -UiHtmlDirectory ui-html -NoticesDirectory . -Light
    if ([IO.File]::ReadAllText($database) -ne 'preserved user data') { throw 'Light package replaced dictionary data' }
    if (-not (Test-Path (Join-Path $installer 'server_exe/msime-client-settings.exe'))) { throw 'Light package lost Tauri shell' }
    foreach ($arch in @('32', '64')) {
        $expected = if ($arch -eq '32') { 'synthetic x86 host' } else { 'synthetic x64 host' }
        if ([IO.File]::ReadAllText((Join-Path $installer "tsf_dll/$arch/msime_host_api.dll")) -ne $expected) {
            throw 'Light package lost matching TSF Host DLL'
        }
    }
    if (-not (Test-Path (Join-Path $installer 'server_exe/msime-client-prepare.exe'))) { throw 'Light package lost preparation tool' }
    foreach ($testFile in @('windows-first-run.exe', 'nested/windows-server-launch.exe', 'nested/windows-server-launch.pdb')) {
        if (Test-Path (Join-Path $installer "server_exe/$testFile")) { throw 'Light package contains a Client test artifact' }
    }
    if (Test-Path (Join-Path $installer 'server_exe/resources')) { throw 'Light package unexpectedly carries dictionaries' }
    Write-Fixture 'custom build/shell.exe' 'synthetic alternate shell'
    foreach ($shellPath in @('custom build/shell.exe', (Join-Path $fixture 'custom build/shell.exe'))) {
        & (Join-Path $installer 'Prepare-PackageFiles.ps1') -RepoRoot $fixture -Light -DesktopExecutable $shellPath
        if ([IO.File]::ReadAllText((Join-Path $installer 'server_exe/msime-client-settings.exe')) -ne 'synthetic alternate shell') {
            throw 'Explicit Tauri shell path was not packaged'
        }
        if ([IO.File]::ReadAllText($database) -ne 'preserved user data') { throw 'Shell override replaced dictionary data' }
    }
    foreach ($name in @('handwriting-zh_CN.model', 'HandwritingModel-LICENSE.txt', 'provenance.json')) {
        if (-not (Test-Path (Join-Path $installer "server_exe/handwriting/$name"))) {
            throw "Light package lost handwriting resource: $name"
        }
    }
    $notice = Join-Path $fixture 'vendor/MSIME-Engine/handwriting/models/HandwritingModel-LICENSE.txt'
    Remove-Item -LiteralPath $notice
    $rejected = $false
    try { & (Join-Path $installer 'Prepare-PackageFiles.ps1') -RepoRoot $fixture } catch { $rejected = $true }
    if (-not $rejected) { throw 'Missing handwriting license was accepted' }
    if ([IO.File]::ReadAllText($database) -ne 'preserved user data') { throw 'Missing license damaged previous staging' }
    [IO.File]::WriteAllText($notice, 'fixture')
    $pinyin = Join-Path $fixture 'server/assets/tables/pinyin.txt'
    [IO.File]::WriteAllText($pinyin, 'invalid-fixture')
    $rejected = $false
    try { & (Join-Path $installer 'Prepare-PackageFiles.ps1') -RepoRoot $fixture } catch { $rejected = $_.Exception.Message -match 'xing' }
    if (-not $rejected) { throw 'Incomplete pinyin table was accepted' }
    if (-not (Test-Path $database) -or [IO.File]::ReadAllText($database) -ne 'preserved user data') { throw 'Invalid pinyin table damaged previous staging' }
    [IO.File]::WriteAllText($pinyin, 'xing')
    $factory = Join-Path $installer 'config.default.toml'
    $originalFactory = [IO.File]::ReadAllText($factory)
    foreach ($invalid in @(
        ('schema = "invalid"' + "`n" + 'theme_mode = "system"'),
        ('schema = "quanpin"' + "`n" + 'theme_mode = "invalid"'),
        ('schema = "quanpin"' + "`n" + 'theme_mode = "system"' + "`n" + 'diagnostic_log = true')
    )) {
        [IO.File]::WriteAllText($factory, $invalid)
        $rejected = $false
        try { & (Join-Path $installer 'Prepare-PackageFiles.ps1') -RepoRoot $fixture } catch { $rejected = $true }
        if (-not $rejected) { throw 'Invalid factory configuration was accepted' }
        if (-not (Test-Path $database) -or [IO.File]::ReadAllText($database) -ne 'preserved user data') { throw 'Invalid factory configuration damaged previous staging' }
    }
    [IO.File]::WriteAllText($factory, $originalFactory)
    foreach ($mapping in @(@('32', 'x86'), @('64', 'x64'))) {
        $native = Join-Path $fixture "target/windows-full/$($mapping[1])/bin"
        New-Item -ItemType Directory -Force $native | Out-Null
        foreach ($name in @('MetasequoiaImeTsf.dll', 'MetasequoiaImeTsf.pdb')) {
            Copy-Item (Join-Path $fixture "windows/build$($mapping[0])-release/Release/$name") $native
        }
        [IO.File]::WriteAllText((Join-Path $native 'msime_host_api.dll'), "native $($mapping[1]) host")
    }
    & (Join-Path $installer 'Prepare-PackageFiles.ps1') -RepoRoot $fixture -Light -ServerReleaseDirectory 'server/build-release/bin/Release'
    foreach ($mapping in @(@('32', 'x86'), @('64', 'x64'))) {
        if ([IO.File]::ReadAllText((Join-Path $installer "tsf_dll/$($mapping[0])/msime_host_api.dll")) -ne "native $($mapping[1]) host") {
            throw 'Native build directory default was not selected'
        }
    }
    & (Join-Path $installer 'Prepare-PackageFiles.ps1') -RepoRoot $fixture -Light `
        -ServerReleaseDirectory 'server/build-release/bin/Release' `
        -Tsf32ReleaseDirectory 'windows/build32-release/Release' -Tsf64ReleaseDirectory 'windows/build64-release/Release'
    foreach ($mapping in @(@('32', 'x86'), @('64', 'x64'))) {
        if ([IO.File]::ReadAllText((Join-Path $installer "tsf_dll/$($mapping[0])/msime_host_api.dll")) -ne "synthetic $($mapping[1]) host") {
            throw 'Explicit TSF directory override was ignored'
        }
    }
    if (-not (Test-Path (Join-Path $installer 'app_data/html/webview2/shared/runtime.js'))) { throw 'Light package lost shared contracts' }
    Remove-Item (Join-Path $fixture 'ui-html/webview2/shared') -Recurse -Force
    $rejected = $false
    try { & (Join-Path $installer 'Prepare-PackageFiles.ps1') -RepoRoot $fixture -TsfDirectory windows -ServerDirectory server -UiHtmlDirectory ui-html -NoticesDirectory . } catch { $rejected = $true }
    if (-not $rejected) { throw 'Missing shared contracts were accepted' }
    if ([IO.File]::ReadAllText($database) -ne 'preserved user data') { throw 'Rejected package damaged previous staging' }
    Write-Host 'Full/light package contracts, provenance, exclusions and failure staging passed'
} finally {
    if (Test-Path $fixture) { Remove-Item $fixture -Recurse -Force }
}
