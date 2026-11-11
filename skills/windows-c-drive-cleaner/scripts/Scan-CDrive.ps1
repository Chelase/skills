# Scan-CDrive.ps1 - Read-only tiered scan of a Windows drive (dev-cache focus).
# ASCII-only on purpose: cmd/PowerShell on zh-CN systems misread non-ASCII .ps1 files.
#
# Output:
#   - Markdown report (human-readable tables, T0..T3 tiers)
#   - Optional JSON plan (-Json) consumed by Clean-CDriveTier.ps1
#
# Parallelism: PowerShell 5.1 has no ForEach-Object -Parallel, so this uses a
# runspace pool. Git Bash `du` times out on AppData; do not substitute it.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File Scan-CDrive.ps1 -Drive C:\ -OutFile scan-report.md -Json scan-plan.json
#   powershell ... -File Scan-CDrive.ps1 -Quick          # skip slow top-level rollup

param(
    [string]$Drive = "C:\",
    [string]$OutFile = "",
    [string]$Json = "",
    [int]$MaxSecondsPerTarget = 120,
    [int]$Workers = 6,
    [switch]$Quick
)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

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

# DirStat function BODY injected into every runspace via SessionStateFunctionEntry
# (the entry IS the function body; do not wrap it in `function Get-DirStat {}` again).
# - skips reparse points (NTFS junctions double-count and can loop forever:
#   "Application Data", "Local Settings" under user profiles)
# - enforces a per-target deadline and a depth cap
$WalkerDef = @'
param([string]$Path, [int]$MaxSeconds = 120)

$r = [ordered]@{ Path = $Path; Exists = $false; Bytes = 0.0; Files = 0; Dirs = 0;
                 Junctions = 0; Errors = 0; TimedOut = $false; DepthCapped = $false }
if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
    return [pscustomobject]$r
}
$r.Exists = $true
$deadline = [datetime]::Now.AddSeconds($MaxSeconds)
$stack = New-Object System.Collections.Generic.Stack[object]
$stack.Push(@{ P = $Path; D = 0 })

while ($stack.Count -gt 0) {
    if ([datetime]::Now -gt $deadline) { $r.TimedOut = $true; break }
    $item = $stack.Pop()
    $current = $item.P
    if ($item.D -ge 40) { $r.DepthCapped = $true; continue }
    try {
        foreach ($f in [System.IO.Directory]::EnumerateFiles($current)) {
            try { $r.Bytes += ([System.IO.FileInfo]::new($f)).Length; $r.Files++ } catch { $r.Errors++ }
        }
    } catch { $r.Errors++ }
    try {
        foreach ($d in [System.IO.Directory]::EnumerateDirectories($current)) {
            try {
                $attr = [System.IO.File]::GetAttributes($d)
                if (($attr -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { $r.Junctions++; continue }
            } catch { $r.Errors++; continue }
            $r.Dirs++
            $stack.Push(@{ P = $d; D = $item.D + 1 })
        }
    } catch { $r.Errors++ }
}
return [pscustomobject]$r
'@

# ---------------------------------------------------------------- targets
# Tier meaning (execution is gated per tier by the agent, never auto-deleted here):
#   T0 = info only, not cleanable via this skill (pagefile, WSL vhdx pointers, ...)
#   T1 = zero-risk debris (temp/cache, in-use files simply fail and are skipped)
#   T2 = regenerable caches; check the Guard column before deleting (pins, closed apps)
#   T3 = needs human judgment per item (tools/data, protected content, system knobs)

$userProfile = $env:USERPROFILE
$localAppData = $env:LOCALAPPDATA
$appData = $env:APPDATA
$programData = $env:ProgramData
$windir = $env:windir

$NewTarget = {
    param($Id, $Name, $Path, $Tier, $Guard, $Secs)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    # NOTE: PSCustomObject does NOT allow adding properties after creation, so
    # IsPattern/Pattern/HitCount must be declared here up front (traps #26).
    return [pscustomobject]@{
        Id = $Id; Name = $Name; Path = $Path; Tier = $Tier; Guard = $Guard
        MaxSeconds = if ($Secs) { $Secs } else { $MaxSecondsPerTarget }
        Bytes = 0.0; Files = 0; Junctions = 0; Errors = 0; TimedOut = $false; Exists = $false
        IsPattern = $false; Pattern = $null; HitCount = 0
    }
}

$targets = New-Object System.Collections.Generic.List[object]

$npmCache = @($localAppData + "\npm-cache", $appData + "\npm-cache") | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

# Pattern-based discovery: many app caches follow a naming convention and are
# invisible to a fixed target list. Discovered paths become extra targets.
$DiscoverPatterns = @(
    @{ Id = "app-updater-dirs"; Name = "App auto-update packages"; Tier = "T1";
       Root = $localAppData; Pattern = '*-updater$'; Guard = "Electron app updater leftovers. Only under LocalAppData; ProgramData equivalents may be driver components." }
    @{ Id = "vscode-guid-residue"; Name = "VS Code extension GUID residue"; Tier = "T1";
       Root = ($userProfile + "\.vscode\extensions"); Pattern = '^\.[0-9a-f]{8}-[0-9a-f]{4}-'; Guard = "Interrupted extension installs. Match a GUID-named dir under .vscode/extensions. Trash residue, not real extensions (traps #14)." }
    @{ Id = "codex-runtime-backups"; Name = "Codex runtime backups"; Tier = "T1";
       Root = ($userProfile + "\.cache\codex-runtimes"); Pattern = 'codex-primary-runtime\.previous-.*'; Guard = "Previous runtime snapshots kept by codex. Keep the non-'previous' one (traps #24)." }
)

$defs = @(
    # ---- T0: report only -------------------------------------------------
    @{ Id = "pagefile";      Name = "Page file";               Path = "C:\pagefile.sys";  Tier = "T0"; Guard = "System-managed. Never delete; explains free-space fluctuation (traps #21)." }
    @{ Id = "hiberfil";      Name = "Hibernation file";        Path = "C:\hiberfil.sys";  Tier = "T0"; Guard = "Remove only via 'powercfg /h off' (loses hibernation). T3 decision." }
    @{ Id = "swapfile";      Name = "Swap file";               Path = "C:\swapfile.sys";  Tier = "T0"; Guard = "System-managed." }
    @{ Id = "recycle-bin";   Name = "Recycle Bin";             Path = "C:\`$Recycle.Bin"; Tier = "T0"; Guard = "Emptying needs explicit confirmation (contents may be wanted)." }
    @{ Id = "svi";           Name = "Shadow copies / VSS";     Path = "C:\System Volume Information"; Tier = "T0"; Guard = "Managed via vssadmin; needs admin and judgment." }
    # ---- T1: zero-risk debris -------------------------------------------
    @{ Id = "user-temp";     Name = "User temp";               Path = ($localAppData + "\Temp"); Tier = "T1"; Guard = "In-use files fail and are skipped. Exclude ps-script-* (traps #20). If VS Installer was active in the last 48h, first check %TEMP% for its random-name dirs (traps #4)." }
    @{ Id = "windows-temp";  Name = "Windows temp";            Path = ($windir + "\Temp"); Tier = "T1"; Guard = "Needs admin. In-use files skipped." }
    @{ Id = "npm-cache";     Name = "npm cache";               Path = $npmCache;          Tier = "T1"; Guard = "'npm cache clean --force' equivalent." }
    @{ Id = "pip-cache";     Name = "pip cache";               Path = ($localAppData + "\pip\Cache"); Tier = "T1"; Guard = "Re-downloaded on demand." }
    @{ Id = "uv-cache";      Name = "uv cache";                Path = ($localAppData + "\uv\cache"); Tier = "T1"; Guard = "Cache only. Do NOT touch ..\uv\python (installed interpreters, T3)." }
    @{ Id = "delivery-opt";  Name = "Delivery Optimization";   Path = ($programData + "\Microsoft\Windows\DeliveryOptimization\Cache"); Tier = "T1"; Guard = "Windows re-fills as needed." }
    @{ Id = "vscode-vsix";   Name = "VS Code VSIX cache";     Path = ($appData + "\Code\CachedExtensionVSIXs"); Tier = "T1"; Guard = "Cached extension installers; safe to drop (traps #15). Note: Roaming path." }
    @{ Id = "cursor-cacheddata"; Name = "Cursor CachedData";    Path = ($appData + "\Cursor\CachedData"); Tier = "T1"; Guard = "Close Cursor first." }
    @{ Id = "cursor-logs";   Name = "Cursor logs";             Path = ($appData + "\Cursor\logs"); Tier = "T1"; Guard = "Close Cursor first." }
    @{ Id = "nvidia-ngx";    Name = "NVIDIA NGX (DLSS models)"; Path = ($programData + "\NVIDIA\NGX"); Tier = "T0"; Guard = "DLSS neural models. NOT garbage - deleting breaks DLSS (traps #17)." }
    # ---- T2: regenerable, check guard first ------------------------------
    @{ Id = "jetbrains-local"; Name = "JetBrains caches (Local)"; Path = ($localAppData + "\JetBrains"); Tier = "T2"; Guard = "NEVER delete any LocalHistory folder inside (traps #1). Prefer old-version product dirs." }
    @{ Id = "vscode-cache";    Name = "VS Code Cache";            Path = ($appData + "\Code\Cache"); Tier = "T2"; Guard = "Close VS Code first." }
    @{ Id = "vscode-cacheddata"; Name = "VS Code CachedData";    Path = ($appData + "\Code\CachedData"); Tier = "T2"; Guard = "Close VS Code first." }
    @{ Id = "nuget";           Name = "NuGet packages";           Path = ($userProfile + "\.nuget\packages"); Tier = "T2"; Guard = "Restored on next build (needs network)." }
    @{ Id = "pnpm-store";      Name = "pnpm store";               Path = ($localAppData + "\pnpm\store"); Tier = "T2"; Guard = "'pnpm store prune' is gentler (keeps pinned versions)." }
    @{ Id = "yarn-cache";      Name = "Yarn cache (v1)";          Path = ($localAppData + "\Yarn\Cache"); Tier = "T2"; Guard = "Yarn 1 layout. Berry uses ..\Yarn\Berry\cache (traps #19)." }
    @{ Id = "yarn-berry-cache"; Name = "Yarn Berry cache";        Path = ($localAppData + "\Yarn\Berry\cache"); Tier = "T2"; Guard = "Yarn 2+ layout (traps #19)." }
    @{ Id = "bun-cache";       Name = "Bun cache";                Path = ($userProfile + "\.bun\install\cache"); Tier = "T2"; Guard = "" }
    @{ Id = "cargo-registry";  Name = "Cargo registry";           Path = ($userProfile + "\.cargo\registry"); Tier = "T2"; Guard = "Next offline build re-downloads. Keep if you build with --offline." }
    @{ Id = "go-build";        Name = "Go build cache";           Path = ($localAppData + "\go-build"); Tier = "T2"; Guard = "'go clean -cache' equivalent." }
    @{ Id = "conda-pkgs";      Name = "Conda pkgs";               Path = ($userProfile + "\.conda\pkgs"); Tier = "T2"; Guard = "'conda clean --all' equivalent." }
    @{ Id = "gradle-caches";   Name = "Gradle caches";            Path = ($userProfile + "\.gradle\caches"); Tier = "T2"; Guard = "Check project Gradle wrapper pin first (traps #3). Does not touch ..\gradle\wrapper." }
    @{ Id = "m2-repo";         Name = "Maven .m2 repository";     Path = ($userProfile + "\.m2\repository"); Tier = "T2"; Guard = "Re-downloads on next build; check for pinned/offline mirrors first." }
    @{ Id = "wupdate-dl";      Name = "Windows Update downloads"; Path = ($windir + "\SoftwareDistribution\Download"); Tier = "T2"; Guard = "Needs admin; stop wuauserv first or use Disk Cleanup." }
    @{ Id = "chrome-cache";    Name = "Chrome cache";             Path = ($localAppData + "\Google\Chrome\User Data\Default\Cache"); Tier = "T2"; Guard = "Close Chrome first; profile data lives elsewhere." }
    @{ Id = "chrome-code-cache"; Name = "Chrome code cache";      Path = ($localAppData + "\Google\Chrome\User Data\Default\Code Cache"); Tier = "T2"; Guard = "Close Chrome first." }
    @{ Id = "chrome-sw";       Name = "Chrome Service Worker";    Path = ($localAppData + "\Google\Chrome\User Data\Default\Service Worker"); Tier = "T2"; Guard = "Close Chrome first. Often much larger than Cache (traps #18)." }
    @{ Id = "edge-cache";      Name = "Edge cache";               Path = ($localAppData + "\Microsoft\Edge\User Data\Default\Cache"); Tier = "T2"; Guard = "Close Edge first." }
    @{ Id = "edge-code-cache"; Name = "Edge code cache";          Path = ($localAppData + "\Microsoft\Edge\User Data\Default\Code Cache"); Tier = "T2"; Guard = "Close Edge first." }
    @{ Id = "edge-sw";         Name = "Edge Service Worker";      Path = ($localAppData + "\Microsoft\Edge\User Data\Default\Service Worker"); Tier = "T2"; Guard = "Close Edge first. Often 6+ GB (traps #18)." }
    @{ Id = "cursor-partitions"; Name = "Cursor partitions";      Path = ($appData + "\Cursor\Partitions"); Tier = "T2"; Guard = "Close Cursor first." }
    @{ Id = "nvm-versions";    Name = "nvm node versions";         Path = ($localAppData + "\nvm"); Tier = "T2"; Guard = "Per-version dirs. 'nvm list' shows which one is active - do not delete it (traps #23)." }
    # ---- T2-guard: regenerable but version-pinned ------------------------
    @{ Id = "ms-playwright";   Name = "Playwright browsers";      Path = ($localAppData + "\ms-playwright"); Tier = "T2"; Guard = "Check pinned browser build in projects first (traps #3); re-download is ~300MB." }
    # ---- T3: judgment per item -------------------------------------------
    @{ Id = "jetbrains-roaming"; Name = "JetBrains config/plugins (Roaming)"; Path = ($appData + "\JetBrains"); Tier = "T3"; Guard = "Settings and plugins. Only old-version dirs; verify plugin zips have a Roaming copy (traps #2)." }
    @{ Id = "android-avd";       Name = "Android AVDs (emulators)";          Path = ($userProfile + "\.android\avd"); Tier = "T3"; Guard = "Per-item only. Check LastWriteTime - an AVD modified today is in use. Each is 4-6 GB (traps #25)." }
    @{ Id = "android-sdk";       Name = "Android SDK";                        Path = ($localAppData + "\Android\Sdk"); Tier = "T3"; Guard = "Use SDK Manager; system images / build-tools per project." }
    @{ Id = "android-user";      Name = "Android user data";                  Path = ($userProfile + "\.android"); Tier = "T3"; Guard = "AVDs, adb keys, debug keystore. Per-item only." }
    @{ Id = "docker-local";      Name = "Docker Desktop data";                Path = ($localAppData + "\Docker"); Tier = "T3"; Guard = "Never rm. 'docker system prune' / DiskImage compact." }
    @{ Id = "docker-progdata";   Name = "Docker ProgramData";                 Path = ($programData + "\Docker"); Tier = "T3"; Guard = "Never rm. Same as above." }
    @{ Id = "wsl-packages";      Name = "WSL/app packages";                   Path = ($localAppData + "\Packages"); Tier = "T3"; Guard = "Find ext4.vhdx; clean inside WSL then 'wsl --shutdown' + compact. Never delete directly." }
    @{ Id = "package-cache";     Name = "Package Cache (installers)";         Path = ($programData + "\Package Cache"); Tier = "T3"; Guard = "GUID-orphan heuristics are invalid (traps #5). Reversible move -> rebuild test -> delete. MSVC/SDK payloads may be needed by toolchains." }
    @{ Id = "vs-temp";           Name = "VS Installer temp";                  Path = ($localAppData + "\Temp\VS"); Tier = "T3"; Guard = "Check BackgroundDownload activity by file mtime, not process names (traps #4)." }
    @{ Id = "uv-python";         Name = "uv managed pythons";                 Path = ($localAppData + "\uv\python"); Tier = "T3"; Guard = "Pinned toolchains; deleting breaks 'uv run' envs." }
    @{ Id = "rustup-toolchains"; Name = "Rust toolchains";                    Path = ($userProfile + "\.rustup\toolchains"); Tier = "T3"; Guard = "Per-toolchain. 'rustup toolchain list' shows active ones." }
    @{ Id = "tencent-wechat";    Name = "Tencent/WeChat app data";            Path = ($appData + "\Tencent"); Tier = "T3"; Guard = "App data, not cache. Prefer WeChat's built-in storage cleanup." }
    @{ Id = "nvidia-nsight";     Name = "NVIDIA Nsight installer";            Path = ($programData + "\NVIDIA Corporation\Nsight"); Tier = "T1"; Guard = "Installer leftovers only. Do NOT touch ..\NVIDIA\NGX (traps #17)." }
)

foreach ($d in $defs) { $nt = & $NewTarget @d; if ($null -ne $nt) { $targets.Add($nt) } }

# ---- pattern-based discovery -> extra targets -------------------------
foreach ($dp in $DiscoverPatterns) {
    if ([string]::IsNullOrWhiteSpace($dp.Root) -or -not (Test-Path -LiteralPath $dp.Root)) { continue }
    try {
        $hits = Get-ChildItem -LiteralPath $dp.Root -Force -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match $dp.Pattern }
    } catch { $hits = @() }
    if (-not $hits) { continue }
    $nt = & $NewTarget $dp.Id $dp.Name $dp.Root $dp.Tier $dp.Guard
    if ($null -ne $nt) { $nt.IsPattern = $true; $nt.Pattern = $dp.Pattern; $nt.HitCount = @($hits).Count; $targets.Add($nt) }
}

# ---------------------------------------------------------------- run pool

$iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
$iss.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList 'Get-DirStat', $WalkerDef))
$pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, [Math]::Max(2, $Workers), $iss, $Host)
$pool.Open()

$jobs = New-Object System.Collections.Generic.List[object]
foreach ($t in $targets) {
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.RunspacePool = $pool
    [void]$ps.AddCommand('Get-DirStat').AddParameter('Path', $t.Path).AddParameter('MaxSeconds', $t.MaxSeconds)
    $jobs.Add([pscustomobject]@{ Target = $t; PS = $ps; Handle = $ps.BeginInvoke() })
}

# Top-level rollup of the drive root (skip with -Quick; Windows\WinSxS dominates runtime)
$topJobs = New-Object System.Collections.Generic.List[object]
if (-not $Quick) {
    $rootEntries = Get-ChildItem -LiteralPath $Drive -Force -ErrorAction SilentlyContinue
    foreach ($e in $rootEntries) {
        if ($e.PSIsContainer) {
            $attr = 0
            try { $attr = [System.IO.File]::GetAttributes($e.FullName) } catch {}
            if (($attr -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            $ps = [System.Management.Automation.PowerShell]::Create()
            $ps.RunspacePool = $pool
            [void]$ps.AddCommand('Get-DirStat').AddParameter('Path', $e.FullName).AddParameter('MaxSeconds', ([Math]::Max(90, $MaxSecondsPerTarget)))
            $topJobs.Add([pscustomobject]@{ Name = $e.Name; Path = $e.FullName; PS = $ps; Handle = $ps.BeginInvoke() })
        }
    }
}

# Drain results as they finish (progress feedback instead of a silent wait)
$free0 = 0.0
try {
    $driveCim = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $Drive.TrimEnd('\'))
    if ($null -ne $driveCim) { $free0 = [double]$driveCim.FreeSpace }
} catch {}

while ($jobs.Count -gt 0) {
    $done = $jobs | Where-Object { $_.Handle.IsCompleted }
    foreach ($j in $done) {
        try {
            $res = $j.PS.EndInvoke($j.Handle)
            if ($res) {
                $j.Target.Bytes = $res.Bytes; $j.Target.Files = $res.Files
                $j.Target.Junctions = $res.Junctions; $j.Target.Errors = $res.Errors
                $j.Target.TimedOut = $res.TimedOut; $j.Target.Exists = $res.Exists
            }
        } catch { $j.Target.Errors++ }
        $j.PS.Dispose()
        $jobs.Remove($j) | Out-Null
    }
    if ($jobs.Count -gt 0) { Start-Sleep -Milliseconds 300 }
}

$topRows = New-Object System.Collections.Generic.List[object]
while ($topJobs.Count -gt 0) {
    $done = $topJobs | Where-Object { $_.Handle.IsCompleted }
    foreach ($j in $done) {
        try {
            $res = $j.PS.EndInvoke($j.Handle)
            if ($res) { $topRows.Add([pscustomobject]@{ Name = $j.Name; Path = $j.Path; Bytes = $res.Bytes; Files = $res.Files; TimedOut = $res.TimedOut }) }
        } catch {}
        $j.PS.Dispose()
        $topJobs.Remove($j) | Out-Null
    }
    if ($topJobs.Count -gt 0) { Start-Sleep -Milliseconds 300 }
}

# Root-level system files (pagefile/hiberfil/swapfile) are invisible to Test-Path
# for non-admin tokens but readable via the parent listing; patch them in here so
# the T0 section shows why free space fluctuates instead of claiming they are absent.
$drivePrefix = $Drive.TrimEnd('\') + '\'
$rootFiles = Get-ChildItem -LiteralPath $Drive -Force -File -ErrorAction SilentlyContinue
foreach ($f in $rootFiles) {
    $full = $drivePrefix + $f.Name
    $topRows.Add([pscustomobject]@{ Name = $f.Name; Path = $full; Bytes = [double]$f.Length; Files = 1; TimedOut = $false })
    foreach ($t in $targets) {
        if ($t.Path -and ($t.Path.TrimEnd('\').ToLowerInvariant() -eq $full.ToLowerInvariant())) {
            $t.Exists = $true; $t.Bytes = [double]$f.Length; $t.Files = 1
        }
    }
}
$pool.Close()

$stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$driveName = $Drive.TrimEnd('\')

# ---------------------------------------------------------------- report

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("# Drive scan report - $driveName ($stamp)")
[void]$sb.AppendLine()
[void]$sb.AppendLine("Free space now: **$(Format-Bytes $free0)** / total (apparent sizes; NTFS junctions skipped).")
[void]$sb.AppendLine()
[void]$sb.AppendLine("Tiers: **T0** info only | **T1** zero-risk debris | **T2** regenerable (check guard) | **T3** judgment per item.")
[void]$sb.AppendLine()

if ($topRows.Count -gt 0) {
    [void]$sb.AppendLine("## Top-level directories")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("| Directory | Size | Files | Timed out |")
    [void]$sb.AppendLine("|---|---|---|---|")
    foreach ($row in ($topRows | Sort-Object Bytes -Descending)) {
        [void]$sb.AppendLine("| $(Escape-Md $row.Name) | $(Format-Bytes $row.Bytes) | $($row.Files) | $(if ($row.TimedOut) {'yes'} else {'-'}) |")
    }
    [void]$sb.AppendLine()
}

foreach ($tier in @("T1", "T2", "T3", "T0")) {
    $rows = @($targets | Where-Object { $_.Tier -eq $tier -and $_.Exists } | Sort-Object Bytes -Descending)
    if ($rows.Count -eq 0) { continue }
    [void]$sb.AppendLine("## $tier targets")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("| Id | Path | Size | Files | Status | Guard |")
    [void]$sb.AppendLine("|---|---|---|---|---|---|")
    foreach ($r in $rows) {
        $status = "ok"
        if (-not $r.Exists) { $status = "missing" }
        if ($r.TimedOut) { $status = "timed-out (size is a floor)" }
        if ($r.PSObject.Properties['IsPattern'] -and $r.IsPattern) { $status += " / pattern-matched ($($r.HitCount) dirs)" }
        [void]$sb.AppendLine("| $($r.Id) | $(Escape-Md $r.Path) | $(Format-Bytes $r.Bytes) | $($r.Files) | $status | $(Escape-Md $r.Guard) |")
    }
    [void]$sb.AppendLine()
}

$missing = @($targets | Where-Object { -not $_.Exists })
if ($missing.Count -gt 0) {
    [void]$sb.AppendLine("## Not present on this machine")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine(($(($missing | ForEach-Object { $_.Id }) -join ", ")))
    [void]$sb.AppendLine()
}

[void]$sb.AppendLine("> Apparent-size caveat: sums of file lengths; sparse/compressed/0.00GB rows can mislead (traps #12).")
[void]$sb.AppendLine("> Clean-CDriveTier.ps1 consumes the JSON plan for execution; this report is for humans.")

if ([string]::IsNullOrWhiteSpace($OutFile)) {
    $OutFile = Join-Path (Get-Location) ("scan-report-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".md")
}
[System.IO.File]::WriteAllText($OutFile, $sb.ToString(), [System.Text.Encoding]::UTF8)
Write-Host "Report: $OutFile"

if (-not [string]::IsNullOrWhiteSpace($Json)) {
    $plan = [pscustomobject]@{
        generated  = $stamp
        drive      = $driveName
        freeBytes  = $free0
        # IsPattern/Pattern must be exported: Clean-CDriveTier.ps1 reads them
        # from the plan to know which targets are "delete matching children"
        # instead of "delete the whole target".
        targets    = @($targets | Select-Object Id, Name, Path, Tier, Guard, MaxSeconds, Bytes, Files, Exists, TimedOut, IsPattern, Pattern, HitCount)
    }
    [System.IO.File]::WriteAllText($Json, ($plan | ConvertTo-Json -Depth 4), [System.Text.Encoding]::UTF8)
    Write-Host "Plan JSON: $Json"
}

# Console summary (worst offenders first)
$targets | Where-Object { $_.Exists -and $_.Tier -ne "T0" } | Sort-Object Bytes -Descending |
    Select-Object -First 15 @{ n = "Tier"; e = { $_.Tier } }, Id, @{ n = "Size"; e = { Format-Bytes $_.Bytes } } |
    Format-Table -AutoSize | Out-String | Write-Host
