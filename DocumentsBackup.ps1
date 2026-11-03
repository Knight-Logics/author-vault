<#
    Knight Logics - Documents Backup
    Version 1.0.1

    Keeps a plain, readable copy of the Documents folder on the external backup drive:

      <drive>:\<Name>'s Documents Backup\Current Documents\   exact copy as of the last backup
      <drive>:\<Name>'s Documents Backup\Previous Versions\   older copies of changed or deleted
                                                             files, in dated folders

    The originals in Documents are only ever read - never moved, changed or deleted.

    Modes:
      Install   - one-time setup (run in a normal PowerShell window)
      Auto      - what the scheduled task runs (hidden, about every hour)
      Repair    - runs at sign-in: fixes the schedule if needed, then backs up
      Backup    - run a backup right now and show progress
      Status    - show the current state
      SelfTest  - test the engine on sample files in a temporary folder
      Uninstall - stop automatic backups (backup copies are left untouched)
#>
[CmdletBinding()]
param(
    [ValidateSet('Install', 'Auto', 'Repair', 'Backup', 'Status', 'SelfTest', 'Uninstall')]
    [string]$Mode = 'Auto',
    [string]$Drive,
    [switch]$NoPrompt
)

$ErrorActionPreference = 'Stop'
$script:Version      = '1.0.1'
$script:TaskName     = 'Knight Logics - Documents Backup'
$script:RunKeyName   = 'KnightLogicsDocumentsBackup'
$script:AppDir       = Join-Path $env:LOCALAPPDATA 'KnightLogics\DocumentsBackup'
$script:LogDir       = Join-Path $script:AppDir 'Logs'
$script:MarkerName   = 'KnightLogics-Backup-Drive.json'
$script:CurrentName  = 'Current Documents'
$script:VersionsName = 'Previous Versions'
$script:HashLimit    = 256MB
$script:CopyBuffer   = New-Object byte[] 1048576
$script:Interactive  = $false
$script:Inv          = [System.Globalization.CultureInfo]::InvariantCulture
$script:Excludes     = @('~$*', '~*.tmp', '*.tmp', 'Thumbs.db', 'desktop.ini', '.~lock.*#', '*.ost', '*.partial', '*.crdownload')

# ----------------------------------------------------------------------------------------------
# Small helpers
# ----------------------------------------------------------------------------------------------

function PathJoin([string]$A, [string]$B) {
    if ([string]::IsNullOrEmpty($B)) { return $A }
    if ($A.EndsWith('\')) { return $A + $B }
    return $A + '\' + $B
}

function Get-Parent([string]$P) {
    $i = $P.LastIndexOf('\')
    if ($i -le 2) { return $P.Substring(0, $i + 1) }
    return $P.Substring(0, $i)
}

# Long-path-safe form of a path for .NET file calls (only used for very long paths).
function ToLongPath([string]$P) {
    if ($P.Length -ge 240 -and -not $P.StartsWith('\\?\')) {
        if ($P.StartsWith('\\')) { return '\\?\UNC\' + $P.Substring(2) }
        return '\\?\' + $P
    }
    return $P
}

function Ensure-Dir([string]$P) {
    if (-not [System.IO.Directory]::Exists((ToLongPath $P))) { [void][System.IO.Directory]::CreateDirectory((ToLongPath $P)) }
}

function Remove-FileForce([string]$P) {
    $l = ToLongPath $P
    try { [System.IO.File]::SetAttributes($l, [System.IO.FileAttributes]::Normal) } catch {}
    [System.IO.File]::Delete($l)
}

function Remove-TreeForce([string]$P) {
    $l = ToLongPath $P
    if (-not [System.IO.Directory]::Exists($l)) { return }
    $di = [System.IO.DirectoryInfo]::new($l)
    foreach ($f in $di.GetFiles('*', [System.IO.SearchOption]::AllDirectories)) {
        try { $f.Attributes = [System.IO.FileAttributes]::Normal } catch {}
    }
    [System.IO.Directory]::Delete($l, $true)
}

function Remove-EmptyTree([string]$P) {
    $di = [System.IO.DirectoryInfo]::new((ToLongPath $P))
    if (-not $di.Exists) { return }
    foreach ($sub in $di.GetDirectories()) { Remove-EmptyTree $sub.FullName }
    if ($di.GetFileSystemInfos().Length -eq 0) { $di.Delete() }
}

function Get-InnerException($ErrorRecord) {
    $ex = $ErrorRecord
    if ($ErrorRecord -is [System.Management.Automation.ErrorRecord]) { $ex = $ErrorRecord.Exception }
    while ($ex -is [System.Management.Automation.RuntimeException] -and $ex.InnerException) { $ex = $ex.InnerException }
    return $ex
}

function Get-ErrText($ErrorRecord) {
    $ex = Get-InnerException $ErrorRecord
    if ($ex -and $ex.Message) { return ([string]$ex.Message).Trim() }
    return [string]$ErrorRecord
}

function Test-LockedError($ErrorRecord) {
    $ex = Get-InnerException $ErrorRecord
    if (-not $ex) { return $false }
    $code = $ex.HResult -band 0xFFFF
    return ($code -eq 32 -or $code -eq 33)
}

function Format-Size([double]$Bytes) {
    if ($Bytes -ge 1GB) { return ('{0:N1} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} KB' -f ($Bytes / 1KB)) }
    return ('{0:N0} bytes' -f $Bytes)
}

function Get-Sha256([string]$P) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $fs = $null
    try {
        $share = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
        $fs = [System.IO.FileStream]::new((ToLongPath $P), [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $share, 1048576)
        return [System.BitConverter]::ToString($sha.ComputeHash($fs))
    }
    finally {
        if ($fs) { $fs.Dispose() }
        $sha.Dispose()
    }
}

function Write-Log([string]$Message, [string]$Level = 'INFO') {
    $line = '{0} [{1}] {2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss', $script:Inv), $Level, $Message
    try {
        Ensure-Dir $script:LogDir
        $file = PathJoin $script:LogDir ('backup-' + (Get-Date).ToString('yyyy-MM', $script:Inv) + '.log')
        [System.IO.File]::AppendAllText($file, $line + "`r`n")
    } catch {}
    if ($script:Interactive) {
        $color = 'Gray'
        if ($Level -eq 'WARN') { $color = 'Yellow' }
        if ($Level -eq 'ERROR') { $color = 'Red' }
        Write-Host ('  ' + $Message) -ForegroundColor $color
    }
}

function Set-Val($Obj, [string]$Name, $Value) {
    if ($null -eq $Value) { $Value = '' }
    if ($Obj.PSObject.Properties[$Name]) { $Obj.$Name = $Value }
    else { $Obj | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

function Get-Val($Obj, [string]$Name) {
    if (-not $Obj) { return $null }
    $p = $Obj.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $null
}

function Get-DateVal($Obj, [string]$Name) {
    $v = Get-Val $Obj $Name
    if (-not $v) { return $null }
    if ($v -is [datetime]) { return $v }
    try { return [datetime]::Parse([string]$v, $script:Inv, [System.Globalization.DateTimeStyles]::RoundtripKind) } catch { return $null }
}

function NowText { return (Get-Date).ToString('o') }

function Read-JsonFile([string]$P) {
    for ($i = 0; $i -lt 3; $i++) {
        try {
            if (-not [System.IO.File]::Exists($P)) { return $null }
            $o = [System.IO.File]::ReadAllText($P) | ConvertFrom-Json
            if ($o) { return $o }
            return $null
        } catch { Start-Sleep -Milliseconds 300 }
    }
    try { [System.IO.File]::Copy($P, $P + '.unreadable', $true) } catch {}
    Write-Log ("The file '" + $P + "' could not be read; starting it fresh.") 'WARN'
    return $null
}

function Save-JsonFile($Obj, [string]$P) {
    $tmp = $P + '.new'
    try {
        Ensure-Dir (Get-Parent $P)
        [System.IO.File]::WriteAllText($tmp, ($Obj | ConvertTo-Json -Depth 4))
        if ([System.IO.File]::Exists($P)) { [System.IO.File]::Replace($tmp, $P, [NullString]::Value) }
        else { [System.IO.File]::Move($tmp, $P) }
    } catch {
        Write-Log ("Couldn't save '" + $P + "': " + (Get-ErrText $_)) 'WARN'
    }
}

function Read-State {
    $o = Read-JsonFile (PathJoin $script:AppDir 'state.json')
    if (-not $o) { $o = [pscustomobject]@{ Created = (NowText) } }
    return $o
}

function Save-State($S) { Save-JsonFile $S (PathJoin $script:AppDir 'state.json') }

function Save-Config($C) { Save-JsonFile $C (PathJoin $script:AppDir 'config.json') }

# ----------------------------------------------------------------------------------------------
# Reading folders
# ----------------------------------------------------------------------------------------------

function Test-Excluded([string]$Name) {
    foreach ($p in $script:Excludes) { if ($Name -like $p) { return $true } }
    return $false
}

# True for junctions / symbolic links (e.g. the hidden legacy "My Music" link inside Documents).
# OneDrive cloud folders are also reparse points but are NOT links, so they are still backed up.
function Test-LinkFolder([string]$P) {
    try {
        $it = Get-Item -LiteralPath $P -Force -ErrorAction Stop
        return ($it.LinkType -eq 'Junction' -or $it.LinkType -eq 'SymbolicLink')
    } catch { return $true }
}

function Get-Tree([string]$Root, [switch]$NoExclude) {
    $files  = [System.Collections.Generic.Dictionary[string,System.IO.FileInfo]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $dirs   = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $failed = [System.Collections.Generic.List[string]]::new()
    $temps  = [System.Collections.Generic.List[string]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()
    $stack  = [System.Collections.Generic.Stack[string]]::new()
    $stack.Push('')
    while ($stack.Count -gt 0) {
        $rel = $stack.Pop()
        $full = PathJoin $Root $rel
        try {
            $di = [System.IO.DirectoryInfo]::new((ToLongPath $full))
            $subs = $di.GetDirectories()
            $fis = $di.GetFiles()
        } catch {
            $failed.Add($rel)
            $errors.Add(("Couldn't read the folder '{0}': {1}" -f $full, (Get-ErrText $_)))
            continue
        }
        foreach ($d in $subs) {
            if ($rel) { $cr = $rel + '\' + $d.Name } else { $cr = $d.Name }
            if (((([int]$d.Attributes) -band 0x400) -ne 0) -and (Test-LinkFolder $d.FullName)) { continue }
            [void]$dirs.Add($cr)
            $stack.Push($cr)
        }
        foreach ($f in $fis) {
            if ($rel) { $cr = $rel + '\' + $f.Name } else { $cr = $f.Name }
            if ($f.Name.EndsWith('.kgtmp', [System.StringComparison]::OrdinalIgnoreCase)) { $temps.Add($cr); continue }
            if (-not $NoExclude -and (Test-Excluded $f.Name)) { continue }
            $files[$cr] = $f
        }
    }
    return @{ Files = $files; Dirs = $dirs; Failed = $failed; Temps = $temps; Errors = $errors }
}

function Test-UnderFailed([string]$Rel, $Failed) {
    foreach ($f in $Failed) {
        if ($f -eq '') { return $true }
        if ($Rel.Equals($f, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        if ($Rel.StartsWith($f + '\', [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Test-Same($S, $D, [bool]$Fat) {
    if ($S.Length -ne $D.Length) { return $false }
    $diff = [Math]::Abs(($S.LastWriteTimeUtc - $D.LastWriteTimeUtc).TotalSeconds)
    if ($diff -le 2) { return $true }
    if ($Fat -and [Math]::Abs($diff - 3600) -le 2) { return $true }   # FAT32 daylight-saving shift
    return $false
}

# ----------------------------------------------------------------------------------------------
# Previous Versions folders
# ----------------------------------------------------------------------------------------------

function Get-VersionDir([hashtable]$Ctx) {
    if ($Ctx.Dir) { return $Ctx.Dir }
    $base = $Ctx.RunTime.ToString('yyyy-MM-dd (ddd) HH.mm', $script:Inv)
    $name = $base
    $i = 2
    while ([System.IO.Directory]::Exists((ToLongPath (PathJoin $Ctx.VersionsRoot $name)))) { $name = '{0} ({1})' -f $base, $i; $i++ }
    $dir = PathJoin $Ctx.VersionsRoot $name
    Ensure-Dir $dir
    $Ctx.Dir = $dir
    return $dir
}

function Get-FreeName([string]$P) {
    $parent = Get-Parent $P
    $name = $P.Substring($parent.TrimEnd('\').Length + 1)
    $dot = $name.LastIndexOf('.')
    if ($dot -le 0) { $base = $name; $ext = '' } else { $base = $name.Substring(0, $dot); $ext = $name.Substring($dot) }
    for ($i = 2; $i -lt 1000; $i++) {
        $c = PathJoin $parent ('{0} ({1}){2}' -f $base, $i, $ext)
        if (-not [System.IO.File]::Exists((ToLongPath $c))) { return $c }
    }
    throw 'too many copies with the same name'
}

function Get-VersionPath([hashtable]$Ctx, [string]$Rel) {
    $dir = Get-VersionDir $Ctx
    $p = PathJoin $dir $Rel
    Ensure-Dir (Get-Parent $p)
    if ([System.IO.File]::Exists((ToLongPath $p))) { $p = Get-FreeName $p }
    return $p
}

function Get-VersionInfo([string]$Name) {
    try {
        if ($Name -match '^(\d{4}-\d{2}-\d{2}) \(\w{3}\) (\d{2})\.(\d{2})(?: \((\d+)\))?$') {
            $d = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd', $script:Inv)
            $idx = 0
            if ($Matches[4]) { $idx = [int]$Matches[4] }
            return [pscustomobject]@{ Name = $Name; Kind = 'hour'; Date = $d; When = $d.AddHours([int]$Matches[2]).AddMinutes([int]$Matches[3]); Index = $idx }
        }
        if ($Name -match '^(\d{4}-\d{2}-\d{2}) \(week\)$') {
            $d = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd', $script:Inv)
            return [pscustomobject]@{ Name = $Name; Kind = 'week'; Date = $d; When = $d; Index = 0 }
        }
        if ($Name -match '^(\d{4}-\d{2}-\d{2}) \(\w{3}\)$') {
            $d = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd', $script:Inv)
            return [pscustomobject]@{ Name = $Name; Kind = 'day'; Date = $d; When = $d; Index = 0 }
        }
    } catch {}
    return $null
}

function Get-VersionFolders([string]$VersionsRoot) {
    if (-not [System.IO.Directory]::Exists((ToLongPath $VersionsRoot))) { return }
    foreach ($d in [System.IO.DirectoryInfo]::new((ToLongPath $VersionsRoot)).GetDirectories()) {
        $i = Get-VersionInfo $d.Name
        if ($i) { $i }
    }
}

# Combines several dated folders into one. The target (if it exists) and then the oldest folders
# win: for each file the OLDEST copy in the group is kept, newer duplicates within the group are
# dropped. That keeps one "as it was" copy per file per day (or per week).
function Merge-VersionFolders([string]$VersionsRoot, [string]$TargetName, [string[]]$OrderedNames) {
    $target = PathJoin $VersionsRoot $TargetName
    Ensure-Dir $target
    foreach ($name in $OrderedNames) {
        if ($name -eq $TargetName) { continue }
        $dir = PathJoin $VersionsRoot $name
        $t = Get-Tree $dir -NoExclude
        if ($t.Failed.Count -gt 0) { Write-Log ("Couldn't tidy the folder '" + $name + "' (part of it couldn't be read) - left as it is.") 'WARN'; continue }
        foreach ($kv in $t.Files.GetEnumerator()) {
            $dst = PathJoin $target $kv.Key
            $srcp = PathJoin $dir $kv.Key
            if ([System.IO.File]::Exists((ToLongPath $dst))) { Remove-FileForce $srcp }
            else {
                Ensure-Dir (Get-Parent $dst)
                [System.IO.File]::Move((ToLongPath $srcp), (ToLongPath $dst))
            }
        }
        foreach ($tmpRel in $t.Temps) { try { Remove-FileForce (PathJoin $dir $tmpRel) } catch {} }
        Remove-EmptyTree $dir
    }
}

# Hour-by-hour folders are kept for 14 days, then combined into one folder per day.
# Day folders are kept for 180 days, then combined into one folder per week. Weeks are kept.
function Invoke-Retention([string]$VersionsRoot, [datetime]$Now, [int]$HourlyDays = 14, [int]$DailyDays = 180) {
    $all = @(Get-VersionFolders $VersionsRoot)
    $cut1 = $Now.Date.AddDays(-$HourlyDays)
    $old = @($all | Where-Object { ($_.Kind -eq 'hour' -or $_.Kind -eq 'day') -and $_.Date -lt $cut1 })
    foreach ($g in @($old | Group-Object { $_.Date.ToString('yyyy-MM-dd', $script:Inv) })) {
        $items = @($g.Group)
        if (-not ($items | Where-Object { $_.Kind -eq 'hour' })) { continue }
        $target = $items[0].Date.ToString('yyyy-MM-dd (ddd)', $script:Inv)
        $ordered = @($items | Sort-Object @{ Expression = { if ($_.Kind -eq 'day') { 0 } else { 1 } } }, When, Index | ForEach-Object { $_.Name })
        try {
            Merge-VersionFolders $VersionsRoot $target $ordered
            Write-Log ('Combined the hourly versions from ' + $g.Name + ' into one folder for that day.')
        } catch { Write-Log ('Could not combine versions from ' + $g.Name + ': ' + (Get-ErrText $_)) 'WARN' }
    }

    $all = @(Get-VersionFolders $VersionsRoot)
    $cut2 = $Now.Date.AddDays(-$DailyDays)
    $old = @($all | Where-Object { $_.Kind -eq 'day' -or $_.Kind -eq 'week' })
    foreach ($g in @($old | Group-Object { $_.Date.AddDays(-(([int]$_.Date.DayOfWeek + 6) % 7)).ToString('yyyy-MM-dd', $script:Inv) })) {
        $items = @($g.Group)
        if (-not ($items | Where-Object { $_.Kind -eq 'day' })) { continue }
        $newest = ($items | Sort-Object Date -Descending | Select-Object -First 1).Date
        if ($newest -ge $cut2) { continue }
        $target = $g.Name + ' (week)'
        $ordered = @($items | Sort-Object @{ Expression = { if ($_.Kind -eq 'week') { 0 } else { 1 } } }, When | ForEach-Object { $_.Name })
        try {
            Merge-VersionFolders $VersionsRoot $target $ordered
            Write-Log ('Combined the daily versions for the week of ' + $g.Name + ' into one folder.')
        } catch { Write-Log ('Could not combine versions for the week of ' + $g.Name + ': ' + (Get-ErrText $_)) 'WARN' }
    }
}

# Only if the drive is nearly full: remove the OLDEST version folders (never the last 30 days,
# never Current Documents) until there is room again.
function Invoke-SpacePrune([string]$DriveRoot, [string]$VersionsRoot, [datetime]$Now) {
    $di = [System.IO.DriveInfo]::new($DriveRoot)
    $min = [Math]::Max([long]2GB, [long]($di.TotalSize * 0.02))
    if ($di.AvailableFreeSpace -ge $min) { return 0 }
    $keepFrom = $Now.Date.AddDays(-30)
    $removed = 0
    foreach ($v in @(Get-VersionFolders $VersionsRoot | Where-Object { $_.Date -lt $keepFrom } | Sort-Object When)) {
        if ([System.IO.DriveInfo]::new($DriveRoot).AvailableFreeSpace -ge $min) { break }
        try {
            Remove-TreeForce (PathJoin $VersionsRoot $v.Name)
            $removed++
            Write-Log ("The backup drive is nearly full: removed the oldest previous-versions folder '" + $v.Name + "'.") 'WARN'
        } catch { Write-Log ("Couldn't remove '" + $v.Name + "': " + (Get-ErrText $_)) 'WARN' }
    }
    return $removed
}

# ----------------------------------------------------------------------------------------------
# The copy engine
# ----------------------------------------------------------------------------------------------

# Copies one file to <Dst>.kgtmp, checks the copy, moves the old backup copy (if any) into
# Previous Versions, then puts the new copy in place. Returns $true when the file was updated.
function Copy-OneFile {
    param([string]$Src, [string]$Dst, [hashtable]$Ctx, [string]$Rel, [hashtable]$R)
    $tmp = $Dst + '.kgtmp'
    $in = $null; $out = $null; $sha = $null
    try {
        $before = [System.IO.FileInfo]::new((ToLongPath $Src))
        $len0 = $before.Length
        $mt0 = $before.LastWriteTimeUtc
        Ensure-Dir (Get-Parent $Dst)
        if ([System.IO.File]::Exists((ToLongPath $tmp))) { Remove-FileForce $tmp }
        $share = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
        $in = [System.IO.FileStream]::new((ToLongPath $Src), [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $share, 1048576)
        $out = [System.IO.FileStream]::new((ToLongPath $tmp), [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None, 1048576)
        $verify = ($len0 -le $script:HashLimit)
        if ($verify) { $sha = [System.Security.Cryptography.SHA256]::Create() }
        $buf = $script:CopyBuffer
        while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
            if ($verify) { [void]$sha.TransformBlock($buf, 0, $n, $null, 0) }
            $out.Write($buf, 0, $n)
        }
        $out.Flush($true)
        $out.Dispose(); $out = $null
        $in.Dispose(); $in = $null

        $after = [System.IO.FileInfo]::new((ToLongPath $Src))
        if ($after.Length -ne $len0 -or $after.LastWriteTimeUtc -ne $mt0) {
            # Being saved while we copied - try again next run.
            Remove-FileForce $tmp
            $R.ChangedDuring.Add($Rel)
            return $false
        }
        $copied = [System.IO.FileInfo]::new((ToLongPath $tmp))
        if ($copied.Length -ne $len0) { throw ('the copy is {0} bytes but the original is {1} bytes' -f $copied.Length, $len0) }
        if ($verify) {
            [void]$sha.TransformFinalBlock($buf, 0, 0)
            $h1 = [System.BitConverter]::ToString($sha.Hash)
            $h2 = Get-Sha256 $tmp
            if ($h1 -ne $h2) { throw 'the copy did not match the original when it was checked' }
        }
        [System.IO.File]::SetLastWriteTimeUtc((ToLongPath $tmp), $mt0)
        if ([System.IO.File]::Exists((ToLongPath $Dst))) {
            $vp = Get-VersionPath $Ctx $Rel
            [System.IO.File]::Move((ToLongPath $Dst), (ToLongPath $vp))
        }
        [System.IO.File]::Move((ToLongPath $tmp), (ToLongPath $Dst))
        return $true
    }
    catch {
        $err = $_
        if ($out) { try { $out.Dispose() } catch {}; $out = $null }
        if ($in) { try { $in.Dispose() } catch {}; $in = $null }
        try { if ([System.IO.File]::Exists((ToLongPath $tmp))) { Remove-FileForce $tmp } } catch {}
        if (Test-LockedError $err) { $R.Locked.Add($Rel) }
        else { $R.Errors.Add(("'{0}': {1}" -f $Rel, (Get-ErrText $err))) }
        return $false
    }
    finally {
        if ($sha) { $sha.Dispose() }
        if ($out) { $out.Dispose() }
        if ($in) { $in.Dispose() }
    }
}

function New-Result {
    return @{
        New = 0; Updated = 0; Removed = 0; Unchanged = 0; Verified = 0; Repaired = 0
        CopiedBytes = [long]0; SourceFiles = 0; SourceBytes = [long]0
        Aborted = $false; AbortReason = ''; VersionFolder = $null
        Locked = [System.Collections.Generic.List[string]]::new()
        Errors = [System.Collections.Generic.List[string]]::new()
        ChangedDuring = [System.Collections.Generic.List[string]]::new()
    }
}

function Invoke-Sync {
    param([string]$SourceRoot, [string]$CurrentRoot, [string]$VersionsRoot, [datetime]$RunTime, [bool]$Fat = $false, [int]$DeepVerifyCount = 0)
    $R = New-Result
    if (-not [System.IO.Directory]::Exists((ToLongPath $SourceRoot))) {
        $R.Aborted = $true; $R.AbortReason = "the Documents folder '$SourceRoot' could not be found"
        return $R
    }
    Ensure-Dir $CurrentRoot
    Ensure-Dir $VersionsRoot
    $src = Get-Tree $SourceRoot
    if ($src.Failed.Contains('')) {
        $R.Aborted = $true; $R.AbortReason = 'the Documents folder could not be read: ' + ($src.Errors -join '; ')
        return $R
    }
    $cur = Get-Tree $CurrentRoot
    if ($cur.Failed.Contains('')) {
        $R.Aborted = $true; $R.AbortReason = 'the backup copy could not be read: ' + ($cur.Errors -join '; ')
        return $R
    }
    foreach ($t in $cur.Temps) { try { Remove-FileForce (PathJoin $CurrentRoot $t) } catch {} }
    foreach ($e in $src.Errors) { $R.Errors.Add($e) }
    $R.SourceFiles = $src.Files.Count
    foreach ($f in $src.Files.Values) { $R.SourceBytes += $f.Length }

    if ($src.Files.Count -eq 0 -and $cur.Files.Count -gt 0) {
        $R.Aborted = $true
        $R.AbortReason = ('Documents looks empty while the backup holds {0:N0} files, so nothing was changed in the backup, to be safe' -f $cur.Files.Count)
        return $R
    }

    $ctx = @{ VersionsRoot = $VersionsRoot; RunTime = $RunTime; Dir = $null }
    $plan = [System.Collections.Generic.List[string]]::new()
    $unchanged = [System.Collections.Generic.List[string]]::new()
    $planBytes = [long]0
    foreach ($kv in $src.Files.GetEnumerator()) {
        $existing = $null
        if ($cur.Files.TryGetValue($kv.Key, [ref]$existing)) {
            if (Test-Same $kv.Value $existing $Fat) { $unchanged.Add($kv.Key); continue }
        }
        $plan.Add($kv.Key)
        $planBytes += $kv.Value.Length
    }
    $R.Unchanged = $unchanged.Count
    $toRemove = @(foreach ($k in $cur.Files.Keys) { if (-not $src.Files.ContainsKey($k) -and -not (Test-UnderFailed $k $src.Failed)) { $k } })

    if ($script:Interactive) {
        Write-Host ('  Documents has {0:N0} files ({1}). To copy: {2:N0} ({3}). Removed since last time: {4:N0}.' -f $src.Files.Count, (Format-Size $R.SourceBytes), $plan.Count, (Format-Size $planBytes), $toRemove.Count)
    }

    $i = 0
    $doneBytes = [long]0
    $lastShow = [DateTime]::UtcNow
    foreach ($rel in $plan) {
        $i++
        $isNew = -not $cur.Files.ContainsKey($rel)
        $len = $src.Files[$rel].Length
        $ok = Copy-OneFile -Src (PathJoin $SourceRoot $rel) -Dst (PathJoin $CurrentRoot $rel) -Ctx $ctx -Rel $rel -R $R
        if ($ok -eq $true) {
            if ($isNew) { $R.New++ } else { $R.Updated++ }
            $R.CopiedBytes += $len
        }
        $doneBytes += $len
        if ($script:Interactive -and ((([DateTime]::UtcNow - $lastShow).TotalSeconds -ge 3) -or $i -eq $plan.Count)) {
            Write-Host ('    copied {0:N0} of {1:N0} files  ({2} of {3})' -f $i, $plan.Count, (Format-Size $doneBytes), (Format-Size $planBytes))
            $lastShow = [DateTime]::UtcNow
        }
    }

    foreach ($rel in $toRemove) {
        try {
            $p = PathJoin $CurrentRoot $rel
            if ([System.IO.File]::Exists((ToLongPath $p))) {
                $vp = Get-VersionPath $ctx $rel
                [System.IO.File]::Move((ToLongPath $p), (ToLongPath $vp))
            }
            $R.Removed++
        } catch {
            if (Test-LockedError $_) { $R.Locked.Add($rel) }
            else { $R.Errors.Add(("Couldn't move the removed file '{0}' into Previous Versions: {1}" -f $rel, (Get-ErrText $_))) }
        }
    }

    foreach ($d in $src.Dirs) {
        if (-not $cur.Dirs.Contains($d)) {
            try { Ensure-Dir (PathJoin $CurrentRoot $d) } catch { $R.Errors.Add(("Couldn't create the folder '{0}': {1}" -f $d, (Get-ErrText $_))) }
        }
    }
    $goneDirs = @($cur.Dirs | Where-Object { -not $src.Dirs.Contains($_) -and -not (Test-UnderFailed $_ $src.Failed) } | Sort-Object { $_.Length } -Descending)
    foreach ($d in $goneDirs) {
        try {
            $di = [System.IO.DirectoryInfo]::new((ToLongPath (PathJoin $CurrentRoot $d)))
            if ($di.Exists -and $di.GetFileSystemInfos().Length -eq 0) { $di.Delete() }
        } catch {}
    }

    if ($DeepVerifyCount -gt 0 -and $unchanged.Count -gt 0) {
        $cands = @($unchanged | Sort-Object { $src.Files[$_].LastWriteTimeUtc } -Descending | Select-Object -First $DeepVerifyCount)
        foreach ($rel in $cands) {
            if ($src.Files[$rel].Length -gt $script:HashLimit) { continue }
            try {
                $h1 = Get-Sha256 (PathJoin $SourceRoot $rel)
                $h2 = Get-Sha256 (PathJoin $CurrentRoot $rel)
                $R.Verified++
                if ($h1 -ne $h2) {
                    Write-Log ("The backup copy of '" + $rel + "' didn't match the original - copying it again.") 'WARN'
                    $ok = Copy-OneFile -Src (PathJoin $SourceRoot $rel) -Dst (PathJoin $CurrentRoot $rel) -Ctx $ctx -Rel $rel -R $R
                    if ($ok -eq $true) { $R.Repaired++ }
                }
            } catch {
                if (-not (Test-LockedError $_)) { $R.Errors.Add(("Couldn't double-check '{0}': {1}" -f $rel, (Get-ErrText $_))) }
            }
        }
    }
    $R.VersionFolder = $ctx.Dir
    return $R
}

# ----------------------------------------------------------------------------------------------
# Backup drive, settings, status files
# ----------------------------------------------------------------------------------------------

function Find-BackupDrive([string]$DriveId) {
    foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
        try {
            if ($d.DriveType -ne [System.IO.DriveType]::Fixed -and $d.DriveType -ne [System.IO.DriveType]::Removable) { continue }
            if (-not $d.IsReady) { continue }
            $m = PathJoin $d.RootDirectory.FullName $script:MarkerName
            if (-not [System.IO.File]::Exists($m)) { continue }
            $j = [System.IO.File]::ReadAllText($m) | ConvertFrom-Json
            if (-not $DriveId -or $j.Id -eq $DriveId) { return [pscustomobject]@{ Root = $d.RootDirectory.FullName; Drive = $d; Marker = $j } }
        } catch {}
    }
    return $null
}

function Read-Config {
    $c = Read-JsonFile (PathJoin $script:AppDir 'config.json')
    if ($c -and (Get-Val $c 'DriveId')) { return $c }
    # Self-repair: rebuild the settings from the marker file on the backup drive.
    $d = Find-BackupDrive $null
    if ($d) {
        $c = [pscustomobject]@{
            Version = $script:Version; DriveId = $d.Marker.Id; BackupFolderName = $d.Marker.BackupFolderName
            Documents = [Environment]::GetFolderPath('MyDocuments'); InstalledAt = (NowText); User = "$env:COMPUTERNAME\$env:USERNAME"
        }
        Save-Config $c
        Write-Log 'The settings file was missing, so it was rebuilt from the backup drive.' 'WARN'
        return $c
    }
    return $null
}

function Resolve-Documents($Cfg) {
    $p = [Environment]::GetFolderPath('MyDocuments')
    if (-not $p -or -not [System.IO.Directory]::Exists($p)) { $p = $Cfg.Documents }
    if ($p -and $Cfg.Documents -and ($p -ne $Cfg.Documents)) {
        Write-Log ("The Documents folder moved from '" + $Cfg.Documents + "' to '" + $p + "' - backing up the new location.") 'WARN'
        Set-Val $Cfg 'Documents' $p
        Save-Config $Cfg
    }
    return $p
}

function Get-ResultText($R) {
    if ($R.Aborted) { return ('NOT DONE - ' + $R.AbortReason) }
    $parts = @()
    if ($R.New) { $parts += ('{0:N0} new' -f $R.New) }
    if ($R.Updated) { $parts += ('{0:N0} changed' -f $R.Updated) }
    if ($R.Removed) { $parts += ('{0:N0} removed (kept in Previous Versions)' -f $R.Removed) }
    if ($R.Repaired) { $parts += ('{0:N0} damaged copies repaired' -f $R.Repaired) }
    if ($parts.Count -eq 0) { $t = 'Up to date - nothing changed since the last backup' }
    else { $t = 'Backed up: ' + ($parts -join ', ') }
    if ($R.Locked.Count -or $R.Errors.Count) { $t += ' (some files need another try - see below)' }
    return $t
}

function Write-RestoreGuide([string]$BackupRoot) {
    $p = PathJoin $BackupRoot 'How to Restore.txt'
    $lines = @(
        'HOW TO GET A FILE BACK'
        '======================'
        ''
        '"Current Documents" is an exact copy of your Documents folder as of the last backup.'
        '(The time of the last backup is in "Backup Status.txt".)'
        ''
        '"Previous Versions" holds older copies. Each folder is named with the date (and time)'
        'a change was backed up, and holds those files exactly as they were BEFORE that change,'
        'or before they were deleted. To go back to an older draft, open the folder from around'
        'the date you want and copy the file out.'
        ''
        'How long versions are kept:'
        '  - hour by hour for the last 2 weeks'
        '  - then one copy per day for 6 months'
        '  - then one copy per week, kept indefinitely'
        '  Nothing is thrown away unless the drive is nearly full, and even then the last'
        '  30 days are always kept.'
        ''
        'Tips:'
        '  - COPY files out of the backup to your Desktop or Documents; do not edit them here.'
        '  - Your original files are never changed, moved or deleted by the backup.'
        '  - Backups run by themselves about every hour while you are signed in, and only copy'
        '    what changed. If the drive is unplugged, it simply catches up next time.'
        ''
        'Set up by Nick Knight, Knight Logics.'
    )
    try { [System.IO.File]::WriteAllText((ToLongPath $p), ($lines -join "`r`n")) } catch {}
}

function Write-StatusFiles([string]$BackupRoot, [string]$DriveRoot, [string]$Docs, $R) {
    try {
        $di = [System.IO.DriveInfo]::new($DriveRoot)
        $verCount = @(Get-VersionFolders (PathJoin $BackupRoot $script:VersionsName)).Count
        $lines = @(
            ('BACKUP STATUS - ' + $env:USERNAME + "'s Documents")
            ''
            ('Last checked:       ' + (Get-Date).ToString('dddd, MMMM d, yyyy   h:mm tt', $script:Inv))
            ('Result:             ' + (Get-ResultText $R))
            ('Backing up:         ' + $Docs)
            ('Size of Documents:  {0:N0} files ({1})' -f $R.SourceFiles, (Format-Size $R.SourceBytes))
            ('Previous versions:  {0:N0} dated folders' -f $verCount)
            ('Drive space:        ' + (Format-Size $di.AvailableFreeSpace) + ' free of ' + (Format-Size $di.TotalSize))
            'Schedule:           about every hour while signed in, and at sign-in. Only changed files are copied.'
        )
        if ($R.Locked.Count -gt 0) {
            $lines += ''
            $lines += 'Not copied this time because the file was open in another program (it will be retried):'
            foreach ($x in @($R.Locked | Select-Object -First 20)) { $lines += ('  ' + $x) }
        }
        if ($R.ChangedDuring.Count -gt 0) {
            $lines += ''
            $lines += 'Being saved while the backup ran (it will be retried):'
            foreach ($x in @($R.ChangedDuring | Select-Object -First 20)) { $lines += ('  ' + $x) }
        }
        if ($R.Errors.Count -gt 0) {
            $lines += ''
            $lines += 'Problems:'
            foreach ($x in @($R.Errors | Select-Object -First 20)) { $lines += ('  ' + $x) }
        }
        [System.IO.File]::WriteAllText((ToLongPath (PathJoin $BackupRoot 'Backup Status.txt')), ($lines -join "`r`n"), [System.Text.Encoding]::UTF8)

        $changed = ($R.New + $R.Updated + $R.Removed + $R.Repaired) -gt 0
        if ($changed -or $R.Aborted -or $R.Locked.Count -or $R.Errors.Count) {
            $h = '{0}   {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm', $script:Inv), (Get-ResultText $R)
            [System.IO.File]::AppendAllText((ToLongPath (PathJoin $BackupRoot 'Backup History.txt')), $h + "`r`n", [System.Text.Encoding]::UTF8)
        }
    } catch { Write-Log ("Couldn't write the status file: " + (Get-ErrText $_)) 'WARN' }
}

# ----------------------------------------------------------------------------------------------
# Reminders (Windows notifications) - only when something needs Stephen's attention
# ----------------------------------------------------------------------------------------------

function Show-Reminder([string]$Title, [string]$Body) {
    try {
        [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $t = [System.Security.SecurityElement]::Escape($Title)
        $b = [System.Security.SecurityElement]::Escape($Body)
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml("<toast><visual><binding template='ToastGeneric'><text>$t</text><text>$b</text></binding></visual></toast>")
        $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
        Write-Log ('Reminder shown: ' + $Title)
        return $true
    } catch {
        Write-Log ("Couldn't show a reminder: " + (Get-ErrText $_)) 'WARN'
        return $false
    }
}

function Invoke-Reminder($State, $Cfg, [string]$Kind, [string]$Body) {
    if ($Mode -ne 'Auto' -and $Mode -ne 'Repair') { return }
    $now = Get-Date
    $key = 'LastReminder' + $Kind
    $gap = 20
    if ($Kind -eq 'Problems') { $gap = 70 }
    $prev = Get-DateVal $State $key
    if ($prev -and ($now - $prev).TotalHours -lt $gap) { return }
    $lastOk = Get-DateVal $State 'LastCompleted'
    if (-not $lastOk) { $lastOk = Get-DateVal $Cfg 'InstalledAt' }
    $title = $null
    switch ($Kind) {
        'DriveMissing' {
            if ($lastOk -and ($now - $lastOk).TotalDays -ge 3) {
                $title = 'Backup drive not connected'
                $Body = 'Your Documents were last backed up on ' + $lastOk.ToString('dddd, MMMM d', $script:Inv) + '. Plug in your backup drive and the backup will catch up by itself.'
            }
        }
        'Failing' {
            if ($lastOk -and ($now - $lastOk).TotalDays -ge 2) { $title = 'Your backup needs attention' }
        }
        'Problems' { $title = 'Some files could not be backed up' }
        'LowSpace' { $title = 'Backup drive almost full' }
    }
    if ($title -and (Show-Reminder $title $Body)) {
        Set-Val $State $key (NowText)
        Save-State $State
    }
}

# ----------------------------------------------------------------------------------------------
# Schedule and self-repair
# ----------------------------------------------------------------------------------------------

function Get-LauncherText {
    $lines = @(
        "' Knight Logics - Documents Backup. Starts the backup with no window at all."
        'Option Explicit'
        'Dim sh, fso, here, mode, ps, cmd'
        'Set sh = CreateObject("WScript.Shell")'
        'Set fso = CreateObject("Scripting.FileSystemObject")'
        'here = fso.GetParentFolderName(WScript.ScriptFullName)'
        'mode = "Auto"'
        'If WScript.Arguments.Count > 0 Then mode = WScript.Arguments(0)'
        'ps = sh.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"'
        'cmd = """" & ps & """ -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & here & "\DocumentsBackup.ps1"" -Mode " & mode'
        'WScript.Quit sh.Run(cmd, 0, True)'
    )
    return ($lines -join "`r`n") + "`r`n"
}

function Write-Launcher {
    $p = PathJoin $script:AppDir 'RunHidden.vbs'
    $text = Get-LauncherText
    $existing = $null
    try { if ([System.IO.File]::Exists($p)) { $existing = [System.IO.File]::ReadAllText($p) } } catch {}
    if ($existing -ne $text) { [System.IO.File]::WriteAllText($p, $text, [System.Text.Encoding]::ASCII) }
}

function Get-TaskXml {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $sid = $id.User.Value
    $name = [System.Security.SecurityElement]::Escape($id.Name)
    $launcher = [System.Security.SecurityElement]::Escape((PathJoin $script:AppDir 'RunHidden.vbs'))
    $wscript = [System.Security.SecurityElement]::Escape((PathJoin $env:SystemRoot 'System32\wscript.exe'))
    $start = (Get-Date).AddMinutes(10).ToString("yyyy-MM-dd'T'HH:mm:ss", $script:Inv)
    return @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Author>Knight Logics</Author>
    <Description>Backs up Documents to the external backup drive about every hour (only what changed). Set up by Nick Knight, Knight Logics.</Description>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>$name</UserId>
      <Delay>PT5M</Delay>
    </LogonTrigger>
    <TimeTrigger>
      <Repetition>
        <Interval>PT1H</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
      <StartBoundary>$start</StartBoundary>
      <Enabled>true</Enabled>
    </TimeTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$sid</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT6H</ExecutionTimeLimit>
    <Priority>7</Priority>
    <RestartOnFailure>
      <Interval>PT15M</Interval>
      <Count>3</Count>
    </RestartOnFailure>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$wscript</Command>
      <Arguments>"$launcher" Auto</Arguments>
    </Exec>
  </Actions>
</Task>
"@
}

function Register-BackupTask {
    Write-Launcher
    $xml = Get-TaskXml
    try {
        Register-ScheduledTask -TaskName $script:TaskName -Xml $xml -Force -ErrorAction Stop | Out-Null
        return
    } catch {
        $first = Get-ErrText $_
        $xf = PathJoin $script:AppDir 'task.xml'
        [System.IO.File]::WriteAllText($xf, $xml, [System.Text.Encoding]::Unicode)
        $old = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $out = & schtasks.exe /Create /TN $script:TaskName /XML $xf /F 2>&1
        $code = $LASTEXITCODE
        $ErrorActionPreference = $old
        if ($code -ne 0) { throw ('Could not create the scheduled task: ' + $first + ' / ' + ($out -join ' ')) }
    }
}

function Set-RunKey {
    $cmd = '"' + (PathJoin $env:SystemRoot 'System32\wscript.exe') + '" "' + (PathJoin $script:AppDir 'RunHidden.vbs') + '" Repair'
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $cur = (Get-ItemProperty -Path $key -Name $script:RunKeyName -ErrorAction SilentlyContinue).($script:RunKeyName)
    if ($cur -ne $cmd) { Set-ItemProperty -Path $key -Name $script:RunKeyName -Value $cmd }
}

# Checks that the hourly task exists, is enabled and points at this program; fixes it if not.
function Repair-Schedule {
    try {
        Write-Launcher
        $launcher = PathJoin $script:AppDir 'RunHidden.vbs'
        $t = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
        $ok = $false
        if ($t -and $t.State -ne 'Disabled') {
            $a = @($t.Actions)[0]
            if ($a -and $a.Arguments -and $a.Arguments.IndexOf($launcher, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $ok = $true }
            if (@($t.Triggers).Count -lt 2) { $ok = $false }
        }
        if (-not $ok) {
            if ($t) { $why = 'changed or turned off' } else { $why = 'missing' }
            Write-Log ('The automatic backup schedule was ' + $why + ' - restoring it.') 'WARN'
            Register-BackupTask
        }
    } catch { Write-Log ("Couldn't check the schedule: " + (Get-ErrText $_)) 'WARN' }
    try { Set-RunKey } catch { Write-Log ("Couldn't check the sign-in entry: " + (Get-ErrText $_)) 'WARN' }
}

function Get-RunLock {
    $lockPath = PathJoin $script:AppDir 'backup.lock'
    $infoPath = PathJoin $script:AppDir 'backup.lock.info'
    for ($attempt = 0; $attempt -lt 2; $attempt++) {
        try {
            $fs = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            [System.IO.File]::WriteAllText($infoPath, ('{0}|{1}' -f $PID, (NowText)))
            return $fs
        } catch {
            try {
                $info = ([System.IO.File]::ReadAllText($infoPath)).Split('|')
                $opid = [int]$info[0]
                $since = [datetime]::Parse($info[1], $script:Inv, [System.Globalization.DateTimeStyles]::RoundtripKind)
                if (((Get-Date) - $since).TotalHours -ge 6) {
                    $p = Get-CimInstance Win32_Process -Filter "ProcessId=$opid" -ErrorAction SilentlyContinue
                    if ($p -and $p.CommandLine -and $p.CommandLine.IndexOf('DocumentsBackup.ps1', [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                        Stop-Process -Id $opid -Force -ErrorAction SilentlyContinue
                        Write-Log ("A backup had been stuck for over 6 hours (process $opid) - stopped it so backups can continue.") 'WARN'
                        Start-Sleep -Seconds 3
                        continue
                    }
                }
            } catch {}
            return $null
        }
    }
    return $null
}

# ----------------------------------------------------------------------------------------------
# One backup run
# ----------------------------------------------------------------------------------------------

function Invoke-Backup([switch]$Manual) {
    Ensure-Dir $script:AppDir
    $state = Read-State
    Set-Val $state 'LastLaunch' (NowText)
    Set-Val $state 'LastLaunchMode' $Mode
    Save-State $state

    $lock = Get-RunLock
    if (-not $lock) {
        Write-Log 'Another backup is already running - skipping this one.'
        return $null
    }
    $cfg = $null
    try {
        if ([System.IO.File]::Exists((PathJoin $script:AppDir 'PAUSED'))) { Write-Log 'Backups are paused (a PAUSED file is in the program folder).'; return $null }
        if (-not $Manual) {
            $last = Get-DateVal $state 'LastCompleted'
            if ($last -and ((Get-Date) - $last).TotalMinutes -lt 20 -and ((Get-Date) - $last).TotalMinutes -ge 0) { return $null }
        }
        $cfg = Read-Config
        if (-not $cfg) { Write-Log 'Not set up yet: no settings file and no backup drive found.' 'ERROR'; return $null }
        $docs = Resolve-Documents $cfg

        $drive = Find-BackupDrive $cfg.DriveId
        if (-not $drive) {
            Write-Log 'The backup drive is not connected - will try again next hour.'
            if (-not (Get-Val $state 'DriveMissingSince')) { Set-Val $state 'DriveMissingSince' (NowText) }
            Save-State $state
            Invoke-Reminder $state $cfg 'DriveMissing' ''
            return $null
        }
        Set-Val $state 'DriveMissingSince' ''
        $folderName = $cfg.BackupFolderName
        if (-not $folderName) { $folderName = $drive.Marker.BackupFolderName }
        $root = PathJoin $drive.Root $folderName
        $currentRoot = PathJoin $root $script:CurrentName
        $versionsRoot = PathJoin $root $script:VersionsName
        if (-not [System.IO.Directory]::Exists((ToLongPath $root))) { Write-Log ("The backup folder was missing on the drive, so it was created again: " + $root) 'WARN' }
        Ensure-Dir $currentRoot
        Ensure-Dir $versionsRoot
        $probe = PathJoin $root ('write-test-' + $PID + '.kgtmp')
        [System.IO.File]::WriteAllText($probe, 'test')
        Remove-FileForce $probe
        if ($script:Interactive) { Write-Host ('  Backup drive: ' + $drive.Root + '   Backup folder: ' + $root) }

        Invoke-Retention $versionsRoot (Get-Date)
        [void](Invoke-SpacePrune $drive.Root $versionsRoot (Get-Date))

        $deep = 0
        $lastDeep = Get-DateVal $state 'LastDeepVerify'
        if (-not $lastDeep -or ((Get-Date) - $lastDeep).TotalDays -ge 7) { $deep = 300 }
        $fat = $false
        try { $fat = ($drive.Drive.DriveFormat -eq 'FAT32' -or $drive.Drive.DriveFormat -eq 'FAT') } catch {}

        $started = Get-Date
        $r = Invoke-Sync -SourceRoot $docs -CurrentRoot $currentRoot -VersionsRoot $versionsRoot -RunTime $started -Fat $fat -DeepVerifyCount $deep
        $secs = [int]((Get-Date) - $started).TotalSeconds
        Write-StatusFiles $root $drive.Root $docs $r
        if ([System.IO.File]::Exists((ToLongPath (PathJoin $root 'How to Restore.txt'))) -eq $false -or $Manual) { Write-RestoreGuide $root }

        $summary = Get-ResultText $r
        if ($r.Aborted) {
            Write-Log ('Backup did not run: ' + $r.AbortReason) 'ERROR'
            Set-Val $state 'LastError' ('{0}  {1}' -f (NowText), $r.AbortReason)
            Save-State $state
            Invoke-Reminder $state $cfg 'Failing' 'The automatic backup of your Documents found a problem and paused to keep your backup safe. Please let Nick know.'
            return $r
        }
        $lvl = 'INFO'
        if ($r.Errors.Count) { $lvl = 'WARN' }
        Write-Log ('{0}  [{1:N0} files checked, {2} copied, {3} s]' -f $summary, $r.SourceFiles, (Format-Size $r.CopiedBytes), $secs) $lvl
        foreach ($x in @($r.Locked | Select-Object -First 10)) { Write-Log ('In use, will retry: ' + $x) }
        foreach ($x in @($r.Errors | Select-Object -First 10)) { Write-Log ('Problem: ' + $x) 'WARN' }

        Set-Val $state 'LastCompleted' (NowText)
        Set-Val $state 'LastResult' $summary
        Set-Val $state 'LastFiles' $r.SourceFiles
        Set-Val $state 'LastLocked' (@($r.Locked | Select-Object -First 20) -join ' | ')
        Set-Val $state 'LastErrors' (@($r.Errors | Select-Object -First 20) -join ' | ')
        Set-Val $state 'LastError' ''
        Set-Val $state 'BackupFolder' $root
        if ($r.Errors.Count -eq 0 -and $r.Locked.Count -eq 0) { Set-Val $state 'LastClean' (NowText) }
        if ($deep -gt 0) { Set-Val $state 'LastDeepVerify' (NowText) }
        Save-State $state

        # Outlook mailbox files are normally open all day; they are listed in the status file but
        # never trigger a reminder on their own.
        $lockedDocs = @($r.Locked | Where-Object { $_ -notlike '*.pst' })
        $problems = $r.Errors.Count + $lockedDocs.Count
        if ($problems -gt 0) {
            $clean = Get-DateVal $state 'LastClean'
            if (-not $clean) { $clean = Get-DateVal $cfg 'InstalledAt' }
            if ($clean -and ((Get-Date) - $clean).TotalDays -ge 3) {
                $example = @($lockedDocs) + @($r.Errors) | Select-Object -First 1
                Invoke-Reminder $state $cfg 'Problems' ('{0} file(s) could not be backed up for a few days, for example {1}. Closing the program that has it open usually fixes this. If it keeps happening, let Nick know.' -f $problems, $example)
            }
        }
        try {
            $di = [System.IO.DriveInfo]::new($drive.Root)
            if ($di.AvailableFreeSpace -lt [Math]::Max([long]2GB, [long]($di.TotalSize * 0.02))) {
                Invoke-Reminder $state $cfg 'LowSpace' ('Only ' + (Format-Size $di.AvailableFreeSpace) + ' is left on the backup drive. Please let Nick know.')
            }
        } catch {}
        try {
            foreach ($old in @(Get-ChildItem -LiteralPath $script:LogDir -Filter 'backup-*.log' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-400) })) { Remove-Item -LiteralPath $old.FullName -Force -ErrorAction SilentlyContinue }
        } catch {}
        return $r
    }
    catch {
        $msg = Get-ErrText $_
        Write-Log ('The backup stopped because of an unexpected problem: ' + $msg + ' ' + $_.InvocationInfo.PositionMessage) 'ERROR'
        Set-Val $state 'LastError' ('{0}  {1}' -f (NowText), $msg)
        Save-State $state
        if ($cfg) { Invoke-Reminder $state $cfg 'Failing' 'The automatic backup of your Documents has not been able to finish for a couple of days. Please let Nick know.' }
        return $null
    }
    finally {
        if ($lock) { $lock.Dispose() }
    }
}

# ----------------------------------------------------------------------------------------------
# Self-test on sample files (never touches real files)
# ----------------------------------------------------------------------------------------------

function Invoke-SelfTest {
    $root = PathJoin ([System.IO.Path]::GetTempPath().TrimEnd('\')) ('KL-Backup-SelfTest-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $src = PathJoin $root 'Documents'
    $cur = PathJoin $root 'Backup\Current Documents'
    $ver = PathJoin $root 'Backup\Previous Versions'
    $res = @{ Passed = 0; Failed = 0; Notes = [System.Collections.Generic.List[string]]::new() }
    $check = {
        param($ok, [string]$label)
        if ($ok) { $res.Passed++ }
        else { $res.Failed++; Write-Host ('    FAILED: ' + $label) -ForegroundColor Red; Write-Log ('Self-test failed: ' + $label) 'ERROR' }
    }
    $saveInteractive = $script:Interactive
    $script:Interactive = $false
    $lockStream = $null
    try {
        Ensure-Dir $src
        $t0 = (Get-Date).AddHours(-3)
        $put = {
            param([string]$rel, [string]$text, [datetime]$when)
            $p = PathJoin $src $rel
            Ensure-Dir (Get-Parent $p)
            if ([System.IO.File]::Exists((ToLongPath $p))) { [System.IO.File]::SetAttributes((ToLongPath $p), [System.IO.FileAttributes]::Normal) }
            [System.IO.File]::WriteAllText((ToLongPath $p), $text)
            [System.IO.File]::SetLastWriteTimeUtc((ToLongPath $p), $when.ToUniversalTime())
        }
        $read = { param([string]$p) if ([System.IO.File]::Exists((ToLongPath $p))) { return [System.IO.File]::ReadAllText((ToLongPath $p)) }; return $null }
        $has = { param([string]$p) return [System.IO.File]::Exists((ToLongPath $p)) }
        $hasDir = { param([string]$p) return [System.IO.Directory]::Exists((ToLongPath $p)) }

        $uni = 'Caf' + [char]0x00E9 + ' ' + [char]0x2014 + ' notes ' + [char]0x2713 + '.txt'
        & $put 'Chapter 1.docx' 'Chapter one, first draft.' $t0
        & $put 'Notes\Ideas.txt' 'Some ideas' $t0
        & $put 'Old Folder\Outline.txt' 'old outline' $t0
        & $put $uni 'unicode name' $t0
        & $put 'Empty.txt' '' $t0
        & $put '~$apter 1.docx' 'word owner file' $t0
        & $put 'Hidden.txt' 'hidden' $t0
        [System.IO.File]::SetAttributes((PathJoin $src 'Hidden.txt'), [System.IO.FileAttributes]::Hidden)
        & $put 'ReadOnly.txt' 'read only' $t0
        [System.IO.File]::SetAttributes((PathJoin $src 'ReadOnly.txt'), [System.IO.FileAttributes]::ReadOnly)
        Ensure-Dir (PathJoin $src 'Empty Folder')
        $longRel = (@(1..6 | ForEach-Object { 'Long folder name number ' + $_ + ' for testing paths' }) -join '\') + '\Deep file.txt'
        $longMade = $true
        try { & $put $longRel 'deep' $t0 } catch { $longMade = $false }

        $r1 = Invoke-Sync -SourceRoot $src -CurrentRoot $cur -VersionsRoot $ver -RunTime (Get-Date).AddMinutes(-50)
        & $check (-not $r1.Aborted) 'first backup completes'
        & $check ((& $read (PathJoin $cur 'Chapter 1.docx')) -eq 'Chapter one, first draft.') 'file copied with identical content'
        & $check (& $has (PathJoin $cur 'Notes\Ideas.txt')) 'files in sub-folders copied'
        & $check (& $has (PathJoin $cur $uni)) 'unusual characters in file names'
        & $check ((& $has (PathJoin $cur 'Empty.txt')) -and ([System.IO.FileInfo]::new((PathJoin $cur 'Empty.txt')).Length -eq 0)) 'empty files copied'
        & $check (-not (& $has (PathJoin $cur '~$apter 1.docx'))) 'Word temporary files skipped'
        & $check (& $has (PathJoin $cur 'Hidden.txt')) 'hidden files copied'
        & $check (& $has (PathJoin $cur 'ReadOnly.txt')) 'read-only files copied'
        & $check (& $hasDir (PathJoin $cur 'Empty Folder')) 'empty folders kept'
        & $check (@(Get-ChildItem -LiteralPath $ver -Force).Count -eq 0) 'no previous versions after the first backup'
        & $check ([System.IO.File]::GetLastWriteTimeUtc((PathJoin $cur 'Chapter 1.docx')) -eq [System.IO.File]::GetLastWriteTimeUtc((PathJoin $src 'Chapter 1.docx'))) 'file dates preserved'
        $unexpected = @($r1.Errors | Where-Object { $_ -notlike '*Long folder name*' })
        & $check ($unexpected.Count -eq 0) ('no unexpected errors (' + ($unexpected -join '; ') + ')')
        if ($longMade) {
            if (& $has (PathJoin $cur $longRel)) { $res.Notes.Add('Very long file paths: supported.') }
            else { $res.Notes.Add('Very long file paths: not supported on this PC - such files are listed as problems, never silently skipped.') }
        }

        $r2 = Invoke-Sync -SourceRoot $src -CurrentRoot $cur -VersionsRoot $ver -RunTime (Get-Date).AddMinutes(-40)
        & $check ($r2.New -eq 0 -and $r2.Updated -eq 0 -and $r2.Removed -eq 0 -and -not $r2.VersionFolder) 'a run with no changes copies nothing'

        & $put 'Chapter 1.docx' 'Chapter one, second draft with more words.' $t0.AddHours(1)
        Remove-FileForce (PathJoin $src 'Notes\Ideas.txt')
        Remove-TreeForce (PathJoin $src 'Old Folder')
        & $put 'Chapter 2.docx' 'Chapter two.' $t0.AddHours(1)
        & $put 'Locked.txt' 'locked content' $t0.AddHours(1)
        $lockStream = [System.IO.FileStream]::new((PathJoin $src 'Locked.txt'), [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        & $put 'ReadOnly.txt' 'read only, edited' $t0.AddHours(1)
        [System.IO.File]::SetAttributes((PathJoin $src 'ReadOnly.txt'), [System.IO.FileAttributes]::ReadOnly)

        $r3 = Invoke-Sync -SourceRoot $src -CurrentRoot $cur -VersionsRoot $ver -RunTime (Get-Date).AddMinutes(-30)
        $v3 = $r3.VersionFolder
        & $check ((& $read (PathJoin $cur 'Chapter 1.docx')) -eq 'Chapter one, second draft with more words.') 'changed file updated in Current Documents'
        & $check ($v3 -and ((& $read (PathJoin $v3 'Chapter 1.docx')) -eq 'Chapter one, first draft.')) 'earlier draft kept in Previous Versions'
        & $check (-not (& $has (PathJoin $cur 'Notes\Ideas.txt'))) 'deleted file leaves Current Documents'
        & $check ($v3 -and (& $has (PathJoin $v3 'Notes\Ideas.txt'))) 'deleted file kept in Previous Versions'
        & $check ((-not (& $hasDir (PathJoin $cur 'Old Folder'))) -and $v3 -and (& $has (PathJoin $v3 'Old Folder\Outline.txt'))) 'deleted folder kept in Previous Versions'
        & $check (& $has (PathJoin $cur 'Chapter 2.docx')) 'new file copied'
        & $check ($r3.Locked.Contains('Locked.txt') -and -not (& $has (PathJoin $cur 'Locked.txt'))) 'a file in use is skipped without stopping the backup'
        & $check ((& $read (PathJoin $cur 'ReadOnly.txt')) -eq 'read only, edited') 'read-only file updated'

        $lockStream.Dispose(); $lockStream = $null
        $r4 = Invoke-Sync -SourceRoot $src -CurrentRoot $cur -VersionsRoot $ver -RunTime (Get-Date).AddMinutes(-20)
        & $check (& $has (PathJoin $cur 'Locked.txt')) 'a file that was in use is backed up once it is free'

        [System.IO.File]::WriteAllText((PathJoin $cur 'Chapter 1.docx.kgtmp'), 'half-copied junk')
        $c2 = PathJoin $cur 'Chapter 2.docx'
        [System.IO.File]::WriteAllText($c2, 'Chapter t*o.')
        [System.IO.File]::SetLastWriteTimeUtc($c2, [System.IO.File]::GetLastWriteTimeUtc((PathJoin $src 'Chapter 2.docx')))
        $r5 = Invoke-Sync -SourceRoot $src -CurrentRoot $cur -VersionsRoot $ver -RunTime (Get-Date).AddMinutes(-10) -DeepVerifyCount 50
        & $check ((-not (& $has (PathJoin $cur 'Chapter 1.docx.kgtmp'))) -and ((& $read (PathJoin $cur 'Chapter 1.docx')) -eq 'Chapter one, second draft with more words.')) 'leftovers from an interrupted copy are cleaned up'
        & $check (((& $read $c2) -eq 'Chapter two.') -and $r5.Repaired -ge 1) 'a damaged backup copy is detected and repaired'

        $away = $src + '-away'
        [System.IO.Directory]::Move($src, $away)
        Ensure-Dir $src
        $r6 = Invoke-Sync -SourceRoot $src -CurrentRoot $cur -VersionsRoot $ver -RunTime (Get-Date).AddMinutes(-5)
        & $check ($r6.Aborted -and (& $has (PathJoin $cur 'Chapter 1.docx'))) 'an empty or missing Documents folder never empties the backup'
        Remove-TreeForce $src
        [System.IO.Directory]::Move($away, $src)

        $d20 = (Get-Date).Date.AddDays(-20)
        $h9 = PathJoin $ver ($d20.AddHours(9).ToString('yyyy-MM-dd (ddd) HH.mm', $script:Inv))
        $h15 = PathJoin $ver ($d20.AddHours(15).ToString('yyyy-MM-dd (ddd) HH.mm', $script:Inv))
        Ensure-Dir $h9; Ensure-Dir (PathJoin $h15 'Sub')
        [System.IO.File]::WriteAllText((PathJoin $h9 'X.txt'), 'x at 9')
        [System.IO.File]::WriteAllText((PathJoin $h15 'X.txt'), 'x at 15')
        [System.IO.File]::WriteAllText((PathJoin $h15 'Sub\Y.txt'), 'y at 15')
        $w = (Get-Date).Date.AddDays(-200)
        $mon = $w.AddDays(-(([int]$w.DayOfWeek + 6) % 7))
        $dm = PathJoin $ver ($mon.ToString('yyyy-MM-dd (ddd)', $script:Inv))
        $dw = PathJoin $ver ($mon.AddDays(2).ToString('yyyy-MM-dd (ddd)', $script:Inv))
        Ensure-Dir $dm; Ensure-Dir $dw
        [System.IO.File]::WriteAllText((PathJoin $dm 'Z.txt'), 'z monday')
        [System.IO.File]::WriteAllText((PathJoin $dw 'Z.txt'), 'z wednesday')
        [System.IO.File]::WriteAllText((PathJoin $dw 'Q.txt'), 'q wednesday')
        Ensure-Dir (PathJoin $ver 'Keep Me')
        [System.IO.File]::WriteAllText((PathJoin $ver 'Keep Me\k.txt'), 'keep')
        Invoke-Retention $ver (Get-Date)
        $day = PathJoin $ver ($d20.ToString('yyyy-MM-dd (ddd)', $script:Inv))
        & $check (((& $read (PathJoin $day 'X.txt')) -eq 'x at 9') -and ((& $read (PathJoin $day 'Sub\Y.txt')) -eq 'y at 15') -and -not (& $hasDir $h9) -and -not (& $hasDir $h15)) 'hourly versions older than 2 weeks become one folder per day'
        $wk = PathJoin $ver ($mon.ToString('yyyy-MM-dd', $script:Inv) + ' (week)')
        & $check (((& $read (PathJoin $wk 'Z.txt')) -eq 'z monday') -and ((& $read (PathJoin $wk 'Q.txt')) -eq 'q wednesday') -and -not (& $hasDir $dm) -and -not (& $hasDir $dw)) 'daily versions older than 6 months become one folder per week'
        & $check ((& $hasDir $v3) -and (& $has (PathJoin $ver 'Keep Me\k.txt'))) 'recent versions and other folders are left alone'
    }
    catch {
        $res.Failed++
        Write-Host ('    FAILED: the self-test itself crashed: ' + (Get-ErrText $_) + ' ' + $_.InvocationInfo.PositionMessage) -ForegroundColor Red
        Write-Log ('Self-test crashed: ' + (Get-ErrText $_) + ' ' + $_.InvocationInfo.PositionMessage) 'ERROR'
    }
    finally {
        if ($lockStream) { $lockStream.Dispose() }
        $script:Interactive = $saveInteractive
        try { Remove-TreeForce $root } catch {}
    }
    $color = 'Green'
    if ($res.Failed -gt 0) { $color = 'Red' }
    Write-Host ('  Self-test: {0} passed, {1} failed' -f $res.Passed, $res.Failed) -ForegroundColor $color
    foreach ($n in $res.Notes) { Write-Host ('    ' + $n) }
    Write-Log ('Self-test: {0} passed, {1} failed. {2}' -f $res.Passed, $res.Failed, ($res.Notes -join ' '))
    return $res
}

# ----------------------------------------------------------------------------------------------
# Setup
# ----------------------------------------------------------------------------------------------

function Get-UsbDriveLetters {
    $letters = @()
    try {
        foreach ($disk in @(Get-CimInstance Win32_DiskDrive -ErrorAction Stop)) {
            if ($disk.InterfaceType -ne 'USB' -and [string]$disk.PNPDeviceID -notlike 'USBSTOR*' -and [string]$disk.MediaType -notlike 'External*') { continue }
            foreach ($part in @(Get-CimAssociatedInstance -InputObject $disk -ResultClassName Win32_DiskPartition -ErrorAction SilentlyContinue)) {
                foreach ($ld in @(Get-CimAssociatedInstance -InputObject $part -ResultClassName Win32_LogicalDisk -ErrorAction SilentlyContinue)) { $letters += ([string]$ld.DeviceID).ToUpper() }
            }
        }
    } catch {}
    return $letters
}

function Select-BackupDrive {
    if ($Drive) {
        $letter = $Drive.Trim().TrimEnd('\').TrimEnd(':') + ':\'
        $di = [System.IO.DriveInfo]::new($letter)
        if (-not $di.IsReady) { throw "Drive $letter isn't ready. Check that the backup drive is plugged in." }
        return $di
    }
    $existing = Find-BackupDrive $null
    if ($existing) {
        Write-Host ('  Found the backup drive used before: ' + $existing.Root)
        return $existing.Drive
    }
    $sys = ($env:SystemDrive + '\').ToUpper()
    $usb = Get-UsbDriveLetters
    $cands = @([System.IO.DriveInfo]::GetDrives() | Where-Object {
            try { ($_.DriveType -eq [System.IO.DriveType]::Fixed -or $_.DriveType -eq [System.IO.DriveType]::Removable) -and $_.IsReady -and $_.RootDirectory.FullName.ToUpper() -ne $sys } catch { $false }
        })
    if ($cands.Count -eq 0) { throw 'No backup drive found. Plug in the external drive and run setup again.' }
    Write-Host '  Drives found:'
    $n = 0
    foreach ($c in $cands) {
        $n++
        $tags = @()
        if ($usb -contains $c.Name.Substring(0, 2).ToUpper()) { $tags += 'USB / external' }
        if ([System.IO.Directory]::Exists((PathJoin $c.RootDirectory.FullName 'KnightLogics-Author-Backups'))) { $tags += 'has the earlier Author Vault backup' }
        $label = $c.VolumeLabel
        if (-not $label) { $label = '(no name)' }
        Write-Host ('    {0}) {1}  {2}  {3}  {4} free of {5}  {6}' -f $n, $c.Name, $label, $c.DriveFormat, (Format-Size $c.AvailableFreeSpace), (Format-Size $c.TotalSize), ($tags -join ', '))
    }
    $pick = $null
    $preferred = @($cands | Where-Object { [System.IO.Directory]::Exists((PathJoin $_.RootDirectory.FullName 'KnightLogics-Author-Backups')) })
    $usbC = @($cands | Where-Object { $usb -contains $_.Name.Substring(0, 2).ToUpper() })
    if ($preferred.Count -eq 1) { $pick = $preferred[0] }
    elseif ($usbC.Count -eq 1) { $pick = $usbC[0] }
    elseif ($cands.Count -eq 1) { $pick = $cands[0] }
    if ($NoPrompt) {
        if (-not $pick) { throw 'More than one drive was found. Run setup again with -Drive and the drive letter, for example -Drive E' }
        return $pick
    }
    while ($true) {
        if ($pick) {
            $ans = Read-Host ('  Use ' + $pick.Name + ' as the backup drive? Press Enter for yes, or type a different drive letter')
            if (-not $ans -or $ans.Trim() -match '^(y|yes)$') { return $pick }
        } else {
            $ans = Read-Host '  Type the letter of the backup drive (for example E)'
        }
        $want = $ans.Trim().TrimEnd('\').TrimEnd(':').ToUpper()
        $match = @($cands | Where-Object { $_.Name.Substring(0, 1).ToUpper() -eq $want })
        if ($match.Count -eq 1) { return $match[0] }
        Write-Host '  That is not one of the drives listed above.' -ForegroundColor Yellow
        $pick = $null
    }
}

function Invoke-PostInstallCheck([string]$Docs, [string]$CurrentRoot) {
    $s = Get-Tree $Docs
    $c = Get-Tree $CurrentRoot
    $missing = @($s.Files.Keys | Where-Object { -not $c.Files.ContainsKey($_) })
    $result = @{ Total = $s.Files.Count; InBackup = $s.Files.Count - $missing.Count; Missing = $missing; Restored = 0; Tried = 0 }
    $pool = @($c.Files.Keys | Where-Object { $s.Files.ContainsKey($_) -and $s.Files[$_].Length -le 50MB })
    if ($pool.Count -gt 0) {
        $sample = @($pool | Get-Random -Count ([Math]::Min(5, $pool.Count)))
        $tmpDir = PathJoin ([System.IO.Path]::GetTempPath().TrimEnd('\')) ('KL-Restore-Test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        Ensure-Dir $tmpDir
        try {
            $k = 0
            foreach ($rel in $sample) {
                $k++
                $result.Tried++
                try {
                    $restored = PathJoin $tmpDir ('restored-' + $k + '.bin')
                    [System.IO.File]::Copy((ToLongPath (PathJoin $CurrentRoot $rel)), (ToLongPath $restored), $true)
                    if ((Get-Sha256 $restored) -eq (Get-Sha256 (PathJoin $Docs $rel))) { $result.Restored++ }
                    else { Write-Log ("Restore test: '" + $rel + "' differs from the original (it may have just been edited).") 'WARN' }
                } catch { Write-Log ("Restore test could not check '" + $rel + "': " + (Get-ErrText $_)) 'WARN' }
            }
        } finally { try { Remove-TreeForce $tmpDir } catch {} }
    }
    return $result
}

function Test-ScheduledLaunch {
    $before = Get-Val (Read-State) 'LastLaunch'
    try { Start-ScheduledTask -TaskName $script:TaskName -ErrorAction Stop | Out-Null } catch { return ("could not start it: " + (Get-ErrText $_)) }
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 2
        $nowVal = Get-Val (Read-JsonFile (PathJoin $script:AppDir 'state.json')) 'LastLaunch'
        if ($nowVal -and $nowVal -ne $before) { return 'OK' }
    }
    return 'it did not report back within 60 seconds'
}

function Invoke-Install {
    $script:Interactive = $true
    Write-Host ''
    Write-Host '  Knight Logics - Documents Backup setup' -ForegroundColor Cyan
    Write-Host '  ---------------------------------------'
    Ensure-Dir $script:AppDir
    Ensure-Dir $script:LogDir
    $dest = PathJoin $script:AppDir 'DocumentsBackup.ps1'
    if ($PSCommandPath -and ($PSCommandPath -ne $dest)) { Copy-Item -LiteralPath $PSCommandPath -Destination $dest -Force }
    Write-Launcher
    Write-Log ('Setup started (version ' + $script:Version + ') for ' + $env:COMPUTERNAME + '\' + $env:USERNAME)

    $docs = [Environment]::GetFolderPath('MyDocuments')
    if (-not $docs -or -not [System.IO.Directory]::Exists($docs)) { throw "The Documents folder couldn't be found." }
    $tree = Get-Tree $docs
    $bytes = [long]0
    foreach ($f in $tree.Files.Values) { $bytes += $f.Length }
    Write-Host ('  Documents folder:  ' + $docs)
    Write-Host ('  It contains {0:N0} files ({1}).' -f $tree.Files.Count, (Format-Size $bytes))
    Write-Host ''

    Write-Host '  Step 1 of 5: safety self-test on sample files'
    $t = Invoke-SelfTest
    if ($t.Failed -gt 0) {
        Write-Host ''
        Write-Host '  Setup stopped: the self-test found a problem, so nothing was turned on.' -ForegroundColor Red
        Write-Host '  No personal files or backups were touched. Send Nick a photo of this window.' -ForegroundColor Red
        return
    }
    Write-Host ''

    Write-Host '  Step 2 of 5: choose the backup drive'
    $di = Select-BackupDrive
    $driveRoot = $di.RootDirectory.FullName
    $markerPath = PathJoin $driveRoot $script:MarkerName
    $folderName = $env:USERNAME + "'s Documents Backup"
    if ([System.IO.File]::Exists($markerPath)) {
        $marker = [System.IO.File]::ReadAllText($markerPath) | ConvertFrom-Json
        $driveId = $marker.Id
        if ($marker.BackupFolderName) { $folderName = $marker.BackupFolderName }
    } else {
        $driveId = [guid]::NewGuid().ToString()
        $marker = [pscustomobject]@{
            Id = $driveId; BackupFolderName = $folderName; CreatedFor = ($env:COMPUTERNAME + '\' + $env:USERNAME); Created = (NowText)
            Note = 'This small file lets the Knight Logics backup recognise this drive even if its letter changes. Please leave it here.'
        }
        [System.IO.File]::WriteAllText($markerPath, ($marker | ConvertTo-Json))
        try { [System.IO.File]::SetAttributes($markerPath, [System.IO.FileAttributes]::Hidden) } catch {}
    }
    $root = PathJoin $driveRoot $folderName
    Ensure-Dir (PathJoin $root $script:CurrentName)
    Ensure-Dir (PathJoin $root $script:VersionsName)
    Write-RestoreGuide $root
    $cfg = [pscustomobject]@{
        Version = $script:Version; DriveId = $driveId; BackupFolderName = $folderName; Documents = $docs
        InstalledAt = (NowText); User = ($env:COMPUTERNAME + '\' + $env:USERNAME)
    }
    Save-Config $cfg
    Write-Host ('  Backup folder:     ' + $root)
    Write-Host ''

    Write-Host '  Step 3 of 5: turn on the hourly schedule'
    Register-BackupTask
    Set-RunKey
    Write-Host ('  Scheduled task "' + $script:TaskName + '" created (every hour + at sign-in, runs invisibly).')
    Write-Host ''

    Write-Host '  Step 4 of 5: first backup (this can take a while the first time)'
    $r = Invoke-Backup -Manual
    if (-not $r -or $r.Aborted) {
        Write-Host '  The first backup did not finish - see the message above. The schedule will keep trying every hour.' -ForegroundColor Yellow
    }
    Write-Host ''

    Write-Host '  Step 5 of 5: checking the backup and the automatic run'
    $chk = Invoke-PostInstallCheck $docs (PathJoin $root $script:CurrentName)
    $launch = Test-ScheduledLaunch

    Write-Host ''
    Write-Host '  ==================================================================' -ForegroundColor Green
    Write-Host ('   Done. ' + $env:USERNAME + "'s Documents are now backed up automatically.") -ForegroundColor Green
    Write-Host '  ==================================================================' -ForegroundColor Green
    Write-Host ('   Backup folder:    ' + $root)
    Write-Host ('   In the backup:    {0:N0} of {1:N0} files' -f $chk.InBackup, $chk.Total)
    if ($chk.Missing.Count -gt 0) {
        Write-Host ('   Not yet copied:   ' + (@($chk.Missing | Select-Object -First 5) -join ', ') + ' (open in another program or unreadable - retried every hour)') -ForegroundColor Yellow
    }
    Write-Host ('   Restore test:     {0} of {1} sample files restored and matched the originals' -f $chk.Restored, $chk.Tried)
    Write-Host ('   Automatic run:    ' + $launch)
    Write-Host '   Schedule:         about every hour while signed in, and at sign-in; only changes are copied'
    Write-Host '   Versions kept:    hourly for 2 weeks, then daily for 6 months, then weekly'
    Write-Host '   Self-repair:      restores its schedule if removed, retries files in use, finds the drive'
    Write-Host '                     if its letter changes, and reminds you if the drive is unplugged 3+ days'
    Write-Host ''
    Write-Log ('Setup finished. Backup folder: ' + $root + '. Automatic run test: ' + $launch)
}

function Show-Status {
    $script:Interactive = $true
    $s = Read-State
    $c = Read-Config
    Write-Host ''
    Write-Host '  Knight Logics - Documents Backup status' -ForegroundColor Cyan
    Write-Host ('  Version:          ' + $script:Version)
    Write-Host ('  Documents:        ' + (Get-Val $c 'Documents'))
    $d = $null
    if ($c) { $d = Find-BackupDrive $c.DriveId }
    if ($d) { Write-Host ('  Backup drive:     connected at ' + $d.Root) } else { Write-Host '  Backup drive:     NOT connected' -ForegroundColor Yellow }
    Write-Host ('  Backup folder:    ' + (Get-Val $s 'BackupFolder'))
    Write-Host ('  Last completed:   ' + (Get-Val $s 'LastCompleted'))
    Write-Host ('  Last result:      ' + (Get-Val $s 'LastResult'))
    Write-Host ('  In use / retry:   ' + (Get-Val $s 'LastLocked'))
    Write-Host ('  Problems:         ' + (Get-Val $s 'LastErrors'))
    Write-Host ('  Last error:       ' + (Get-Val $s 'LastError'))
    try {
        $t = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction Stop
        $ti = Get-ScheduledTaskInfo -TaskName $script:TaskName -ErrorAction Stop
        Write-Host ('  Scheduled task:   ' + $t.State + '; last run ' + $ti.LastRunTime + ' (result ' + $ti.LastTaskResult + '); next run ' + $ti.NextRunTime)
    } catch { Write-Host '  Scheduled task:   MISSING (it will be restored at the next sign-in)' -ForegroundColor Yellow }
    Write-Host ('  Log folder:       ' + $script:LogDir)
    Write-Host ''
}

function Invoke-Uninstall {
    try { Unregister-ScheduledTask -TaskName $script:TaskName -Confirm:$false -ErrorAction Stop } catch {}
    try { Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name $script:RunKeyName -ErrorAction Stop } catch {}
    Write-Log 'Automatic backups were turned off (Uninstall). Backup copies on the drive were left untouched.' 'WARN'
    Write-Host '  Automatic backups are turned off. The backup copies on the drive were left untouched.'
}

# ----------------------------------------------------------------------------------------------
# Start
# ----------------------------------------------------------------------------------------------

try {
    switch ($Mode) {
        'Install'   { Invoke-Install }
        'SelfTest'  { $script:Interactive = $true; $res = Invoke-SelfTest; if ($res.Failed -gt 0) { exit 1 } }
        'Backup'    { $script:Interactive = $true; [void](Invoke-Backup -Manual) }
        'Auto'      { [void](Invoke-Backup); Repair-Schedule }
        'Repair'    { Repair-Schedule; [void](Invoke-Backup) }
        'Status'    { Show-Status }
        'Uninstall' { $script:Interactive = $true; Invoke-Uninstall }
    }
}
catch {
    Write-Log ('Unexpected problem in ' + $Mode + ': ' + (Get-ErrText $_) + ' ' + $_.InvocationInfo.PositionMessage) 'ERROR'
    if ($Mode -eq 'Install') { Write-Host ''; Write-Host '  Setup could not finish. Send Nick a photo of this window.' -ForegroundColor Red }
    exit 1
}
