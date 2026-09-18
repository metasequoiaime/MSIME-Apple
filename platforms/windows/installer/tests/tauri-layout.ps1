$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$script = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../msime_setup.iss') -Raw
$script = $script -replace '\\\r?\n\s*', ' '
$records = [regex]::Matches($script, '(?m)^Source:[^\r\n]*')
if (@($records | Where-Object { $_.Value.Contains('\app_data\html\') }).Count -ne 0) {
    throw 'Installer still requires loose legacy HTML'
}
$data = @($records | Where-Object { $_.Value.Contains('\app_data\*') })
if ($data.Count -ne 1 -or -not $data[0].Value.Contains('\html\*')) {
    throw 'Full package does not exclude stale HTML'
}
$server = @($records | Where-Object { $_.Value.Contains('\server_exe\*') })
if ($server.Count -ne 1 -or -not $server[0].Value.Contains('recursesubdirs')) {
    throw 'Missing native/Tauri executable installation rule'
}
$dataDirRecords = @($records | Where-Object { $_.Value.Contains('{code:GetDataDir}') })
if ($dataDirRecords.Count -lt 3) {
    throw 'Installer resources do not follow the selected DataDir'
}
if (-not $script.Contains('ValueName: "DataDir"') -or
    -not $script.Contains('{param:DATADIR|}')) {
    throw 'Installer does not persist or accept the selected DataDir'
}
if (-not $script.Contains('function DataDirIsSafe') -or
    -not $script.Contains('DataDirIsSafe(GetDataDir')) {
    throw 'Installer does not validate the selected DataDir'
}
if (-not $script.Contains("DataDirMarkerName = '.metasequoiaime-data'") -or
    -not $script.Contains('function OwnsDataDir') -or
    -not $script.Contains('WriteDataDirMarker(GetDataDir')) {
    throw 'Installer does not protect user-owned data directories with a marker'
}
if (-not $script.Contains('if not OwnsDataDir(AppDataPath) then')) {
    throw 'Installer cleanup is not guarded by data-directory ownership'
}
if (-not $script.Contains('custom DataDir may already contain files')) {
    throw 'Installer database cleanup lacks custom-directory ownership protection'
}
if (-not $script.Contains('function MigrateUserDataDir') -or
    -not $script.Contains('robocopy.exe') -or
    -not $script.Contains('MigrateUserDataDir(ResolvePreviousDataDir')) {
    throw 'Installer does not migrate user data when DataDir changes'
}
Write-Output 'Installer carries native/Tauri outputs without loose legacy HTML'
