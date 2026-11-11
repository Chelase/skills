<#
.SYNOPSIS
    MySQL/MariaDB health check + ad-hoc SQL runner, with multi-profile + SSH tunnel.

.DESCRIPTION
    Detects local Windows MySQL services, probes TCP 3306, opens an authenticated
    MySQL connection (via bundled MySqlConnector.dll, NO mysql.exe required), and
    reports server version / charset / hostname / tables.

    Can also execute arbitrary SQL via -Query or -QueryFile. By default any
    write-like statement is REFUSED unless -AllowWrite is supplied.

    Supports named profiles from a JSON config file so you can switch between
    dev/staging/prod without re-typing credentials. For databases behind a bastion
    (reachable only via SSH), profiles can carry an `ssh` block; the script opens
    a local-port forward and tears the tunnel down on exit.

    Requires PowerShell 7.2+ (uses modern .NET APIs).

.PARAMETER Server / Port / User / Password / Database
    Standard MySQL connection params. CLI args override profile values.

.PARAMETER LocalOnly
    If set, skip remote auth. Only check local service + TCP + module load.

.PARAMETER Config
    Path to JSON config. Default: $env:USERPROFILE\.mysql-check\config.json

.PARAMETER Profile
    Name of a profile defined in the config file.

.PARAMETER ListProfiles
    List all profiles (passwords masked) and exit.

.PARAMETER SaveProfile
    After run, save the resolved values as a new named profile.

.PARAMETER SshTunnelPort / SshWaitSeconds
    SSH tunnel local port (default 13306) and wait timeout (default 8s).

.PARAMETER Query
    A SQL statement to run. By default read-only; write statements need -AllowWrite.

.PARAMETER QueryFile
    Path to a .sql file. Mutually exclusive with -Query.

.PARAMETER AllowWrite
    Opt-in flag that permits write statements.

.PARAMETER ResultFormat
    How to format query result sets: Table (default), Json, Csv, Raw.

.PARAMETER QueryTimeoutSec
    Query timeout. Default 30.

.PARAMETER InstallPowerShell
    If PS < 7.2 detected, auto-install via winget. Requires admin.

.PARAMETER SkipPowerShellCheck
    Bypass the PS 7.2+ check. Not recommended.

.PARAMETER Init
    First-time setup wizard. Asks for profile name, host, port, user, password,
    optional database, optional SSH config. Tests the connection and saves the
    profile to %USERPROFILE%\.mysql-check\config.json. If config or the named
    profile already exists, aborts unless -ForceProfile is also set.

.PARAMETER ForceProfile
    With -Init, overwrite an existing profile with the same name.

.EXAMPLE
    pwsh -File Test-MysqlConnection.ps1 -Profile prod

.EXAMPLE
    pwsh -File Test-MysqlConnection.ps1 -Profile wkbox2

.EXAMPLE
    pwsh -File Test-MysqlConnection.ps1 -Profile prod -Query "SELECT COUNT(*) FROM users"

.EXAMPLE
    pwsh -File Test-MysqlConnection.ps1 -Profile prod -Query "DELETE FROM logs WHERE created < NOW() - INTERVAL 30 DAY" -AllowWrite

.EXAMPLE
    pwsh -File Test-MysqlConnection.ps1 -LocalOnly

.EXAMPLE
    pwsh -File Test-MysqlConnection.ps1 -Init    # first-time setup wizard
#>

[CmdletBinding()]
param(
    [string]$Server,
    [Nullable[int]]$Port,
    [string]$User,
    [string]$Password,
    [string]$Database,
    [switch]$LocalOnly,
    [string]$Config,
    [string]$Profile,
    [switch]$ListProfiles,
    [string]$SaveProfile,
    [int]$SshTunnelPort = 13306,
    [int]$SshWaitSeconds = 8,
    [string]$Query,
    [string]$QueryFile,
    [switch]$AllowWrite,
    [ValidateSet('Table','Json','Csv','Raw')]
    [string]$ResultFormat = 'Table',
    [int]$QueryTimeoutSec = 30,
    [switch]$InstallPowerShell,
    [switch]$SkipPowerShellCheck,
    [switch]$Init,
    [switch]$ForceProfile
)

$ErrorActionPreference = 'Continue'

# --- 0. PowerShell version gate -------------------------------------------

function Test-CommandAvailable([string]$Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Install-PowerShell7 {
    Write-Host ""
    Write-Host "=== Installing PowerShell 7 ===" -ForegroundColor Cyan
    if (Test-CommandAvailable 'winget') {
        Write-Host "  using: winget install Microsoft.PowerShell"
        $proc = Start-Process -FilePath 'winget' -ArgumentList @(
            'install', '--id', 'Microsoft.PowerShell',
            '--silent', '--accept-package-agreements', '--accept-source-agreements'
        ) -PassThru -Wait -NoNewWindow
        if ($proc.ExitCode -eq 0) {
            Write-Host "  OK: PowerShell 7 installed. Re-run with 'pwsh'." -ForegroundColor Green
            return $true
        } else {
            Write-Host "  winget failed (exit $($proc.ExitCode)). Trying choco..." -ForegroundColor Yellow
        }
    }
    if (Test-CommandAvailable 'choco') {
        $proc = Start-Process -FilePath 'choco' -ArgumentList @('install','powershell-core','-y','--no-progress') -PassThru -Wait -NoNewWindow
        if ($proc.ExitCode -eq 0) { Write-Host "  OK via Chocolatey." -ForegroundColor Green; return $true }
    }
    Write-Host "  No package manager. Manual: https://github.com/PowerShell/PowerShell/releases" -ForegroundColor Red
    return $false
}

if (-not $SkipPowerShellCheck) {
    $ver = $PSVersionTable.PSVersion
    if ($ver.Major -lt 7 -or ($ver.Major -eq 7 -and $ver.Minor -lt 2)) {
        Write-Host ""
        Write-Host "=== PowerShell version check ===" -ForegroundColor Cyan
        Write-Host ("  Current: PS {0}.{1}.{2}" -f $ver.Major, $ver.Minor, $ver.Patch) -ForegroundColor Yellow
        Write-Host "  Required: PS 7.2+ (uses modern .NET runtime)"
        Write-Host ""
        if ($InstallPowerShell) {
            if (-not (Install-PowerShell7)) { exit 1 }
            Write-Host "  (re-run with pwsh.exe to use the new install)"
            exit 0
        } else {
            Write-Host "  Options:" -ForegroundColor Cyan
            if (Test-CommandAvailable 'winget') {
                Write-Host "    1) Auto-install:  pwsh -File `"$PSCommandPath`" -InstallPowerShell"
            } else {
                Write-Host "    1) Install winget first, then:  pwsh -File `"$PSCommandPath`" -InstallPowerShell"
            }
            Write-Host "    2) Manual:  winget install Microsoft.PowerShell"
            Write-Host "    3) Bypass:  pwsh -File `"$PSCommandPath`" -SkipPowerShellCheck  (NOT recommended)"
            Write-Host ""
            Write-Host "  Aborting." -ForegroundColor Red
            exit 2
        }
    }
}

# --- helpers ---------------------------------------------------------------

function Write-Row {
    param([string]$Status, [string]$Item, [string]$Detail)
    $color = switch ($Status) {
        'OK'   { 'Green'  }
        'WARN' { 'Yellow' }
        'FAIL' { 'Red'    }
        default { 'White'  }
    }
    Write-Host ("{0,-6} {1,-30} {2}" -f $Status, $Item, $Detail) -ForegroundColor $color
}

function Resolve-ConfigPath {
    if ($Config) {
        $r = Resolve-Path -LiteralPath $Config -ErrorAction SilentlyContinue
        if ($r) { return $r.Path }
        return $Config
    }
    if ($env:MYSQL_CHECK_CONFIG) { return $env:MYSQL_CHECK_CONFIG }
    $dir = Join-Path $env:USERPROFILE '.mysql-check'
    return (Join-Path $dir 'config.json')
}

function Load-Config([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json)
    } catch {
        Write-Row 'FAIL' 'config' "could not parse $Path — $($_.Exception.Message)"
        exit 1
    }
}

function Format-ProfileRow {
    param($Name, $Obj)
    $server = if ($Obj.server) { $Obj.server } else { '(none)' }
    $port   = if ($Obj.port)   { $Obj.port }   else { '3306' }
    $user   = if ($Obj.user)   { $Obj.user }   else { '(none)' }
    $db     = if ($Obj.database) { $Obj.database } else { '(none)' }
    $pw     = if ($Obj.password) { '****' } else { '(none)' }
    $ssh    = if ($Obj.ssh) { "ssh=$($Obj.ssh.user)@$($Obj.ssh.host):$($Obj.ssh.port)" } else { '' }
    $line = "{0,-20} {1,-22}:{2,-5} {3,-20} db={4,-20} pw={5}" -f $Name, $server, $port, $user, $db, $pw
    if ($ssh) { $line += "  [$ssh]" }
    return $line
}

function Test-ConfigPermissions([string]$Path) {
    try {
        $acl = Get-Acl -LiteralPath $Path -ErrorAction SilentlyContinue
        if (-not $acl) { return }
        $worldSid = New-Object System.Security.Principal.SecurityIdentifier 'S-1-1-0'
        $hit = $acl.Access | Where-Object { $_.IdentityReference -eq $worldSid -and $_.AccessControlType -eq 'Allow' }
        if ($hit) {
            Write-Row 'WARN' 'config-acl' "$Path is readable by Everyone; restrict with: icacls `"$Path`" /inheritance:r /grant:r `"$env:USERNAME:R`""
        }
    } catch { }
}

# --- MySqlConnector loader (bundled DLL, no PSGallery needed) -------------

$script:MySqlLoaded = $false

function Ensure-MySqlConnector {
    $asm = [System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq 'MySqlConnector' }
    if ($asm) {
        $script:MySqlLoaded = $true
        return $true
    }
    $libDir = Join-Path $PSScriptRoot '..\lib'
    $dll = Join-Path $libDir 'MySqlConnector.dll'
    if (-not (Test-Path -LiteralPath $dll)) {
        Write-Row 'FAIL' 'mysql-driver' "MySqlConnector.dll not found at $dll"
        Write-Host "  The skill must ship with lib/MySqlConnector.dll + its dependencies." -ForegroundColor Yellow
        return $false
    }
    try {
        Add-Type -Path $dll -ErrorAction Stop
        $script:MySqlLoaded = $true
        return $true
    } catch {
        Write-Row 'FAIL' 'mysql-driver' "Add-Type failed: $($_.Exception.Message)"
        return $false
    }
}

function Open-MySqlConnection([string]$ConnString) {
    $conn = [MySqlConnector.MySqlConnection]::new($ConnString)
    $conn.Open()
    return $conn
}

# --- SSH tunnel -----------------------------------------------------------

function Resolve-SshAuth {
    param($Ssh)
    if ($Ssh.key) {
        # If key path was set but file is missing, auto-generate it.
        if (-not (Test-Path -LiteralPath $Ssh.key)) {
            Write-Host ""
            Write-Host "  SSH key not found at: $($Ssh.key)" -ForegroundColor Yellow
            if (Ensure-SshKey $Ssh.key) {
                return 'key'
            }
            Write-Host "  cannot continue without key" -ForegroundColor Red
            return $null
        }
        return 'key'
    }
    if ($Ssh.password) {
        if (Get-Command plink.exe -ErrorAction SilentlyContinue) { return 'plink' }
        if (Get-Command sshpass.exe -ErrorAction SilentlyContinue) { return 'sshpass' }
        if (Get-Module -ListAvailable -Name Posh-SSH) { return 'posh' }
        # No plink/sshpass/Posh-SSH but we have a password — try to install plink automatically.
        Write-Host ""
        Write-Host "  SSH password auth requested but no SSH client tool found." -ForegroundColor Yellow
        if (Install-Plink) {
            if (Get-Command plink.exe -ErrorAction SilentlyContinue) { return 'plink' }
        }
        Write-Host "  tried to install plink, but still not found. Install PuTTY/choco manually." -ForegroundColor Red
    }
    return $null
}

function Start-SshTunnel {
    param($Ssh, [int]$RemotePort, [int]$LocalPort, [int]$WaitSeconds)
    $method = Resolve-SshAuth $Ssh
    if (-not $method) {
        Write-Row 'FAIL' 'ssh-auth' @"
no usable SSH auth method. Need one of:
  1. SSH key  -> set profile ssh.key
  2. plink.exe on PATH -> password
  3. sshpass.exe on PATH -> password
  4. Posh-SSH module -> password

Quick key setup:
  ssh-keygen -t ed25519 -f "$env:USERPROFILE\.ssh\id_ed25519" -N '""'
"@
        exit 1
    }
    Write-Row 'OK' 'ssh-auth' "using $method"
    $handle = $null
    switch ($method) {
        'key' {
            $sshArgs = @(
                '-i', $Ssh.key,
                '-L', "${LocalPort}:127.0.0.1:${RemotePort}",
                '-p', "$($Ssh.port)", '-N',
                '-o', 'BatchMode=yes',
                '-o', 'ExitOnForwardFailure=yes',
                '-o', 'StrictHostKeyChecking=accept-new',
                "$($Ssh.user)@$($Ssh.host)"
            )
            $handle = [pscustomobject]@{
                Method = 'proc'
                Process = (Start-Process -FilePath 'ssh.exe' -ArgumentList $sshArgs -PassThru -WindowStyle Hidden)
            }
        }
        'plink' {
            $plink = (Get-Command plink.exe).Source
            $plinkArgs = @(
                '-ssh',
                '-L', "${LocalPort}:127.0.0.1:${RemotePort}",
                '-P', "$($Ssh.port)", '-N',
                '-pw', $Ssh.password, '-batch'
            )
            if ($Ssh.hostkey) { $plinkArgs += @('-hostkey', $Ssh.hostkey) }
            $plinkArgs += "$($Ssh.user)@$($Ssh.host)"
            $handle = [pscustomobject]@{
                Method = 'proc'
                Process = (Start-Process -FilePath $plink -ArgumentList $plinkArgs -PassThru -WindowStyle Hidden)
            }
        }
        'sshpass' {
            $sshpass = (Get-Command sshpass.exe).Source
            $env:SSHPASS = $Ssh.password
            $spArgs = @(
                '-e', 'ssh',
                '-L', "${LocalPort}:127.0.0.1:${RemotePort}",
                '-p', "$($Ssh.port)", '-N',
                '-o', 'ExitOnForwardFailure=yes',
                '-o', 'StrictHostKeyChecking=accept-new',
                "$($Ssh.user)@$($Ssh.host)"
            )
            $handle = [pscustomobject]@{
                Method = 'proc'
                Process = (Start-Process -FilePath $sshpass -ArgumentList $spArgs -PassThru -WindowStyle Hidden)
            }
        }
        'posh' {
            Import-Module Posh-SSH -ErrorAction Stop
            $cred = New-Object PSCredential($Ssh.user, (ConvertTo-SecureString $Ssh.password -AsPlainText -Force))
            $session = New-SSHSession -ComputerName $Ssh.host -Port ([int]$Ssh.port) -Credential $cred -AcceptKey:$true -Force
            # Posh-SSH 从未提供 New-SSHPortForward；本地转发一律用 New-SSHLocalPortForward。
            # 3.x 用 -BoundHost/-BoundPort，2.x 用 -LocalAdress/-LocalPort，按实际参数名选择。
            $fwd = Get-Command New-SSHLocalPortForward -ErrorAction Stop
            $fwdArgs = @{ RemoteAddress = '127.0.0.1'; RemotePort = $RemotePort; SessionId = $session.SessionId }
            if ($fwd.Parameters.ContainsKey('BoundPort')) {
                $fwdArgs['BoundHost'] = '127.0.0.1'
                $fwdArgs['BoundPort'] = $LocalPort
            } else {
                $fwdArgs['LocalAdress'] = '127.0.0.1'
                $fwdArgs['LocalPort'] = $LocalPort
            }
            New-SSHLocalPortForward @fwdArgs | Out-Null
            $handle = [pscustomobject]@{
                Method = 'posh'
                Session = $session
            }
        }
    }
    $ready = $false
    for ($i = 0; $i -lt $WaitSeconds; $i++) {
        Start-Sleep -Seconds 1
        $ok = Test-NetConnection -ComputerName 127.0.0.1 -Port $LocalPort -InformationLevel Quiet -WarningAction SilentlyContinue 2>$null
        if ($ok) { $ready = $true; break }
    }
    if (-not $ready) {
        Stop-SshTunnel $handle
        Write-Row 'FAIL' 'ssh-tunnel' "port $LocalPort not listening after ${WaitSeconds}s; tunnel failed"
        exit 1
    }
    Write-Row 'OK' 'ssh-tunnel' "127.0.0.1:$LocalPort -> 127.0.0.1:$RemotePort via $($Ssh.user)@$($Ssh.host):$($Ssh.port)"
    return $handle
}

function Stop-SshTunnel {
    param($Handle)
    if (-not $Handle) { return }
    try {
        if ($Handle.Method -eq 'posh' -and $Handle.Session) {
            Remove-SSHSession -SessionId $Handle.Session.SessionId -ErrorAction SilentlyContinue
        } elseif ($Handle.Method -eq 'proc' -and $Handle.Process) {
            $p = $Handle.Process
            if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
        }
    } catch { }
    if ($env:SSHPASS) { Remove-Item Env:SSHPASS -ErrorAction SilentlyContinue }
}

# --- SQL safety guard -----------------------------------------------------

$script:WritePatterns = @(
    '^\s*INSERT\b', '^\s*UPDATE\b', '^\s*DELETE\b', '^\s*REPLACE\b',
    '^\s*CREATE\b', '^\s*DROP\b', '^\s*ALTER\b', '^\s*TRUNCATE\b',
    '^\s*RENAME\b', '^\s*GRANT\b', '^\s*REVOKE\b',
    '^\s*SET\s+', '^\s*CALL\b', '^\s*LOAD\s+DATA\b',
    '^\s*LOCK\b', '^\s*UNLOCK\b', '^\s*FLUSH\b', '^\s*KILL\b', '^\s*SHUTDOWN\b'
)

function Test-IsWriteQuery([string]$Sql) {
    if ([string]::IsNullOrWhiteSpace($Sql)) { return $false }
    $stripped = $Sql -replace '(?m)^\s*--.*$', '' -replace '(?s)/\*.*?\*/', ''
    foreach ($p in $script:WritePatterns) {
        if ($stripped -match $p) { return $true }
    }
    return $false
}

function Split-SqlStatements([string]$Sql) {
    if ([string]::IsNullOrWhiteSpace($Sql)) { return @() }
    $sb = New-Object System.Text.StringBuilder
    $stmts = New-Object System.Collections.Generic.List[string]
    $inString = $false
    $strChar = ''
    $i = 0
    while ($i -lt $Sql.Length) {
        $c = $Sql[$i]
        if ($inString) {
            [void]$sb.Append($c)
            if ($c -eq '\' -and $i + 1 -lt $Sql.Length) {
                [void]$sb.Append($Sql[$i+1]); $i += 2; continue
            }
            if ($c -eq $strChar) { $inString = $false }
        } else {
            if ($c -eq "'" -or $c -eq '"' -or $c -eq '`') {
                $inString = $true; $strChar = $c; [void]$sb.Append($c)
            } elseif ($c -eq '-' -and $i + 1 -lt $Sql.Length -and $Sql[$i+1] -eq '-') {
                while ($i -lt $Sql.Length -and $Sql[$i] -ne "`n") { $i++ }
            } elseif ($c -eq '/' -and $i + 1 -lt $Sql.Length -and $Sql[$i+1] -eq '*') {
                $i += 2
                while ($i + 1 -lt $Sql.Length -and -not ($Sql[$i] -eq '*' -and $Sql[$i+1] -eq '/')) { $i++ }
                $i += 2
                continue
            } elseif ($c -eq ';') {
                $cur = $sb.ToString().Trim()
                if ($cur) { $stmts.Add($cur) }
                $sb = New-Object System.Text.StringBuilder
            } else {
                [void]$sb.Append($c)
            }
        }
        $i++
    }
    $last = $sb.ToString().Trim()
    if ($last) { $stmts.Add($last) }
    return $stmts.ToArray()
}

# --- Result formatting ---------------------------------------------------

function Write-ResultSet {
    param($Reader, [string]$Format)
    $dt = New-Object System.Data.DataTable
    for ($i = 0; $i -lt $Reader.FieldCount; $i++) {
        [void]$dt.Columns.Add(($Reader.GetName($i)), [object])
    }
    while ($Reader.Read()) {
        $row = $dt.NewRow()
        for ($i = 0; $i -lt $Reader.FieldCount; $i++) {
            $val = $Reader.GetValue($i)
            $row[$i] = if ($val -is [byte[]]) { [System.Convert]::ToBase64String($val) } else { $val }
        }
        [void]$dt.Rows.Add($row)
    }
    $Reader.Close()

    switch ($Format) {
        'Json' {
            Write-Host ("  -> {0} row(s) returned" -f $dt.Rows.Count) -ForegroundColor Green
            if ($dt.Rows.Count -gt 0) { Write-Host ($dt | ConvertTo-Json -Depth 5) } else { Write-Host '  (no rows)' }
        }
        'Csv' {
            Write-Host ("  -> {0} row(s) returned" -f $dt.Rows.Count) -ForegroundColor Green
            $dt | ConvertTo-Csv -NoTypeInformation
        }
        'Raw' {
            Write-Host ("  -> {0} row(s) returned" -f $dt.Rows.Count) -ForegroundColor Green
            $dt
        }
        default {
            if ($dt.Rows.Count -eq 0) {
                Write-Host "  -> 0 rows returned" -ForegroundColor Green
                return
            }
            $colWidths = @()
            for ($i = 0; $i -lt $dt.Columns.Count; $i++) {
                $w = $dt.Columns[$i].ColumnName.Length
                foreach ($r in $dt.Rows) {
                    $len = if ($null -eq $r[$i]) { 4 } else { ($r[$i].ToString()).Length }
                    if ($len -gt $w) { $w = $len }
                }
                if ($w -gt 60) { $w = 60 }
                $colWidths += $w
            }
            $sb = New-Object System.Text.StringBuilder
            $parts = @()
            for ($i = 0; $i -lt $dt.Columns.Count; $i++) {
                $parts += $dt.Columns[$i].ColumnName.PadRight($colWidths[$i])
            }
            [void]$sb.AppendLine(($parts -join '  '))
            $sep = ($colWidths | ForEach-Object { '-' * $_ }) -join '  '
            [void]$sb.AppendLine($sep)
            foreach ($r in $dt.Rows) {
                $parts = @()
                for ($i = 0; $i -lt $dt.Columns.Count; $i++) {
                    $v = if ($null -eq $r[$i]) { 'NULL' } else { $r[$i].ToString() }
                    if ($v.Length -gt $colWidths[$i]) { $v = $v.Substring(0, $colWidths[$i] - 1) + '…' }
                    $parts += $v.PadRight($colWidths[$i])
                }
                [void]$sb.AppendLine(($parts -join '  '))
            }
            Write-Host $sb.ToString()
            Write-Host ("  -> {0} row(s)" -f $dt.Rows.Count) -ForegroundColor Green
        }
    }
}

# --- 0. resolve config & handle list pre-flight ----------------------------

$configPath = Resolve-ConfigPath
$cfg = Load-Config $configPath

# --- -Init: first-time setup wizard ---

function Install-Plink {
    Write-Host "  plink.exe not found. Auto-installing PuTTY..." -ForegroundColor Yellow
    if (Test-CommandAvailable 'winget') {
        $proc = Start-Process -FilePath 'winget' -ArgumentList @(
            'install', '--id', 'PuTTY.PuTTY',
            '--silent', '--accept-package-agreements', '--accept-source-agreements'
        ) -PassThru -Wait -NoNewWindow
        if ($proc.ExitCode -eq 0) {
            # winget installs to a path that may not be in current $env:PATH; refresh
            $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'User') + ';' + [System.Environment]::GetEnvironmentVariable('PATH', 'Machine')
            Write-Host "  OK: PuTTY installed (plink.exe now in PATH)" -ForegroundColor Green
            return $true
        }
        Write-Host "  winget failed (exit $($proc.ExitCode))" -ForegroundColor Yellow
    }
    if (Test-CommandAvailable 'choco') {
        $proc = Start-Process -FilePath 'choco' -ArgumentList @('install','putty','-y','--no-progress') -PassThru -Wait -NoNewWindow
        if ($proc.ExitCode -eq 0) { return $true }
    }
    return $false
}

function Ensure-SshKey {
    param([string]$KeyPath)
    if (Test-Path -LiteralPath $KeyPath) { return $true }
    Write-Host ""
    Write-Host "  SSH key not found at: $KeyPath" -ForegroundColor Yellow
    $ans = Read-Host "  Generate a new ed25519 keypair? (y/N)"
    if ($ans -notmatch '^[Yy]') { return $false }
    $dir = Split-Path -Parent $KeyPath
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    # ssh-keygen on Windows
    $sshKeygen = Get-Command ssh-keygen.exe -ErrorAction SilentlyContinue
    if (-not $sshKeygen) {
        Write-Host "  ssh-keygen.exe not in PATH. Cannot auto-generate." -ForegroundColor Red
        return $false
    }
    $proc = Start-Process -FilePath 'ssh-keygen.exe' -ArgumentList @('-t','ed25519','-f',$KeyPath,'-N','','-q') -PassThru -Wait -NoNewWindow
    if ($proc.ExitCode -eq 0) {
        Write-Host "  OK: keypair generated" -ForegroundColor Green
        Write-Host ""
        Write-Host "  ┌────────────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
        Write-Host "  │  YOU STILL NEED TO PUSH THE PUBLIC KEY TO THE BASTION:         │" -ForegroundColor Yellow
        Write-Host "  │  Add the line below to ~/.ssh/authorized_keys on the SSH host  │" -ForegroundColor Yellow
        Write-Host "  │  (or have your admin do it).                                      │" -ForegroundColor Yellow
        Write-Host "  └────────────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
        Write-Host ""
        $pub = Get-Content "$KeyPath.pub"
        Write-Host "  $pub" -ForegroundColor Cyan
        Write-Host ""
        $ans2 = Read-Host "  Press Enter after you've added the public key to the server (or 's' to skip)"
        return $true
    }
    Write-Host "  ssh-keygen failed (exit $($proc.ExitCode))" -ForegroundColor Red
    return $false
}

function Invoke-Init {
    Write-Host ""
    Write-Host "=== mysql-check first-time setup ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "This wizard walks you through creating your first MySQL connection profile."
    Write-Host "The profile is stored in plain JSON at: $configPath" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "All answers go to a JSON file on YOUR machine. Passwords in plaintext." -ForegroundColor Yellow
    Write-Host "For shared machines, restrict ACL: icacls `"$configPath`" /inheritance:r /grant:r `"`$env:USERNAME`:R`"" -ForegroundColor DarkGray
    Write-Host ""

    $name = (Read-Host "Profile name (e.g. prod, dev, my-wkbox)").Trim()
    if (-not $name) { Write-Host "  no name given, aborting" -ForegroundColor Red; return }
    if ($cfg -and $cfg.profiles -and $cfg.profiles.PSObject.Properties.Name -contains $name) {
        if (-not $ForceProfile) {
            Write-Host "  profile '$name' already exists. Use -ForceProfile to overwrite, or pick a different name." -ForegroundColor Red
            return
        }
        Write-Host "  profile '$name' exists; will overwrite (-ForceProfile)" -ForegroundColor Yellow
    }

    $server = (Read-Host "MySQL host (e.g. 192.168.1.100, db.example.com)").Trim()
    if (-not $server) { Write-Host "  host required, aborting" -ForegroundColor Red; return }

    $portStr = (Read-Host "MySQL port [3306]").Trim()
    $port = if ($portStr) { [int]$portStr } else { 3306 }

    $user = (Read-Host "MySQL user").Trim()
    if (-not $user) { Write-Host "  user required, aborting" -ForegroundColor Red; return }

    $securePw = Read-Host "MySQL password" -AsSecureString
    if (-not $securePw -or $securePw.Length -eq 0) {
        Write-Host "  password required, aborting" -ForegroundColor Red; return
    }
    $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePw))

    $database = (Read-Host "MySQL database (optional, Enter to skip)").Trim()

    $useSsh = (Read-Host "Is the MySQL behind an SSH bastion? (y/N)").Trim()
    $sshBlock = $null
    if ($useSsh -match '^[Yy]') {
        Write-Host ""
        Write-Host "  --- SSH bastion config ---" -ForegroundColor DarkCyan
        $sshHost = (Read-Host "  SSH host (e.g. 10.0.0.1, bastion.example.com)").Trim()
        $sshPortStr = (Read-Host "  SSH port [22]").Trim()
        $sshPort = if ($sshPortStr) { [int]$sshPortStr } else { 22 }
        $sshUser = (Read-Host "  SSH user").Trim()

        $useKey = (Read-Host "  Use SSH key auth? (y/N, default = password)").Trim()
        if ($useKey -match '^[Yy]') {
            $keyPath = (Read-Host "  SSH key path [~/.ssh/id_ed25519]").Trim()
            if (-not $keyPath) { $keyPath = "~/.ssh/id_ed25519" }
            $keyPath = $keyPath -replace '^~', $env:USERPROFILE
            $keyPath = $keyPath -replace '/', [System.IO.Path]::DirectorySeparatorChar
            if (-not (Ensure-SshKey $keyPath)) {
                Write-Host "  cannot continue without key" -ForegroundColor Red; return
            }
            $sshBlock = [pscustomobject]@{
                host = $sshHost
                port = $sshPort
                user = $sshUser
                key  = $keyPath
            }
        } else {
            $secureSsh = Read-Host "  SSH password" -AsSecureString
            if (-not $secureSsh -or $secureSsh.Length -eq 0) {
                Write-Host "  SSH password required for password auth, aborting" -ForegroundColor Red; return
            }
            $sshPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureSsh))
            # Auto-install plink
            if (-not (Get-Command plink.exe -ErrorAction SilentlyContinue)) {
                if (-not (Install-Plink)) {
                    Write-Host "  plink install failed. Manually install PuTTY and re-run." -ForegroundColor Red
                    return
                }
            }
            $sshBlock = [pscustomobject]@{
                host     = $sshHost
                port     = $sshPort
                user     = $sshUser
                password = $sshPassword
            }
        }
    }

    Write-Host ""
    Write-Host "  --- Test connection before saving ---" -ForegroundColor DarkCyan

    # Build profile object
    $newProfile = [ordered]@{
        server   = $server
        port     = $port
        user     = $user
        password = $password
        database = $database
    }
    if ($sshBlock) { $newProfile.ssh = $sshBlock }

    # Test by saving to a temp config and running with -Profile
    $tempConfig = Join-Path $env:TEMP ("mysql-check-init-{0}.json" -f (Get-Random))
    $tmpCfg = [pscustomobject]@{ profiles = [pscustomobject]@{ $name = [pscustomobject]$newProfile } }
    ($tmpCfg | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $tempConfig -Encoding UTF8
    try {
        $script = Join-Path $PSScriptRoot 'Test-MysqlConnection.ps1'
        & $script -Config $tempConfig -Profile $name -LocalOnly:$false *>$null
        # Above just runs the local probe. Now full:
        $out = & $script -Config $tempConfig -Profile $name 2>&1
        $success = $LASTEXITCODE -eq 0
        if ($success) {
            Write-Host "  ✓ Connection OK" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Connection failed" -ForegroundColor Red
            $out | Select-Object -Last 15 | ForEach-Object { Write-Host "    $_" }
            Remove-Item $tempConfig -Force -ErrorAction SilentlyContinue
            $ans = Read-Host "  Save profile anyway? (y/N)"
            if ($ans -notmatch '^[Yy]') { return }
        }
    } finally {
        Remove-Item $tempConfig -Force -ErrorAction SilentlyContinue
    }

    # Persist
    if (-not $cfg) { $cfg = [pscustomobject]@{ profiles = [pscustomobject]@{} } }
    if (-not $cfg.profiles) { $cfg | Add-Member -NotePropertyName 'profiles' -NotePropertyValue ([pscustomobject]@{}) -Force }
    if ($cfg.profiles.PSObject.Properties.Name -contains $name) {
        $cfg.profiles.PSObject.Properties.Remove($name)
    }
    $cfg.profiles | Add-Member -NotePropertyName $name -NotePropertyValue ([pscustomobject]$newProfile) -Force

    $configDir = Split-Path -Parent $configPath
    if (-not (Test-Path -LiteralPath $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }
    ($cfg | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $configPath -Encoding UTF8

    Write-Host ""
    Write-Host "  ✓ Profile '$name' saved to $configPath" -ForegroundColor Green
    Test-ConfigPermissions $configPath
    Write-Host ""
    Write-Host "  Next:" -ForegroundColor Cyan
    Write-Host "    pwsh -File `"$PSCommandPath`" -Profile $name" -ForegroundColor White
    Write-Host "    pwsh -File `"$PSCommandPath`" -Profile $name -Query `"SELECT 1`"" -ForegroundColor White
}

if ($Init) {
    if (-not (Ensure-MySqlConnector)) {
        Write-Row 'FAIL' 'init' 'MySqlConnector.dll missing; re-install skill'
        exit 1
    }
    Invoke-Init
    exit 0
}

if ($ListProfiles) {
    Write-Host "Config: $configPath"
    if (-not $cfg -or -not $cfg.profiles) {
        Write-Host "  (no profiles defined)"
        exit 0
    }
    Write-Host ""
    $cfg.profiles.PSObject.Properties | ForEach-Object {
        Write-Host (Format-ProfileRow $_.Name $_.Value)
    }
    Test-ConfigPermissions $configPath
    exit 0
}

# --- 1. local probe --------------------------------------------------------

Write-Host "`n=== Local probe ===" -ForegroundColor Cyan

$svc = Get-Service -Name MySQL*, MariaDB* -ErrorAction SilentlyContinue |
       Where-Object { $_.Status -eq 'Running' } | Select-Object -First 1
if ($svc) {
    Write-Row 'OK' 'service' "$($svc.Name) running ($($svc.StartType) start)"
} else {
    Write-Row 'WARN' 'service' 'no running MySQL/MariaDB Windows service (remote tests still OK)'
}

$localPort = (Test-NetConnection -ComputerName localhost -Port 3306 -InformationLevel Quiet 2>$null)
if ($localPort) {
    Write-Row 'OK' 'tcp:3306' 'localhost accepting'
} else {
    Write-Row 'WARN' 'tcp:3306' 'localhost NOT accepting (may be remote-only)'
}

Write-Host "`n=== MySQL driver (bundled) ===" -ForegroundColor Cyan
if (-not (Ensure-MySqlConnector)) { exit 1 }
Write-Row 'OK' 'mysql-driver' "MySqlConnector loaded (no mysql.exe needed)"

if ($LocalOnly) {
    Write-Host "`n=== -LocalOnly set, stopping here ===" -ForegroundColor Cyan
    exit 0
}

# --- 2. resolve profile / merge --------------------------------------------

$Ssh = $null
if ($Profile) {
    if (-not $cfg -or -not $cfg.profiles -or -not $cfg.profiles.$Profile) {
        Write-Row 'FAIL' 'profile' "profile '$Profile' not found in $configPath (use -ListProfiles to see available)"
        exit 1
    }
    $p = $cfg.profiles.$Profile
    if (-not $Server)    { $Server    = $p.server }
    if (-not $Port)      { $Port      = if ($p.port) { [int]$p.port } else { 3306 } }
    if (-not $User)      { $User      = $p.user }
    if (-not $Password)  { $Password  = $p.password }
    if (-not $Database)  { $Database  = $p.database }
    if ($p.ssh)          { $Ssh       = $p.ssh }
    Write-Row 'OK' 'profile' "loaded '$Profile' from $configPath"
}

if ($env:MYSQL_CHECK_SSH_HOST) {
    if (-not $Ssh) { $Ssh = [pscustomobject]@{} }
    $Ssh | Add-Member -NotePropertyName 'host' -NotePropertyValue $env:MYSQL_CHECK_SSH_HOST -Force
}
if ($env:MYSQL_CHECK_SSH_PORT) {
    if (-not $Ssh) { $Ssh = [pscustomobject]@{} }
    $Ssh | Add-Member -NotePropertyName 'port' -NotePropertyValue ([int]$env:MYSQL_CHECK_SSH_PORT) -Force
}

# --- 3. validate inputs ----------------------------------------------------

if (-not $Server -or -not $User -or -not $Password) {
    Write-Row 'FAIL' 'inputs' '-Server, -User, -Password (or -Profile) are required (or use -LocalOnly)'
    exit 1
}
if (-not $Port) { $Port = 3306 }

# --- 4. SSH tunnel (if profile has ssh block) -------------------------------

$tunnel = $null
if ($Ssh) {
    Write-Host "`n=== SSH tunnel ===" -ForegroundColor Cyan
    $inUse = Get-NetTCPConnection -LocalPort $SshTunnelPort -State Listen -ErrorAction SilentlyContinue
    if ($inUse) {
        Write-Row 'FAIL' 'ssh-port' "local port $SshTunnelPort already in use; pass -SshTunnelPort <other>"
        exit 1
    }
    $tunnel = Start-SshTunnel -Ssh $Ssh -RemotePort $Port -LocalPort $SshTunnelPort -WaitSeconds $SshWaitSeconds
    $Server = '127.0.0.1'
    $Port   = $SshTunnelPort
}

# --- 5. remote probe + connection + execution -------------------------------

$csParts = @("Server=$Server", "Port=$Port", "User ID=$User", "Password=$Password")
if ($Database) { $csParts += "Database=$Database" }
$csParts += "SslMode=None"
$csParts += "ConnectionTimeout=10"
$csParts += "DefaultCommandTimeout=$QueryTimeoutSec"
$connStr = $csParts -join ";"

$conn = $null
try {
    Write-Host "`n=== Remote MySQL probe ===" -ForegroundColor Cyan
    $tcp = Test-NetConnection -ComputerName $Server -Port $Port -InformationLevel Quiet -WarningAction SilentlyContinue 2>$null
    if ($tcp) {
        Write-Row 'OK' "tcp:$Port" "$Server accepting"
    } else {
        Write-Row 'FAIL' "tcp:$Port" "$Server NOT accepting on $Port"
        exit 1
    }

    Write-Host "`n=== Connection test ===" -ForegroundColor Cyan
    $conn = Open-MySqlConnection $connStr
    Write-Row 'OK' 'auth' 'credential accepted (via MySqlConnector)'

    $probeSql = "SELECT VERSION() AS version, NOW() AS server_time, USER() AS connected_as, @@hostname AS hostname, @@character_set_database AS charset;"
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $probeSql
    $reader = $cmd.ExecuteReader()
    $reader.Read() | Out-Null
    Write-Host ("    version       = {0}" -f $reader['version'])
    Write-Host ("    server_time   = {0}" -f $reader['server_time'])
    Write-Host ("    connected_as  = {0}" -f $reader['connected_as'])
    Write-Host ("    hostname      = {0}" -f $reader['hostname'])
    Write-Host ("    charset       = {0}" -f $reader['charset'])
    $reader.Close()

    if ($Database) {
        Write-Host "`n=== Database: $Database ===" -ForegroundColor Cyan
        $cmd2 = $conn.CreateCommand()
        $cmd2.CommandText = "SHOW TABLES"
        $reader2 = $cmd2.ExecuteReader()
        $tableCount = 0
        $tableNames = New-Object System.Collections.Generic.List[string]
        while ($reader2.Read()) {
            $tableCount++
            $tableNames.Add(($reader2.GetValue(0).ToString()))
        }
        $reader2.Close()
        Write-Row 'OK' 'database' "$Database accessible, $tableCount table(s)"
        foreach ($t in $tableNames) { Write-Host ('    - ' + $t) }
    }

    $userSql = $null
    if ($Query -and $QueryFile) {
        Write-Row 'FAIL' 'inputs' '-Query and -QueryFile are mutually exclusive'
        exit 1
    } elseif ($Query) {
        $userSql = $Query
    } elseif ($QueryFile) {
        if (-not (Test-Path -LiteralPath $QueryFile)) {
            Write-Row 'FAIL' 'queryfile' "not found: $QueryFile"
            exit 1
        }
        $userSql = Get-Content -LiteralPath $QueryFile -Raw -Encoding UTF8
    }

    if ($userSql) {
        Write-Host "`n=== User query ===" -ForegroundColor Cyan
        $statements = Split-SqlStatements $userSql
        Write-Host ("  {0} statement(s) parsed" -f $statements.Count)
        $anyWrite = $false
        foreach ($s in $statements) {
            if (Test-IsWriteQuery $s) { $anyWrite = $true; break }
        }
        if ($anyWrite -and -not $AllowWrite) {
            Write-Row 'FAIL' 'safety' "query contains write-like statement; refusing. Pass -AllowWrite to opt in."
            Write-Host ""
            Write-Host "  Detected: INSERT/UPDATE/DELETE/REPLACE/CREATE/DROP/ALTER/TRUNCATE/RENAME" -ForegroundColor Yellow
            Write-Host "            /GRANT/REVOKE/SET/CALL/LOAD DATA/LOCK/UNLOCK/FLUSH/KILL/SHUTDOWN"
            exit 1
        }
        if ($anyWrite) {
            Write-Row 'WARN' 'safety' "write-like statements detected; -AllowWrite supplied, executing"
        }
        $stmtIndex = 0
        foreach ($s in $statements) {
            $stmtIndex++
            $firstLine = ($s -split "`n")[0].Trim()
            if ($firstLine.Length -gt 100) { $firstLine = $firstLine.Substring(0, 97) + '...' }
            Write-Host ""
            Write-Host ("--- statement {0}/{1} ---" -f $stmtIndex, $statements.Count) -ForegroundColor DarkCyan
            Write-Host ("  $firstLine") -ForegroundColor Gray

            $cmd3 = $conn.CreateCommand()
            $cmd3.CommandText = $s
            $cmd3.CommandTimeout = $QueryTimeoutSec
            $isWrite = Test-IsWriteQuery $s
            try {
                if ($isWrite) {
                    $rowsAffected = $cmd3.ExecuteNonQuery()
                    Write-Host ("  -> {0} row(s) affected" -f $rowsAffected) -ForegroundColor Green
                } else {
                    $reader3 = $cmd3.ExecuteReader()
                    Write-ResultSet -Reader $reader3 -Format $ResultFormat
                }
            } catch {
                Write-Row 'FAIL' 'query' $_.Exception.Message
                exit 1
            }
        }
    }
}
finally {
    if ($conn -and $conn.State -eq 'Open') {
        try { $conn.Close() } catch { }
    }
    if ($tunnel) {
        Stop-SshTunnel $tunnel
        Write-Row 'OK' 'ssh-tunnel' "torn down (127.0.0.1:$SshTunnelPort released)"
    }
}

# --- 9. save profile (optional) --------------------------------------------

if ($SaveProfile) {
    if (-not $cfg) { $cfg = [pscustomobject]@{ profiles = [pscustomobject]@{} } }
    if (-not $cfg.profiles) { $cfg | Add-Member -NotePropertyName 'profiles' -NotePropertyValue ([pscustomobject]@{}) -Force }
    $newProfile = [ordered]@{
        server   = $Server
        port     = $Port
        user     = $User
        password = $Password
        database = $Database
    }
    if ($cfg.profiles.PSObject.Properties.Name -contains $SaveProfile) {
        $cfg.profiles.PSObject.Properties.Remove($SaveProfile)
    }
    $cfg.profiles | Add-Member -NotePropertyName $SaveProfile -NotePropertyValue ([pscustomobject]$newProfile) -Force

    $configDir = Split-Path -Parent $configPath
    if (-not (Test-Path -LiteralPath $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }
    ($cfg | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $configPath -Encoding UTF8
    Write-Row 'OK' 'save' "profile '$SaveProfile' written to $configPath"
    Test-ConfigPermissions $configPath
}

# --- 10. summary -----------------------------------------------------------

Write-Host "`n=== Result ===" -ForegroundColor Cyan
Write-Row 'OK' 'CONNECTED' "${User}@${Server}:${Port}"
exit 0
