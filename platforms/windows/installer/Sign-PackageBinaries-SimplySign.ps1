<#
.SYNOPSIS
    Sign every staged Windows EXE/DLL with the connected Certum SimplySign card.

.DESCRIPTION
    This is the release counterpart of Sign-PackageBinaries-Local.ps1. It never
    signs only the Server: the Tauri shell, helper processes, TSF adapters and
    bundled runtime DLLs all reach the user's disk and must carry Authenticode.
    All payloads are passed to one signtool invocation so SimplySign prompts only
    once for the virtual-card PIN.
#>
[CmdletBinding()]
param(
    [string]$PackageRoot = $PSScriptRoot,
    [string]$CertificateThumbprint,
    [ValidateNotNullOrEmpty()]
    [string]$TimestampUrl = 'http://time.certum.pl',
    [string]$SignToolPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$CodeSigningEku = '1.3.6.1.5.5.7.3.3'

function Find-SignTool {
    param([string]$ExplicitPath)
    if ($ExplicitPath) {
        if (-not (Test-Path -LiteralPath $ExplicitPath -PathType Leaf)) {
            throw "signtool.exe 不存在：$ExplicitPath"
        }
        return (Resolve-Path -LiteralPath $ExplicitPath).Path
    }
    $kitsBin = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    $candidate = Get-ChildItem -LiteralPath $kitsBin -Directory -ErrorAction SilentlyContinue |
        Sort-Object { try { [version]$_.Name } catch { [version]'0.0' } } -Descending |
        ForEach-Object { Join-Path $_.FullName 'x64\signtool.exe' } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
    if (-not $candidate) { throw '找不到 Windows SDK signtool.exe。' }
    return $candidate
}

function Test-CodeSigningCertificate {
    param([Parameter(Mandatory)]$Certificate)
    foreach ($usage in @($Certificate.EnhancedKeyUsageList)) {
        $value = $usage.PSObject.Properties['Value']
        if ($value -and $value.Value -eq $CodeSigningEku) { return $true }
        $objectId = $usage.PSObject.Properties['ObjectId']
        if ($objectId) {
            $id = $objectId.Value
            if (($id -is [System.Security.Cryptography.Oid] -and $id.Value -eq $CodeSigningEku) -or
                $id -eq $CodeSigningEku) { return $true }
        }
    }
    return $false
}

function Select-SimplySignCertificate {
    param([string]$Thumbprint)
    $normalized = $Thumbprint -replace '\s', ''
    $candidates = @(
        Get-ChildItem -Path 'Cert:\CurrentUser\My' |
            Where-Object {
                $_.HasPrivateKey -and $_.NotBefore -le (Get-Date) -and $_.NotAfter -gt (Get-Date) -and
                (Test-CodeSigningCertificate $_) -and $_.Issuer -match '(?i)Certum'
            }
    )
    if ($normalized) {
        $candidates = @($candidates | Where-Object {
            ($_.Thumbprint -replace '\s', '') -ieq $normalized
        })
    }
    if ($candidates.Count -eq 0) {
        throw '没有发现有效的 Certum 代码签名证书；请先连接 SimplySign 虚拟卡。'
    }
    if ($candidates.Count -gt 1) {
        $details = $candidates | ForEach-Object { "  $($_.Thumbprint) $($_.Subject)" }
        throw "发现多个 Certum 代码签名证书，请用 -CertificateThumbprint 指定：`n$($details -join "`n")"
    }
    return $candidates[0]
}

$root = (Resolve-Path -LiteralPath $PackageRoot).Path
$directories = @((Join-Path $root 'server_exe'), (Join-Path $root 'tsf_dll'))
foreach ($directory in $directories) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        throw "签名目录不存在，请先运行 Prepare-PackageFiles.ps1：$directory"
    }
}
$targets = @(
    foreach ($directory in $directories) {
        Get-ChildItem -LiteralPath $directory -Recurse -File |
            Where-Object { $_.Extension -in @('.exe', '.dll') }
    }
) | Sort-Object FullName -Unique
if ($targets.Count -eq 0) { throw '暂存包中没有可签名的 EXE 或 DLL。' }

$certificate = Select-SimplySignCertificate -Thumbprint $CertificateThumbprint
$signTool = Find-SignTool -ExplicitPath $SignToolPath
$paths = @($targets | ForEach-Object { $_.FullName })
$thumbprint = $certificate.Thumbprint -replace '\s', ''
Write-Host "使用 SimplySign 证书签名 $($paths.Count) 个 EXE/DLL：$($certificate.Subject)"
& $signTool sign /sha1 $thumbprint /s My /fd sha256 /tr $TimestampUrl /td sha256 /v @($paths)
if ($LASTEXITCODE -ne 0) { throw "signtool 签名失败，退出码：$LASTEXITCODE" }
foreach ($path in $paths) {
    & $signTool verify /pa /all /v $path
    if ($LASTEXITCODE -ne 0) { throw "签名校验失败：$path" }
    $signature = Get-AuthenticodeSignature -LiteralPath $path
    if (-not $signature.SignerCertificate -or
        (($signature.SignerCertificate.Thumbprint -replace '\s', '') -ine $thumbprint)) {
        throw "签名证书不匹配：$path"
    }
    if (-not $signature.TimeStamperCertificate) { throw "缺少可信时间戳：$path" }
}
Write-Host "SimplySign 包内二进制签名完成：$($paths.Count) 个文件。"
$global:LASTEXITCODE = 0
