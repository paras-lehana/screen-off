# Non-actuating regression suite: no lock, screen-power, input injection or real RGB.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Find-AutoHotkey.ps1')
$runtime = Find-AutoHotkey
$output = Join-Path $PSScriptRoot ('logs\offline-tests-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $output -Force | Out-Null
function Invoke-AhkCheck([string]$Name,[switch]$Validate) {
    $argsList = @('/ErrorStdOut')
    if ($Validate) { $argsList += '/Validate' }
    $argsList += '"' + (Join-Path $PSScriptRoot $Name) + '"'
    $label = $Name + $(if ($Validate) { '-validate' } else { '' })
    $process = Start-Process -FilePath $runtime -ArgumentList $argsList -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -PassThru -Wait -RedirectStandardOutput (Join-Path $output ($label + '.out')) -RedirectStandardError (Join-Path $output ($label + '.err'))
    $stdout = Get-Content -LiteralPath (Join-Path $output ($label + '.out')) -Raw
    $stderr = Get-Content -LiteralPath (Join-Path $output ($label + '.err')) -Raw
    if ($process.ExitCode -ne 0 -or $stderr -or $stdout -match 'Warning:|FAIL|==>') {
        throw ($Name + ': ' + $stdout + $stderr + '; exit=' + $process.ExitCode)
    }
    if ($stdout) { Write-Output $stdout.Trim() }
    elseif ($Validate) { Write-Output ('PASS AHK validation: ' + $Name) }
    else { throw ('No test result: ' + $Name) }
}
Invoke-AhkCheck 'ScreenOffWindows.ahk' -Validate
Invoke-AhkCheck 'configure-utility.ahk' -Validate
Invoke-AhkCheck 'control-utility.ahk' -Validate
Invoke-AhkCheck 'test-settings-ui.ahk' -Validate
Invoke-AhkCheck 'test-wake-lock.ahk'
Invoke-AhkCheck 'test-configuration.ahk'
Invoke-AhkCheck 'test-input-release.ahk'
Invoke-AhkCheck 'test-standby-preparation.ahk'
Invoke-AhkCheck 'test-display-presence.ahk'
Invoke-AhkCheck 'test-lighting-set.ahk'
Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File | ForEach-Object {
    $tokens = $null; $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$parseErrors)
    if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
}
Write-Output 'PASS PowerShell parsing, zero errors.'
& (Join-Path $PSScriptRoot 'LightingHost\publish\ScreenOff.LightingHost.exe') --self-test
if ($LASTEXITCODE -ne 0) { throw 'Backend simulation failed.' }
Write-Output ('Evidence: ' + $output)
