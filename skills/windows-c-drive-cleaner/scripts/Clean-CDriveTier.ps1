# Clean-CDriveTier.ps1 - Tier-gated executor for scan results of Scan-CDrive.ps1.
# ASCII-only on purpose: cmd/PowerShell on zh-CN systems misread non-ASCII .ps1 files.
#
# Modes:
#   DryRun   (default) - resolve selection and guards, delete nothing
#   Recycle            - send items to the Recycle Bin (preferred)
#   Staging            - move items into -StagingDir with a manifest (reversible)
#   Delete             - permanent delete (rm does NOT go to the recycle bin)
#
# Hard rules baked in (cannot be overridden by flags):
#   - any directory named LocalHistory is never touched
#   - targets must live under an allow-listed root; the root itself is refused
#   - T3 targets require -AllowT3
#   - directories matching a pattern target are removed per-match, not wholesale
#   - the running script itself (ps-script-*.ps1 under %TEMP%) is never removed
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File Clean-CDriveTier.ps1 -PlanFile scan-plan.json -Tier T1            # DryRun
#   powershell ... -File Clean-CDriveTier.ps1 -PlanFile scan-plan.json -Tier T1,T2 -Mode Recycle
#   powershell ... -File Clean-CDriveTier.ps1 -Ids npm-cache,user-temp -Mode Staging
#   powershell ... -File Clean-CDriveTier.ps1 -Paths "D:\some\dir" -Mode Delete -AllowOutside

param(
    [string]$PlanFile = "",
    [string[]]$Tier = @(),
    [string[]]$Ids = @(),
    [string[]]$Paths = @(),
    [ValidateSet('DryRun', 'Recycle', 'Staging', 'Delete')][string]$Mode = 'DryRun',
    [string]$StagingDir = "",
    [string]$ReportFile = "",
    [switch]$AllowT3,
    [switch]$AllowOutside,
    [int]$MaxSecondsPerCheck = 60
)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
Add-Type -AssemblyName Microsoft.VisualBasic

$ExcludeDirNames = @('localhistory')   # compared case-insensitively; NEVER removable here

# Self-protection: never delete the script currently running (PowerShell stages
# inline scripts under %TEMP%\ps-script-<guid>.ps1). Traps #20.
$SelfPath = $null
try { $SelfPath = $MyInvocation.MyCommand.Path } catch {}
$SelfName = $null
if ($SelfPath) { $SelfName = [System.IO.Path]::GetFileName($SelfPath) }

# ---------------------------------------------------------------- helpers

function Format-Bytes {
    param([Nullable[double]]$Bytes)
    if ($null -eq $Bytes) { return "n/a" }
    if ($Bytes -ge 1TB) { return ("{0:N2} TB" -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ("{0:N2} GB" -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ("{0:N2} MB" -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ("{0:N2} KB" -f ($Bytes / 1KB)) }
    return ("{0:N0} B" -f $Bytes)
}

function Escape-Md { param([string]$Text) if ($null -eq $Text) { return "" }; return ($Text -replace "\|", "\|") }

function Get-FreeBytes {
    param([string]$DriveRoot)
    try {
        $d = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $DriveRoot.TrimEnd('\'))
        if ($null -ne $d) { return [double]$d.FreeSpace }
    } catch {}
    return 0.0
}

function Test-UnderRoot {
    param([string]$Path, [string]$Root)
    $p = $Path.TrimEnd('\').ToLowerInvariant()
    $r = $Root.TrimEnd('\').ToLowerInvariant()
    if ($p -eq $r) { return $false }                       # the root itself is never a target
    return $p.StartsWith($r + '\')
}

function Test-TreeHasExcluded {
    param([string]$Dir)
    # DFS for guard directories. 'timeout' is treated as dirty by callers.
    $deadline = [datetime]::Now.AddSeconds($MaxSecondsPerCheck)
    $stack = New-Object System.Collections.Generic.Stack[object]
    $stack.Push(@{ P = $Dir; D = 0 })
    while ($stack.Count -gt 0) {
        if ([datetime]::Now -gt $deadline) { return 'timeout' }
        $item = $stack.Pop()
        if ($item.D -ge 40) { continue }
        $children = $null
        try { $children = [System.IO.Directory]::EnumerateDirectories($item.P) } catch { continue }
        foreach ($c in $children) {
            try {
                $name = [System.IO.Path]::GetFileName($c)
                if ($ExcludeDirNames -contains $name.ToLowerInvariant()) { return $true }
                $attr = [System.IO.File]::GetAttributes($c)
                if (($attr -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                $stack.Push(@{ P = $c; D = $item.D + 1 })
            } catch { continue }
        }
    }
    return $false
}

function Test-IsSelf {
    # Protect the running script and any PowerShell temp script.
    param([string]$Path)
    $n = [System.IO.Path]::GetFileName($Path)
    if ($n -like 'ps-script-*' -and $n -like '*.ps1') { return $true }
    if ($SelfName -and $n -eq $SelfName) { return $true }
    return $false
}

function Remove-OneItem {
    param([string]$ItemPath, [string]$RunMode)
    if (Test-IsSelf -Path $ItemPath) { return 'skipped: self-protected' }
    if ($RunMode -eq 'Recycle') {
        try {
            $attr = [System.IO.File]::GetAttributes($ItemPath)
            if (($attr -band [System.IO.FileAttributes]::Directory) -ne 0) {
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($ItemPath, 'OnlyErrorDialogs', 'SendToRecycleBin')
            } else {
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($ItemPath, 'OnlyErrorDialogs', 'SendToRecycleBin')
            }
            return 'recycled'
        } catch { return "failed: $($_.Exception.Message)" }
    }
    if ($RunMode -eq 'Delete') {
        try { [System.IO.Directory]::Delete($ItemPath, $true); return 'deleted' }
        catch {
            try { [System.IO.File]::Delete($ItemPath); return 'deleted' }
            catch { return "failed: $($_.Exception.Message)" }
        }
    }
    return 'noop'
}

function Move-ToStaging {
    param([string]$ItemPath, [string]$StageRoot, [string]$Tag)
    if (Test-IsSelf -Path $ItemPath) { return 'skipped: self-protected' }
    try {
        $dest = Join-Path $StageRoot $Tag
        if (Test-Path -LiteralPath $dest) { $dest = Join-Path $StageRoot ($Tag + "-" + [guid]::NewGuid().ToString('N').Substring(0, 6)) }
        $parent = Split-Path -Parent $dest
        if (-not (Test-Path -LiteralPath $parent)) { [System.IO.Directory]::CreateDirectory($parent) | Out-Null }
        Move-Item -LiteralPath $ItemPath -Destination $dest -Force
        return "staged: $dest"
    } catch { return "failed: $($_.Exception.Message)" }
}

# Walk-based cleaning: guard dirs are skipped in place, clean subtrees are
# removed in one shot (fast), dirty subtrees are recursed, locked items are
# logged and skipped so one in-use file never kills the whole target.
function Remove-Tree {
    param([string]$Dir, [string]$RunMode, [string]$StageRoot, [string]$Tag, $Log)
    $dirsRemoved = 0; $filesRemoved = 0; $skipped = 0; $failed = 0
    $work = New-Object System.Collections.Generic.Stack[object]
    $work.Push(@{ P = $Dir; D = 0; T = $Tag })
    while ($work.Count -gt 0) {
        $item = $work.Pop()
        $children = $null
        try { $children = [System.IO.Directory]::GetFileSystemEntries($item.P) } catch { $failed++; continue }
        foreach ($c in $children) {
            $name = [System.IO.Path]::GetFileName($c)
            $isDir = $false
            try { $isDir = ([System.IO.File]::GetAttributes($c) -band [System.IO.FileAttributes]::Directory) -ne 0 } catch { $failed++; continue }
            if (-not $isDir) {
                if (Test-IsSelf -Path $c) { $skipped++; [void]$Log.Add([pscustomobject]@{ kind = 'self'; path = $c; result = 'skipped (running script)' }); continue }
                if ($RunMode -eq 'DryRun') { $filesRemoved++; continue }
                if ($RunMode -eq 'Staging') {
                    $r = Move-ToStaging -ItemPath $c -StageRoot $StageRoot -Tag ($item.T + "\" + $name)
                    if ($r.StartsWith('staged')) { $filesRemoved++ } else { $failed++ }
                    [void]$Log.Add([pscustomobject]@{ kind = 'file'; path = $c; result = $r })
                } else {
                    $r = Remove-OneItem -ItemPath $c -RunMode $RunMode
                    if ($r -eq 'recycled' -or $r -eq 'deleted') { $filesRemoved++ } else { $failed++ }
                    if ($r.StartsWith('failed')) { [void]$Log.Add([pscustomobject]@{ kind = 'file'; path = $c; result = $r }) }
                }
                continue
            }
            if ($ExcludeDirNames -contains $name.ToLowerInvariant()) { $skipped++; [void]$Log.Add([pscustomobject]@{ kind = 'guard'; path = $c; result = 'protected (excluded name)' }); continue }
            try { if (([System.IO.File]::GetAttributes($c) -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { $skipped++; [void]$Log.Add([pscustomobject]@{ kind = 'junction'; path = $c; result = 'skipped reparse point' }); continue } } catch { $failed++; continue }
            if ($item.D -ge 40) { $skipped++; continue }
            $hasGuard = Test-TreeHasExcluded -Dir $c
            if ($hasGuard -eq 'timeout') { $work.Push(@{ P = $c; D = $item.D + 1; T = ($item.T + "\" + $name) }); continue }
            if ($hasGuard) { $work.Push(@{ P = $c; D = $item.D + 1; T = ($item.T + "\" + $name) }); continue }
            # clean subtree: handle it in one shot
            if ($RunMode -eq 'DryRun') { $dirsRemoved++ ; continue }
            if ($RunMode -eq 'Staging') {
                $r = Move-ToStaging -ItemPath $c -StageRoot $StageRoot -Tag ($item.T + "\" + $name)
                if ($r.StartsWith('staged')) { $dirsRemoved++ } else { $failed++ }
                [void]$Log.Add([pscustomobject]@{ kind = 'dir'; path = $c; result = $r })
            } else {
                $r = Remove-OneItem -ItemPath $c -RunMode $RunMode
                if ($r -eq 'recycled' -or $r -eq 'deleted') { $dirsRemoved++ } else { $failed++ }
                if ($r.StartsWith('failed')) { [void]$Log.Add([pscustomobject]@{ kind = 'dir'; path = $c; result = $r }) }
            }
        }
    }
    return [pscustomobject]@{ Dirs = $dirsRemoved; Files = $filesRemoved; Skipped = $skipped; Failed = $failed }
}

# Pattern-based cleanup: only the MATCHING children under the root are removed.
# The root itself is never deleted. Used for updater dirs, GUID residue, etc.
function Remove-PatternMatches {
    param([string]$Root, [string]$Pattern, [string]$RunMode, [string]$StageRoot, [string]$Tag, $Log)
    $hits = @()
    try {
        $hits = @(Get-ChildItem -LiteralPath $Root -Force -Directory -ErrorAction SilentlyContinue |
                  Where-Object { $_.Name -match $Pattern })
    } catch { $hits = @() }
    $dirsRemoved = 0; $filesRemoved = 0; $skipped = 0; $failed = 0
    foreach ($h in $hits) {
        if (Test-IsSelf -Path $h.FullName) { $skipped++; continue }
        $name = $h.Name.ToLowerInvariant()
        if ($ExcludeDirNames -contains $name) { $skipped++; [void]$Log.Add([pscustomobject]@{ kind = 'guard'; path = $h.FullName; result = 'protected (excluded name)' }); continue }
        $hasGuard = Test-TreeHasExcluded -Dir $h.FullName
        if ($hasGuard -eq 'true') { $skipped++; [void]$Log.Add([pscustomobject]@{ kind = 'guard'; path = $h.FullName; result = 'contains protected dirs; skipped' }); continue }
        if ($RunMode -eq 'DryRun') { $dirsRemoved++; [void]$Log.Add([pscustomobject]@{ kind = 'match'; path = $h.FullName; result = 'would remove (pattern match)' }); continue }
        if ($RunMode -eq 'Staging') {
            $r = Move-ToStaging -ItemPath $h.FullName -StageRoot $StageRoot -Tag ($Tag + "\" + $h.Name)
            if ($r.StartsWith('staged')) { $dirsRemoved++ } else { $failed++ }
            [void]$Log.Add([pscustomobject]@{ kind = 'match'; path = $h.FullName; result = $r })
        } else {
            $r = Remove-OneItem -ItemPath $h.FullName -RunMode $RunMode
            if ($r -eq 'recycled' -or $r -eq 'deleted') { $dirsRemoved++ } else { $failed++ }
            [void]$Log.Add([pscustomobject]@{ kind = 'match'; path = $h.FullName; result = $r })
        }
    }
    return [pscustomobject]@{ Dirs = $dirsRemoved; Files = $filesRemoved; Skipped = $skipped; Failed = $failed; Matches = $hits.Count }
}

# ---------------------------------------------------------------- selection

if ([string]::IsNullOrWhiteSpace($StagingDir)) { $StagingDir = Join-Path $env:USERPROFILE "cdisk-staging" }

$planTargets = @()
$patternMap = @{}
if (-not [string]::IsNullOrWhiteSpace($PlanFile)) {
    $plan = Get-Content -LiteralPath $PlanFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $planTargets = @($plan.targets)
    foreach ($t in $planTargets) {
        if ($t.PSObject.Properties['IsPattern'] -and $t.IsPattern -and $t.PSObject.Properties['Pattern']) {
            $patternMap[$t.Id] = $t.Pattern
        }
    }
}

$selection = New-Object System.Collections.Generic.List[object]
foreach ($t in $planTargets) {
    $wantTier = ($Tier.Count -gt 0 -and ($Tier | ForEach-Object { $_.ToUpperInvariant() }) -contains $t.Tier)
    $wantId = ($Ids.Count -gt 0 -and ($Ids | ForEach-Object { $_.ToLowerInvariant() }) -contains $t.Id.ToLowerInvariant())
    if ($wantTier -or $wantId) {
        $isPattern = ($t.PSObject.Properties['IsPattern'] -and $t.IsPattern)
        $pat = $null
        if ($isPattern -and $t.PSObject.Properties['Pattern']) { $pat = $t.Pattern }
        $selection.Add([pscustomobject]@{ Id = $t.Id; Path = $t.Path; Tier = $t.Tier; Guard = $t.Guard; Source = 'plan'; IsPattern = $isPattern; Pattern = $pat })
    }
}
$i = 0
foreach ($p in $Paths) {
    $i++
    $selection.Add([pscustomobject]@{ Id = "manual-$i"; Path = $p; Tier = 'MANUAL'; Guard = 'explicit -Paths selection'; Source = 'paths'; IsPattern = $false; Pattern = $null })
}
if ($selection.Count -eq 0) { Write-Host "Nothing selected. Use -Tier / -Ids (with -PlanFile) or -Paths."; exit 1 }

# ---------------------------------------------------------------- safety gate

$allowRoots = @($env:LOCALAPPDATA, $env:APPDATA, $env:USERPROFILE, $env:ProgramData,
                ($env:windir + '\Temp'),
                ($env:windir + '\SoftwareDistribution\Download')) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

$approved = New-Object System.Collections.Generic.List[object]
$rejected = New-Object System.Collections.Generic.List[object]
foreach ($s in $selection) {
    $resolved = try { ([System.IO.Path]::GetFullPath($s.Path)).TrimEnd('\') } catch { $null }
    if ([string]::IsNullOrWhiteSpace($resolved) -or -not (Test-Path -LiteralPath $resolved)) {
        [void]$rejected.Add([pscustomobject]@{ Sel = $s; Reason = "path missing or invalid" }); continue
    }
    $ok = $false
    foreach ($root in $allowRoots) { if (Test-UnderRoot -Path $resolved -Root $root) { $ok = $true; break } }
    if (-not $ok -and $AllowOutside) { $ok = $true }
    if (-not $ok) { [void]$rejected.Add([pscustomobject]@{ Sel = $s; Reason = "outside allow-listed roots (use -AllowOutside to override)"; Path = $resolved }); continue }
    if ($s.Tier -eq 'T3' -and -not $AllowT3) { [void]$rejected.Add([pscustomobject]@{ Sel = $s; Reason = "T3 requires -AllowT3"; Path = $resolved }); continue }
    # Pattern targets hold the ROOT; the guard check applies to each match, not the root.
    if ($s.IsPattern) {
        [void]$approved.Add([pscustomobject]@{ Sel = $s; Path = $resolved; GuardTimeout = $false })
        continue
    }
    $guardHit = Test-TreeHasExcluded -Dir $resolved
    if ($guardHit -eq 'true') { [void]$rejected.Add([pscustomobject]@{ Sel = $s; Reason = "contains protected dirs (LocalHistory). Clean sub-items manually instead."; Path = $resolved }); continue }
    [void]$approved.Add([pscustomobject]@{ Sel = $s; Path = $resolved; GuardTimeout = ($guardHit -eq 'timeout') })
}

# ---------------------------------------------------------------- execute

$driveRoot = "C:\"
if ($approved.Count -gt 0) {
    $probe = $approved[0].Path
    $driveRoot = (Split-Path -Qualifier $probe) + "\"
}
$freeBefore = Get-FreeBytes -DriveRoot $driveRoot
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
if ([string]::IsNullOrWhiteSpace($ReportFile)) { $ReportFile = Join-Path (Get-Location) ("clean-report-" + $stamp + ".md") }
if ($Mode -eq 'Staging' -and -not (Test-Path -LiteralPath $StagingDir)) { [System.IO.Directory]::CreateDirectory($StagingDir) | Out-Null }

$log = New-Object System.Collections.Generic.List[object]
$results = New-Object System.Collections.Generic.List[object]

foreach ($a in $approved) {
    $s = $a.Sel
    Write-Host ("[{0}] {1} -> {2}" -f $s.Id, $Mode, $a.Path)
    $outcome = ""
    if ($s.IsPattern) {
        $r = Remove-PatternMatches -Root $a.Path -Pattern $s.Pattern -RunMode $Mode -StageRoot $StagingDir -Tag $s.Id -Log $log
        $outcome = ("{0}: {1} pattern-matched dirs handled" -f $Mode, $r.Matches)
        [void]$results.Add([pscustomobject]@{ Id = $s.Id; Path = $a.Path; Tier = $s.Tier; Mode = $Mode; Dirs = $r.Dirs; Files = $r.Files; Skipped = $r.Skipped; Failed = $r.Failed; Outcome = $outcome })
        continue
    }
    if ($Mode -eq 'DryRun') {
        $r = Remove-Tree -Dir $a.Path -RunMode 'DryRun' -StageRoot $StagingDir -Tag $s.Id -Log $log
        $outcome = "dry-run: {0} dirs / {1} files would go" -f $r.Dirs, $r.Files
        [void]$results.Add([pscustomobject]@{ Id = $s.Id; Path = $a.Path; Tier = $s.Tier; Mode = $Mode; Dirs = $r.Dirs; Files = $r.Files; Skipped = $r.Skipped; Failed = $r.Failed; Outcome = $outcome })
        continue
    }
    $r = Remove-Tree -Dir $a.Path -RunMode $Mode -StageRoot $StagingDir -Tag $s.Id -Log $log
    $outcome = ("{0}: dirs={1} files={2} skipped={3} failed={4}" -f $Mode, $r.Dirs, $r.Files, $r.Skipped, $r.Failed)
    if ($a.GuardTimeout) { $outcome += " (guard pre-check timed out; walked per-child)" }
    [void]$results.Add([pscustomobject]@{ Id = $s.Id; Path = $a.Path; Tier = $s.Tier; Mode = $Mode; Dirs = $r.Dirs; Files = $r.Files; Skipped = $r.Skipped; Failed = $r.Failed; Outcome = $outcome })
}

$freeAfter = Get-FreeBytes -DriveRoot $driveRoot
$delta = $freeAfter - $freeBefore

# ---------------------------------------------------------------- report

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("# Cleanup execution report ($stamp)")
[void]$sb.AppendLine()
[void]$sb.AppendLine("Mode: **$Mode** | Free before: $(Format-Bytes $freeBefore) | Free after: $(Format-Bytes $freeAfter) | **Freed: $(Format-Bytes ([Math]::Max(0, $delta)))**")
if ($Mode -eq 'Staging') { [void]$sb.AppendLine("Staging dir (restore source): $StagingDir") }
[void]$sb.AppendLine()
[void]$sb.AppendLine("## Targets")
[void]$sb.AppendLine()
[void]$sb.AppendLine("| Id | Tier | Path | Dirs | Files | Skipped | Failed | Outcome |")
[void]$sb.AppendLine("|---|---|---|---|---|---|---|---|")
foreach ($r in $results) {
    [void]$sb.AppendLine("| $($r.Id) | $($r.Tier) | $(Escape-Md $r.Path) | $($r.Dirs) | $($r.Files) | $($r.Skipped) | $($r.Failed) | $(Escape-Md $r.Outcome) |")
}
[void]$sb.AppendLine()
[void]$sb.AppendLine("## Rejected before touching anything")
[void]$sb.AppendLine()
if ($rejected.Count -eq 0) { [void]$sb.AppendLine("none.") } else {
    foreach ($x in $rejected) { [void]$sb.AppendLine("- **$($x.Sel.Id)** $(Escape-Md $x.Sel.Path) - $($x.Reason)") }
}
[void]$sb.AppendLine()
[void]$sb.AppendLine("## Item log (skipped / failed / staged / matched)")
[void]$sb.AppendLine()
if ($log.Count -eq 0) { [void]$sb.AppendLine("none.") } else {
    [void]$sb.AppendLine("| Kind | Path | Result |")
    [void]$sb.AppendLine("|---|---|---|")
    foreach ($l in ($log | Select-Object -First 200)) { [void]$sb.AppendLine("| $($l.kind) | $(Escape-Md $l.path) | $(Escape-Md $l.result) |") }
    if ($log.Count -gt 200) { [void]$sb.AppendLine(); [void]$sb.AppendLine("... and $($log.Count - 200) more.") }
}
[void]$sb.AppendLine()
[void]$sb.AppendLine("> Free-space delta is measured, not assumed. In-use files fail individually and are listed.")
[System.IO.File]::WriteAllText($ReportFile, $sb.ToString(), [System.Text.Encoding]::UTF8)
Write-Host "Report: $ReportFile"
Write-Host ("Freed (measured): " + (Format-Bytes ([Math]::Max(0, $delta))))
exit 0
