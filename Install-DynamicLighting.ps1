<#
.SYNOPSIS
Build/register the optional Windows Dynamic Lighting identity for this user.
.DESCRIPTION
PackOnly creates an unsigned identity package without installing it. Development
registration requires Windows Developer Mode already enabled. For normal signed
registration supply an existing trusted signing certificate from CurrentUser\My.
This script never enables Developer Mode, creates trust certificates, changes
lighting priorities or colours, or installs a startup task.
.EXAMPLE
.\Install-DynamicLighting.ps1 -PackOnly
.EXAMPLE
.\Install-DynamicLighting.ps1 -Development
#>
param([switch]$PackOnly,[switch]$Development,[string]$CertificateThumbprint)
$ErrorActionPreference = 'Stop'
$publish = Join-Path $PSScriptRoot 'LightingHost\publish'
$identity = Join-Path $PSScriptRoot 'LightingHost\Identity'
$helper = Join-Path $publish 'ScreenOff.LightingHost.exe'
if (-not (Test-Path -LiteralPath $helper)) { throw 'Run Build-LightingHost.ps1 first.' }
$kitRoot = 'C:\Program Files (x86)\Windows Kits\10\bin'
$packer = Get-ChildItem -Path ($kitRoot + '\*\x64\makeappx.exe') | Sort-Object FullName -Descending | Select-Object -First 1
if ($null -eq $packer) { throw 'Windows SDK MakeAppx.exe is required to build the identity package.' }
$assets = Join-Path $publish 'Assets'
New-Item -ItemType Directory -Path $assets -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $publish 'Public') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'assets\screen-off.png') -Destination (Join-Path $assets 'screen-off.png') -Force
$package = Join-Path $PSScriptRoot 'LightingHost\ScreenOff.Lighting.msix'
# Sparse package references the external published executable. /nv is required
# by Microsoft's sparse-package instructions to skip external file resolution.
& $packer.FullName pack /o /d $identity /nv /p $package
if ($LASTEXITCODE -ne 0) { throw 'Identity package build failed.' }
if ($PackOnly) { Write-Output ('Built unsigned package: ' + $package + '; not installed.'); return }
if (Get-AppxPackage -Name 'ScreenOff.Lighting') { throw 'ScreenOff.Lighting is already registered. Review its version before replacing it.' }
if ($Development) {
    $dev = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -ErrorAction SilentlyContinue
    if ($null -eq $dev -or $dev.AllowDevelopmentWithoutDevLicense -ne 1) {
        throw 'Development registration requires Developer Mode already enabled in Windows Settings. Alternatively use an existing trusted signing certificate. No system security setting was changed.'
    }
    Add-AppxPackage -Register (Join-Path $identity 'AppxManifest.xml') -ExternalLocation $publish
} else {
    if (-not $CertificateThumbprint) { throw 'Choose -Development on an existing development PC, or provide -CertificateThumbprint for an existing trusted signing certificate. Package built but not installed.' }
    $certificate = Get-Item -LiteralPath ('Cert:\CurrentUser\My\' + $CertificateThumbprint)
    if ($certificate.Subject -ne 'CN=ScreenOff.Local') { throw 'Certificate subject must match CN=ScreenOff.Local in the package and executable manifests.' }
    $signer = Join-Path $packer.DirectoryName 'signtool.exe'
    & $signer sign /fd SHA256 /sha1 $CertificateThumbprint /s My $package
    if ($LASTEXITCODE -ne 0) { throw 'Package signing failed.' }
    Add-AppxPackage -Path $package -ExternalLocation $publish
}
Write-Output 'Identity registered. In Windows Settings > Personalization > Dynamic lighting, prioritize Screen Off Lighting for each compatible device. No lighting writes performed.'
