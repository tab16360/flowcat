param([string]$PayloadUrl='')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$run=Join-Path $root ('build\verify-'+[guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $run | Out-Null
$report=Join-Path $run 'report.json'
$exe=Join-Path $root 'build\Release\FlowCat.exe'
$p=Start-Process $exe -ArgumentList "--diagnostics 22 --report $report --data-dir $run\history" -PassThru
Start-Sleep 5
$buffer=New-Object byte[] (1MB)
$rng=[System.Security.Cryptography.RandomNumberGenerator]::Create();$rng.GetBytes($buffer);$rng.Dispose()
$file=Join-Path $run 'disk-test.bin'
$f=New-Object System.IO.FileStream($file,[System.IO.FileMode]::Create,[System.IO.FileAccess]::ReadWrite,[System.IO.FileShare]::None,1MB,[System.IO.FileOptions]::WriteThrough)
try { for($i=0;$i -lt 16;$i++){$f.Write($buffer,0,$buffer.Length)};$f.Flush($true);$f.Position=0;while($f.Read($buffer,0,$buffer.Length) -gt 0){} } finally {$f.Dispose()}
if($PayloadUrl){Invoke-WebRequest -UseBasicParsing $PayloadUrl -OutFile (Join-Path $run 'network-test.bin') | Out-Null}
$p.WaitForExit();if($p.ExitCode -ne 0){throw "Diagnostics exit $($p.ExitCode)"}
if(-not (Test-Path $report)){throw 'No diagnostics report'}
Get-Content $report -Encoding UTF8
Remove-Item $file -Force
if(Test-Path (Join-Path $run 'network-test.bin')){Remove-Item (Join-Path $run 'network-test.bin') -Force}
