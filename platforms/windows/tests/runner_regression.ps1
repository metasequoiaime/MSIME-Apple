param([Parameter(Mandatory = $true)][string]$Probe)
$ErrorActionPreference = 'Stop'
$probePath = (Resolve-Path -LiteralPath $Probe).ProviderPath
$runner = Join-Path $PSScriptRoot 'run-smoke.ps1'
$tokens = $null
$parseErrors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($runner, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -ne 0) { throw 'Runner parse failed' }
$root = Join-Path ([System.IO.Path]::GetTempPath()) ('msime-runner-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $root
$previousMode = $env:MSIME_RUNNER_PROBE_MODE
try {
    Copy-Item -LiteralPath $runner -Destination (Join-Path $root 'run-smoke.ps1')
    $copy = Join-Path $root 'run-smoke.ps1'
    $names = @(
        'windows-registration-inbox.exe', 'windows-focus-router.exe',
        'windows-main-frame.exe', 'windows-focus-gate.exe',
        'windows-input-queue.exe', 'windows-session-smoke.exe',
        'windows-reply-codec.exe', 'windows-reply-composer.exe',
        'windows-pipe-io.exe', 'windows-server-smoke.exe',
        'windows-preview-config.exe', 'msime-client-server.exe'
    )
    foreach ($name in $names) { Copy-Item -LiteralPath $probePath -Destination (Join-Path $root $name) }
    $env:MSIME_RUNNER_PROBE_MODE = 'pass'
    $output = @(& $copy 6>&1 | ForEach-Object { $_.ToString() })
    if (@($output | Where-Object { $_ -like 'PASS *' }).Count -ne 12 -or
        @($output | Where-Object { $_ -like 'SKIP locked-dictionary*' }).Count -ne 1) {
        throw 'Default runner coverage mismatch'
    }
    $resources = Join-Path $root 'resource directory'
    $null = New-Item -ItemType Directory -Path $resources
    $output = @(& $copy -ResourcesDirectory $resources 6>&1 | ForEach-Object { $_.ToString() })
    if (@($output | Where-Object { $_ -like 'PASS *' }).Count -ne 13 -or
        @($output | Where-Object { $_ -like 'SKIP *' }).Count -ne 0) {
        throw 'Resource runner coverage mismatch'
    }
    function Expect-Failure([scriptblock]$Action, [string]$Message) {
        $caught = $false
        try { & $Action | Out-Null } catch {
            if ($_.Exception.Message -notlike $Message) { throw }
            $caught = $true
        }
        if (-not $caught) { throw 'Expected runner rejection' }
    }
    Expect-Failure { & $copy -ResourcesDirectory '' } '*must not be empty*'
    $env:MSIME_RUNNER_PROBE_MODE = 'fail'
    Expect-Failure { & $copy } '*exit 7*'
    $env:MSIME_RUNNER_PROBE_MODE = 'timeout'
    Expect-Failure { & $copy -TimeoutSeconds 1 } '*timed out*'
    $env:MSIME_RUNNER_PROBE_MODE = 'pass'
    Remove-Item -LiteralPath (Join-Path $root 'msime-client-server.exe')
    Expect-Failure { & $copy } '*Missing test: msime-client-server.exe*'
    Write-Host 'Runner process-control regressions passed; no Windows IME binary was tested.'
} finally {
    $env:MSIME_RUNNER_PROBE_MODE = $previousMode
    Remove-Item -LiteralPath $root -Recurse -Force
}
