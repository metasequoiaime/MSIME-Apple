$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../msime_setup.iss') -Raw
$script = $script -replace '\\\r?\n\s*', ' '

$create = [regex]::Match(
    $script,
    "(?s)procedure CreateWatchdogLogonTask;.*?end;\r?\n\r?\nprocedure TryDeleteTree"
).Value
if (-not $create) { throw 'Watchdog task creation procedure is missing' }
if ($create -notmatch "/SC ONLOGON") { throw 'Watchdog task is not a logon task' }
if ($create -notmatch "/RL LIMITED") { throw 'Watchdog task must use a non-elevated run level' }
if ($create -notmatch "/IT") { throw 'Watchdog task must run only in an interactive session' }
if (-not $create.Contains('/TR "') -or -not $create.Contains('WatchdogPath')) {
    throw 'Watchdog task action is not passed as one quoted executable path'
}
if ($create.Contains('/TR "\"')) { throw 'Watchdog task action contains shell escape characters' }

$delete = [regex]::Match(
    $script,
    "(?s)procedure DeleteWatchdogLogonTask;.*?end;\r?\n\r?\nprocedure EnsureSharedWebView2DataDir"
).Value
if ($delete -notmatch '/Delete /F /TN') { throw 'Uninstall does not remove the watchdog task' }

Write-Output 'Watchdog task registration and removal command contracts passed'
