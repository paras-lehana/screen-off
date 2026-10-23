# Downloads Corsair's official iCUE SDK releases and verifies each before extracting to
# vendor\ (not committed). iCUE 4.x speaks SDK protocol 4.0.12 and rejects the newer 4.0.84
# client at handshake, so both are fetched: 4.0.48 for iCUE 4, 4.0.84 for iCUE 5.
$ErrorActionPreference = 'Stop'
$releases = @(
    @{ Version = '4.0.48'; Sha256 = 'A355A5F2F98DE324F20E2838377EAEA267834939FA404A8300D98AE2C209B788' },
    @{ Version = '4.0.84'; Sha256 = 'EB4414CF505145F3E507DC839AD587BF7CA684D64BE3D9A834F416A136736D5D' }
)
$vendor = Join-Path $PSScriptRoot 'vendor'
New-Item -ItemType Directory -Path $vendor -Force | Out-Null
foreach ($release in $releases) {
    $name = "iCUESDK_$($release.Version)"
    $zip = Join-Path $vendor "$name.zip"
    $target = Join-Path $vendor $name
    $dll = Join-Path $target 'iCUESDK\redist\x64\iCUESDK.x64_2019.dll'
    if (Test-Path -LiteralPath $dll) { Write-Output "$name already present"; continue }
    $url = "https://github.com/CorsairOfficial/cue-sdk/releases/download/v$($release.Version)/$name.zip"
    if (-not (Test-Path -LiteralPath $zip)) { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $zip }
    $actual = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
    if ($actual -ne $release.Sha256) {
        Remove-Item -LiteralPath $zip -Force
        throw "SHA256 mismatch for $url (got $actual). Download removed; nothing extracted."
    }
    Expand-Archive -LiteralPath $zip -DestinationPath $target -Force
    if (-not (Test-Path -LiteralPath $dll)) { throw "Archive layout changed: $dll not found." }
    Write-Output "$name ready"
}
