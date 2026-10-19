param([string]$Configuration='Release')
$ErrorActionPreference='Stop'
$vswhere="${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs=& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if(-not $vs){throw 'Install Visual Studio Build Tools with the Desktop development with C++ workload.'}
$cmake=Join-Path $vs 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
if(-not (Test-Path $cmake)){$cmake='cmake'}
& $cmake -S $PSScriptRoot -B "$PSScriptRoot\build" -G 'Visual Studio 17 2022' -A x64
if($LASTEXITCODE){exit $LASTEXITCODE}
& $cmake --build "$PSScriptRoot\build" --config $Configuration --parallel 2
if($LASTEXITCODE){exit $LASTEXITCODE}
& "$PSScriptRoot\build\$Configuration\FlowCatCoreTests.exe"
if($LASTEXITCODE){exit $LASTEXITCODE}
& "$PSScriptRoot\build\$Configuration\FlowCatStoreTests.exe"
exit $LASTEXITCODE
