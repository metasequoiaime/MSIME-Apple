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
Write-Output 'Installer carries native/Tauri outputs without loose legacy HTML'
