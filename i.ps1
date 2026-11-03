# Knight Logics - Documents Backup installer.
# Downloads the backup program, checks it is exactly the expected file, then runs setup.
$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072 } catch {}
$url  = 'https://raw.githubusercontent.com/Knight-Logics/author-vault/8d25d1379199c1078358defce4cb79e4ca86a8f2/DocumentsBackup.ps1'
$want = '0A86AB461A2A383FD77D08BB5B157BEF6FC4EFD03C6F7DEEC0825C2BD02B213A'
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
