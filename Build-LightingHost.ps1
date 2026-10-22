# Build the optional backends using the installed .NET SDK. Artifacts stay on E:.
param([switch]$Test)
$ErrorActionPreference = 'Stop'
$project = Join-Path $PSScriptRoot 'LightingHost\LightingHost.csproj'
$output = Join-Path $PSScriptRoot 'LightingHost\publish'
& dotnet publish $project -c Release -r win-x64 --self-contained false -o $output --nologo
if ($LASTEXITCODE -ne 0) { throw 'Lighting host build failed.' }
if ($Test) {
    & (Join-Path $output 'ScreenOff.LightingHost.exe') --self-test
    if ($LASTEXITCODE -ne 0) { throw 'Lighting backend simulations failed.' }
}
