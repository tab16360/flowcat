param([switch]$SkipBuild)
$ErrorActionPreference='Stop'
if(-not $SkipBuild){& "$PSScriptRoot\build.ps1";if($LASTEXITCODE){exit $LASTEXITCODE}}
$stage=Join-Path $PSScriptRoot 'build\package'
$out=Join-Path $PSScriptRoot 'dist'
New-Item -ItemType Directory -Force $stage,$out | Out-Null
Copy-Item "$PSScriptRoot\build\Release\FlowCat.exe" "$stage\FlowCat.exe" -Force
Copy-Item "$PSScriptRoot\README.md" "$stage\README.md" -Force
$zip=Join-Path $out 'FlowCat-Windows-x64-preview.zip'
Compress-Archive -Path "$stage\FlowCat.exe","$stage\README.md" -DestinationPath $zip -Force
$hash=(Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  FlowCat-Windows-x64-preview.zip" | Set-Content "$zip.sha256" -Encoding ascii
Get-Item $zip | Select-Object Name,Length
