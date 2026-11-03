# Knight Logics - Documents Backup installer.
# Downloads the backup program, checks it is exactly the expected file, then runs setup.
$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072 } catch {}
$url  = 'https://raw.githubusercontent.com/Knight-Logics/author-vault/dcd9abf761f4da8a5e43c0e704c333d075df25b0/DocumentsBackup.ps1'
$want = '69C7B35C9A8301301EDA06C955ED1519B9CE9F1EC654EE045CCFB35178D90937'
$dir  = Join-Path $env:LOCALAPPDATA 'KnightLogics\DocumentsBackup'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$tmp  = Join-Path $dir 'DocumentsBackup.download'
Write-Host '  Downloading the backup program...'
Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
$got = (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash
if ($got -ne $want) {
    Remove-Item -LiteralPath $tmp -Force
    throw "The download did not match the expected file, so nothing was installed. (got $got)"
}
$ps1 = Join-Path $dir 'DocumentsBackup.ps1'
Move-Item -LiteralPath $tmp -Destination $ps1 -Force
try { Unblock-File -LiteralPath $ps1 } catch {}
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
& $ps1 -Mode Install
