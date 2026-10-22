# Downloads Corsair's official iCUE SDK 4.0.84 release and verifies it before extracting to
# vendor\iCUESDK_4.0.84 (not committed). Needed only for the Corsair lighting system.
$ErrorActionPreference = 'Stop'
$url = 'https://github.com/CorsairOfficial/cue-sdk/releases/download/v4.0.84/iCUESDK_4.0.84.zip'
$sha256 = 'EB4414CF505145F3E507DC839AD587BF7CA684D64BE3D9A834F416A136736D5D'
$vendor = Join-Path $PSScriptRoot 'vendor'
$zip = Join-Path $vendor 'iCUESDK_4.0.84.zip'
$target = Join-Path $vendor 'iCUESDK_4.0.84'
New-Item -ItemType Directory -Path $vendor -Force | Out-Null
if (-not (Test-Path -LiteralPath $zip)) { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $zip }
$actual = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
if ($actual -ne $sha256) {
    Remove-Item -LiteralPath $zip -Force
    throw "SHA256 mismatch for $url (got $actual). Download removed; nothing extracted."
}
Expand-Archive -LiteralPath $zip -DestinationPath $target -Force
$dll = Join-Path $target 'iCUESDK\redist\x64\iCUESDK.x64_2019.dll'
if (-not (Test-Path -LiteralPath $dll)) { throw "Archive layout changed: $dll not found." }
Write-Output "iCUE SDK ready: $dll"
