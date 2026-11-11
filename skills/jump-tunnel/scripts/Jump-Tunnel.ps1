#!/usr/bin/env pwsh
#Requires -Version 7.2
<#
.SYNOPSIS
    Jump Tunnel - forward (-L) and reverse (-R) SSH tunnels via bastion

.DESCRIPTION
    forward: local port -> bastion -> intranet TCP
    reverse: share this PC VPN reachability onto any intranet host

.PARAMETER Action
    start | stop | test | status | help

.PARAMETER Config
    Config JSON path

.PARAMETER Tunnel
    Optional tunnels[].name filter. Accepts a comma-separated list to select
    several tunnels at once (e.g. -Tunnel db-main,inner-ssh). Empty = all.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('start', 'stop', 'test', 'status', 'help')]
    [string]$Action = 'help',

    [string]$Config = '',

    [string]$Tunnel = ''
)

$ErrorActionPreference = 'Stop'
$script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:RootDir = Split-Path -Parent $script:ScriptDir
$script:DefaultConfig = Join-Path $script:RootDir 'config\jump-tunnel.config.json'
$script:RuntimeDir = Join-Path $env:USERPROFILE '.jump-tunnel-runtime'

function Find-Ssh {
    $candidates = @()
    if ($env:SSH_PATH) { $candidates += $env:SSH_PATH }
    $candidates += Join-Path $env:WINDIR 'System32\OpenSSH\ssh.exe'
    foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { return $c } }
    foreach ($dir in ($env:PATH -split ';')) {
        if ($dir) {
            $c = Join-Path $dir 'ssh.exe'
            if (Test-Path -LiteralPath $c) { return $c }
        }
    }
    return ''
}

function Read-Config([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Config not found: $path" }
    return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

# Bastion resolution.
# Config format:
#   "bastion": "qin"                     -> name of the default bastion
#   "bastions": { "qin": {...}, "bk": {...} }
#   each tunnel may set "bastion": "bk"   -> per-tunnel bastion override
# Legacy single-bastion format ("bastion": { host, port, user, password })
# is still accepted and treated as one bastion named "default".
function Initialize-Bastions($config) {
    $map = @{}
    $default = $null

    $legacy = $config.bastion
    $hasLegacy = $false
    if ($legacy -and $legacy.PSObject.Properties['host']) { $hasLegacy = $true }

    if ($config.bastions) {
        foreach ($p in $config.bastions.PSObject.Properties) {
            $map[$p.Name] = $p.Value
        }
        if ($legacy -and -not $hasLegacy) { $default = [string]$legacy }
        if (-not $default) { $default = @($map.Keys)[0] }
    }
    elseif ($hasLegacy) {
        $map['default'] = $legacy
        $default = 'default'
    }

    if ($map.Count -eq 0) { throw 'no bastion defined in config' }
    if (-not $default -or -not $map.ContainsKey($default)) { throw "default bastion not found: $default" }

    $script:Bastions = $map
    $script:DefaultBastion = $default
}

# Returns @{ Name = <name>; Cfg = <bastion object> }
function Get-Bastion($config, $tunnel) {
    $name = $null
    if ($tunnel -and $tunnel.bastion) { $name = [string]$tunnel.bastion }
    if (-not $name) { $name = $script:DefaultBastion }
    if (-not $script:Bastions.ContainsKey($name)) { throw "bastion not found: $name" }
    return @{ Name = $name; Cfg = $script:Bastions[$name] }
}

function Get-TunnelMode($t) {
    $m = [string]$t.mode
    if (-not $m) { return 'forward' }
    $m = $m.ToLowerInvariant()
    if ($m -ne 'forward' -and $m -ne 'reverse') { throw "Tunnel [$($t.name)] invalid mode: $m" }
    return $m
}

function Get-TunnelPid([string]$name) {
    $pidFile = Join-Path $script:RuntimeDir ($name + '.pid')
    if (-not (Test-Path -LiteralPath $pidFile)) { return $null }
    $raw = (Get-Content -LiteralPath $pidFile -Raw).Trim()
    if (-not $raw) { return $null }
    return [int]$raw
}

function Test-TcpPort([string]$hostName, [int]$port, [int]$timeoutMs = 3000) {
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $task = $client.ConnectAsync($hostName, $port)
        if (-not $task.Wait($timeoutMs)) { return $false }
        if ($task.IsFaulted) { return $false }
        return $client.Connected
    } catch { return $false }
    finally { $client.Dispose() }
}

function Wait-PortUp([string]$hostName, [int]$port, [int]$timeoutSec = 20) {
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    do {
        if (Test-TcpPort $hostName $port 1500) { return $true }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Get-SshPidByLocalBind([string]$hostName, [int]$port) {
    $needle = "$hostName`:$port`:"
    try {
        $hit = Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -and ($_.CommandLine -replace '\s+', ' ').Contains($needle) } |
            Select-Object -First 1
        if ($hit) { return [int]$hit.ProcessId }
    } catch { }
    return $null
}

# Returns the recorded pid only if that pid still belongs to ssh.exe.
# Guards against PID recycling: a stale pid file may point at an unrelated process.
function Get-RecordedSshPid([string]$name) {
    $pidVal = Get-TunnelPid $name
    if (-not $pidVal) { return $null }
    $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$pidVal" -ErrorAction SilentlyContinue
    if ($proc -and $proc.Name -eq 'ssh.exe') { return $pidVal }
    return $null
}

# Turns the -Tunnel filter into a lookup set of tunnel names.
# Empty input means "all tunnels", which is represented by $null.
# Accepts a comma-separated list: -Tunnel a,b,c
function Resolve-TunnelFilter([string]$filter) {
    if ([string]::IsNullOrWhiteSpace($filter)) { return $null }
    $set = @{}
    foreach ($part in ($filter -split ',')) {
        $name = $part.Trim()
        if ($name) { $set[$name] = $true }
    }
    if ($set.Count -eq 0) { return $null }
    return $set
}

# True when the tunnel should be processed for the current filter.
function Test-TunnelSelected($t, $filterSet) {
    if (-not $filterSet) { return $true }
    return $filterSet.ContainsKey([string]$t.name)
}

# Reports filter names that match no tunnel, so a typo in a multi-select
# is visible instead of silently starting a smaller set than intended.
function Assert-TunnelFilterExists($config, $filterSet) {
    if (-not $filterSet) { return }
    $unknown = @()
    foreach ($name in $filterSet.Keys) {
        $hit = $config.tunnels | Where-Object { $_.name -eq $name } | Select-Object -First 1
        if (-not $hit) { $unknown += $name }
    }
    if ($unknown.Count -gt 0) { throw "tunnel not found: $($unknown -join ', ')" }
}

function Save-PidOnly([string]$name, [int]$pidVal) {
    Set-Content -LiteralPath (Join-Path $script:RuntimeDir ($name + '.pid')) -Value $pidVal -Encoding ascii
}

function Write-AskpassFile([string]$password) {
    $escaped = $password -replace '%', '%%'
    $askFile = Join-Path $script:RuntimeDir ('jump_askpass_' + [Guid]::NewGuid().ToString('N') + '.cmd')
    Set-Content -LiteralPath $askFile -Value "@echo off`r`necho $escaped`r`n" -Encoding ascii -NoNewline
    return $askFile
}

function Save-ProcMeta([string]$name, $proc, [string]$askFile) {
    Set-Content -LiteralPath (Join-Path $script:RuntimeDir ($name + '.pid')) -Value $proc.Id -Encoding ascii
    Set-Content -LiteralPath (Join-Path $script:RuntimeDir ($name + '.askpass')) -Value $askFile -Encoding ascii
}

function Start-SshProcess([string]$ssh, [string[]]$sshArgs, [string]$password) {
    $askFile = Write-AskpassFile $password
    $env:DISPLAY = 'localhost:0'
    $env:SSH_ASKPASS = $askFile
    $env:SSH_ASKPASS_REQUIRE = 'force'
    $proc = Start-Process -FilePath $ssh -ArgumentList $sshArgs -WindowStyle Hidden -PassThru
    return @{ Proc = $proc; AskFile = $askFile }
}

function Get-BridgeName([string]$tunnelName) { return "__bridge_$tunnelName" }

function Resolve-ReverseBridge($config, $t) {
    if ($t.via) {
        $viaName = [string]$t.via
        $fwd = $config.tunnels | Where-Object { $_.name -eq $viaName } | Select-Object -First 1
        if (-not $fwd) { throw "Tunnel [$($t.name)] via=$viaName not found" }
        if ((Get-TunnelMode $fwd) -ne 'forward') { throw "via must be a forward tunnel: $viaName" }
        if (-not ($t.server -and $t.server.password)) { throw "reverse [$($t.name)] needs server.password" }
        $defaultCfg = $script:Bastions[$script:DefaultBastion]
        $user = if ($t.server.user) { [string]$t.server.user } else { [string]$defaultCfg.user }
        return @{
            Host = [string]$fwd.local.host
            Port = [int]$fwd.local.port
            User = $user
            Password = [string]$t.server.password
            EnsureForwardName = $viaName
            AutoBridge = $null
            BastionName = $null
        }
    }
    if (-not $t.server -or -not $t.server.host) {
        throw "reverse [$($t.name)] needs server.host (any intranet host) or via"
    }
    if (-not $t.server.password) { throw "reverse [$($t.name)] needs server.password" }
    $bridgePort = if ($t.server.bridgePort) { [int]$t.server.bridgePort } elseif ($t.bridge -and $t.bridge.port) { [int]$t.bridge.port } else { 23000 + ([Math]::Abs($t.name.GetHashCode()) % 1000) }
    $bridgeHost = if ($t.bridge -and $t.bridge.host) { [string]$t.bridge.host } else { '127.0.0.1' }
    $defaultCfg = $script:Bastions[$script:DefaultBastion]
    $user = if ($t.server.user) { [string]$t.server.user } else { [string]$defaultCfg.user }
    $serverPort = if ($t.server.port) { [int]$t.server.port } else { 22 }
    # The bridge forward reaches the intranet host through the same bastion the
    # tunnel declares (or the default one).
    $bastion = Get-Bastion $config $t
    return @{
        Host = $bridgeHost
        Port = $bridgePort
        User = $user
        Password = [string]$t.server.password
        EnsureForwardName = $null
        AutoBridge = @{
            Name = (Get-BridgeName $t.name)
            LocalHost = $bridgeHost
            LocalPort = $bridgePort
            RemoteHost = [string]$t.server.host
            RemotePort = $serverPort
            BastionName = $bastion.Name
        }
        BastionName = $bastion.Name
    }
}

function Start-OneForward($config, $t, [string]$ssh) {
    $bastion = Get-Bastion $config $t
    $b = $bastion.Cfg
    $localBind = "$($t.local.host):$($t.local.port)"
    $remoteTarget = "$($t.remote.host):$($t.remote.port)"
    $sshArgs = @(
        '-o', 'StrictHostKeyChecking=accept-new',
        '-o', 'ConnectTimeout=15',
        '-o', 'ServerAliveInterval=60',
        '-o', 'ServerAliveCountMax=3',
        '-N',
        '-L', "${localBind}:${remoteTarget}",
        ('{0}@{1}' -f $b.user, $b.host),
        '-p', ([string]$b.port)
    )
    Write-Host "Start forward [$($t.name)]: $localBind -> $remoteTarget via [$($bastion.Name)] $($b.user)@$($b.host):$($b.port)"
    $started = Start-SshProcess $ssh $sshArgs ([string]$b.password)
    Save-ProcMeta $t.name $started.Proc $started.AskFile
}

function Ensure-ForwardRunning($config, [string]$name, [string]$ssh) {
    $t = $config.tunnels | Where-Object { $_.name -eq $name } | Select-Object -First 1
    if (-not $t) { throw "forward not found: $name" }
    $lh = [string]$t.local.host
    $lp = [int]$t.local.port

    if (Test-TcpPort $lh $lp) {
        # Healthy listener: only refresh the pid record if it is stale.
        if (-not (Get-RecordedSshPid $name)) {
            $realPid = Get-SshPidByLocalBind $lh $lp
            if ($realPid) { Save-PidOnly $name $realPid }
        }
        return
    }

    # Port not up. If a live ssh is recorded, give it time to finish forwarding
    # before concluding it is dead - starting a second ssh on the same port
    # would only fail to bind and clobber the pid record.
    $livePid = Get-RecordedSshPid $name
    if ($livePid) {
        if (Wait-PortUp $lh $lp 20) { return }
        Write-Host "[stale] ${name}: pid=$livePid alive but port $lp never came up, restarting"
        Stop-Process -Id $livePid -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath (Join-Path $script:RuntimeDir ($name + '.pid')) -Force -ErrorAction SilentlyContinue
    Start-OneForward $config $t $ssh
    if (-not (Wait-PortUp $lh $lp 20)) { throw "failed to bring up forward: $name" }
}

function Start-AutoBridge($config, $bridge, [string]$ssh) {
    $name = $bridge.Name
    $existing = Get-RecordedSshPid $name
    if ($existing -and (Test-TcpPort $bridge.LocalHost ([int]$bridge.LocalPort))) {
        Write-Host "[exists] bridge $name (pid=$existing)"
        return
    }
    Remove-Item -LiteralPath (Join-Path $script:RuntimeDir ($name + '.pid')) -Force -ErrorAction SilentlyContinue
    $bastionName = if ($bridge.BastionName) { [string]$bridge.BastionName } else { $script:DefaultBastion }
    $bastion = $script:Bastions[$bastionName]
    $localBind = "$($bridge.LocalHost):$($bridge.LocalPort)"
    $remoteTarget = "$($bridge.RemoteHost):$($bridge.RemotePort)"
    $sshArgs = @(
        '-o', 'StrictHostKeyChecking=accept-new',
        '-o', 'ConnectTimeout=15',
        '-o', 'ServerAliveInterval=60',
        '-o', 'ServerAliveCountMax=3',
        '-N',
        '-L', "${localBind}:${remoteTarget}",
        ('{0}@{1}' -f $bastion.user, $bastion.host),
        '-p', ([string]$bastion.port)
    )
    Write-Host "Start bridge [$name]: $localBind -> $remoteTarget via [$bastionName] $($bastion.user)@$($bastion.host):$($bastion.port)"
    $started = Start-SshProcess $ssh $sshArgs ([string]$bastion.password)
    Save-ProcMeta $name $started.Proc $started.AskFile
    if (-not (Wait-PortUp $bridge.LocalHost ([int]$bridge.LocalPort) 20)) { throw "bridge port not ready: $localBind" }
}

function Start-OneReverse($config, $t, [string]$ssh) {
    if (-not $t.listen -or -not $t.target) { throw "reverse [$($t.name)] needs listen and target" }
    $bridge = Resolve-ReverseBridge $config $t
    if ($bridge.EnsureForwardName) { Ensure-ForwardRunning $config $bridge.EnsureForwardName $ssh }
    elseif ($bridge.AutoBridge) { Start-AutoBridge $config $bridge.AutoBridge $ssh }

    $listen = "$($t.listen.host):$($t.listen.port)"
    $target = "$($t.target.host):$($t.target.port)"
    $sshArgs = @(
        '-o', 'StrictHostKeyChecking=accept-new',
        '-o', 'ConnectTimeout=15',
        # Tighter keepalive: a reverse tunnel whose remote session dies while the
        # client lingers looks healthy to a process-only check, so notice sooner.
        '-o', 'ServerAliveInterval=15',
        '-o', 'ServerAliveCountMax=3',
        # Fail loudly if the remote port cannot be bound, instead of staying
        # connected with no listener (the silent-failure mode).
        '-o', 'ExitOnForwardFailure=yes',
        '-N',
        '-R', "${listen}:${target}",
        ('{0}@{1}' -f $bridge.User, $bridge.Host),
        '-p', ([string]$bridge.Port)
    )
    Write-Host "Start reverse [$($t.name)]: intranet $listen <-R- thisPC(VPN) -> $target (ssh $($bridge.User)@$($bridge.Host):$($bridge.Port))"
    $started = Start-SshProcess $ssh $sshArgs ([string]$bridge.Password)
    Save-ProcMeta $t.name $started.Proc $started.AskFile
}

# Askpass files hold the password in cleartext and are only removed on stop, so
# an interrupted or repeated start leaves them behind. Drop the ones no live
# tunnel still references.
function Remove-OrphanAskpass {
    $inUse = @{}
    Get-ChildItem -LiteralPath $script:RuntimeDir -Filter '*.askpass' -ErrorAction SilentlyContinue | ForEach-Object {
        $ref = (Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue)
        if ($ref) { $inUse[$ref.Trim()] = $true }
    }
    Get-ChildItem -LiteralPath $script:RuntimeDir -Filter 'jump_askpass_*.cmd' -ErrorAction SilentlyContinue | ForEach-Object {
        if (-not $inUse.ContainsKey($_.FullName)) {
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
        }
    }
}

function Start-Tunnels($config, $filterSet) {
    $ssh = Find-Ssh
    if (-not $ssh) { throw 'ssh.exe not found' }
    $needsPassword = $false
    foreach ($t in $config.tunnels) {
        if (-not (Test-TunnelSelected $t $filterSet)) { continue }
        $bastion = Get-Bastion $config $t
        if (-not $bastion.Cfg.password) { $needsPassword = $true; break }
    }
    if ($needsPassword) { throw 'bastion password missing' }
    New-Item -ItemType Directory -Force -Path $script:RuntimeDir | Out-Null
    Remove-OrphanAskpass
    $started = 0
    foreach ($t in $config.tunnels) {
        if (-not (Test-TunnelSelected $t $filterSet)) { continue }
        if ((Get-TunnelMode $t) -ne 'forward') { continue }
        $lh = [string]$t.local.host
        $lp = [int]$t.local.port
        if (Test-TcpPort $lh $lp) {
            # Already forwarding. Refresh a stale pid record, then leave it alone:
            # the listening port - not the pid file - is the source of truth.
            if (-not (Get-RecordedSshPid $t.name)) {
                $realPid = Get-SshPidByLocalBind $lh $lp
                if ($realPid) { Save-PidOnly $t.name $realPid }
            }
            Write-Host "[exists] $($t.name) already forwarding on ${lh}:${lp}"
            continue
        }
        $livePid = Get-RecordedSshPid $t.name
        if ($livePid) {
            if (Wait-PortUp $lh $lp 20) { continue }
            Write-Host "[stale] $($t.name): pid=$livePid alive but port $lp never came up, restarting"
            Stop-Process -Id $livePid -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath (Join-Path $script:RuntimeDir ($t.name + '.pid')) -Force -ErrorAction SilentlyContinue
        Start-OneForward $config $t $ssh
        # Wait for the port before moving on, so a later Ensure-ForwardRunning
        # (reverse tunnels that depend on this forward) does not start a duplicate.
        if (-not (Wait-PortUp $lh $lp 20)) { Write-Host "[warn] $($t.name): port $lp not up yet" }
        $started++
    }
    foreach ($t in $config.tunnels) {
        if (-not (Test-TunnelSelected $t $filterSet)) { continue }
        if ((Get-TunnelMode $t) -ne 'reverse') { continue }
        $existing = Get-RecordedSshPid $t.name
        if ($existing) {
            Write-Host "[exists] $($t.name) (pid=$existing)"; continue
        }
        Remove-Item -LiteralPath (Join-Path $script:RuntimeDir ($t.name + '.pid')) -Force -ErrorAction SilentlyContinue
        Start-OneReverse $config $t $ssh
        Start-Sleep -Seconds 3
        $started++
    }
    if ($started -gt 0) {
        Write-Host ''
        Write-Host 'Started. Waiting 3s then probing...'
        Start-Sleep -Seconds 3
    }
    [void](Test-Tunnels $config $filterSet)
}

function Invoke-RemoteListenCheck($bridgeHost, [int]$bridgePort, [string]$user, [string]$password, $listenHost, [int]$listenPort) {
    $ssh = Find-Ssh
    $askFile = Write-AskpassFile $password
    $env:DISPLAY = 'localhost:0'
    $env:SSH_ASKPASS = $askFile
    $env:SSH_ASKPASS_REQUIRE = 'force'
    $py = "import socket;s=socket.create_connection(('$listenHost',$listenPort),3);s.close();print('TCP_OK')"
    $remoteCmd = "python3 -c `"$py`" 2>/dev/null || (echo >/dev/tcp/$listenHost/$listenPort && echo TCP_OK)"
    $sshArgs = @(
        '-o', 'StrictHostKeyChecking=accept-new',
        '-o', 'ConnectTimeout=15',
        '-p', ([string]$bridgePort),
        ('{0}@{1}' -f $user, $bridgeHost),
        $remoteCmd
    )
    try {
        $out = & $ssh @sshArgs 2>&1 | Out-String
        return ($out -match 'TCP_OK')
    } catch { return $false }
    finally { Remove-Item -LiteralPath $askFile -Force -ErrorAction SilentlyContinue }
}

function Test-Tunnels {
    param($config, $filterSet)
    $allOk = $true
    foreach ($t in $config.tunnels) {
        if (-not (Test-TunnelSelected $t $filterSet)) { continue }
        $mode = Get-TunnelMode $t
        if ($mode -eq 'forward') {
            $ok = Test-TcpPort $t.local.host ([int]$t.local.port)
            $mark = if ($ok) { 'OK  ' } else { 'FAIL' }
            Write-Host "[$mark] forward $($t.name): $($t.local.host):$($t.local.port) -> $($t.remote.host):$($t.remote.port)"
            if (-not $ok) { $allOk = $false }
        } else {
            $pidVal = Get-TunnelPid $t.name
            $procAlive = $pidVal -and (Get-Process -Id $pidVal -ErrorAction SilentlyContinue)
            $remoteOk = $false
            if ($procAlive) {
                try {
                    $b = Resolve-ReverseBridge $config $t
                    $remoteOk = Invoke-RemoteListenCheck $b.Host ([int]$b.Port) $b.User $b.Password $t.listen.host ([int]$t.listen.port)
                } catch { $remoteOk = $false }
            }
            $mark = if ($procAlive -and $remoteOk) { 'OK  ' } elseif ($procAlive) { 'PROC' } else { 'FAIL' }
            Write-Host "[$mark] reverse $($t.name): intranet $($t.listen.host):$($t.listen.port) -> VPN $($t.target.host):$($t.target.port)"
            if (-not ($procAlive -and $remoteOk)) { $allOk = $false }
        }
    }
    return $allOk
}

function Get-TunnelStatus {
    param($config, $filterSet)
    foreach ($t in $config.tunnels) {
        if (-not (Test-TunnelSelected $t $filterSet)) { continue }
        $mode = Get-TunnelMode $t
        $pidVal = Get-TunnelPid $t.name
        $procAlive = $false
        if ($pidVal) { $procAlive = [bool](Get-Process -Id $pidVal -ErrorAction SilentlyContinue) }
        if ($mode -eq 'forward') {
            $portUp = Test-TcpPort $t.local.host ([int]$t.local.port)
            $state = if ($procAlive -and $portUp) { 'RUNNING' } elseif ($portUp) { 'PORT-UP' } else { 'DOWN' }
            $pidStr = if ($pidVal) { "pid=$pidVal" } else { 'pid=-' }
            $bName = (Get-Bastion $config $t).Name
            Write-Host ("{0,-22} {1,-8} {2,-8} {3,-10} {4,-9} {5}:{6,-5} -> {7}:{8}" -f $t.name, 'forward', $state, $pidStr, $bName, $t.local.host, $t.local.port, $t.remote.host, $t.remote.port)
        } else {
            # Process liveness alone is misleading here: a reverse tunnel whose
            # remote session dropped stays "alive" locally with no listener.
            $remoteOk = $false
            if ($procAlive) {
                try {
                    $b = Resolve-ReverseBridge $config $t
                    $remoteOk = Invoke-RemoteListenCheck $b.Host ([int]$b.Port) $b.User $b.Password $t.listen.host ([int]$t.listen.port)
                } catch { $remoteOk = $false }
            }
            $state = if (-not $procAlive) { 'DOWN' } elseif ($remoteOk) { 'RUNNING' } else { 'NO-LISTEN' }
            $pidStr = if ($pidVal) { "pid=$pidVal" } else { 'pid=-' }
            $bName = if ($t.bastion) { [string]$t.bastion } else { $script:DefaultBastion }
            Write-Host ("{0,-22} {1,-8} {2,-9} {3,-10} {4,-9} listen {5}:{6} target {7}:{8}" -f $t.name, 'reverse', $state, $pidStr, $bName, $t.listen.host, $t.listen.port, $t.target.host, $t.target.port)
        }
    }
    $reverses = @($config.tunnels | Where-Object { (Get-TunnelMode $_) -eq 'reverse' })
    if ($reverses.Count -gt 0) {
        Write-Host ''
        Write-Host 'On the intranet host, run:'
        foreach ($r in $reverses) {
            # TLS is the norm for these intranet apps, and the port alone does not
            # tell us (they serve TLS on 50000). Override with "scheme" in config.
            $scheme = if ($r.scheme) { [string]$r.scheme } else { 'https' }
            $port = [int]$r.listen.port
            Write-Host ("  curl -k -H 'Host: {0}' --resolve {0}:{1}:127.0.0.1 {2}://{0}:{1}/<path>" -f $r.target.host, $port, $scheme)
        }
    }
}

function Stop-OneByName([string]$name) {
    $pidVal = Get-TunnelPid $name
    if ($pidVal) {
        $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$pidVal" -ErrorAction SilentlyContinue
        if ($proc -and $proc.Name -eq 'ssh.exe') {
            Stop-Process -Id $pidVal -Force -ErrorAction SilentlyContinue
            Write-Host "Stopped : $name (pid=$pidVal)"
        }
        elseif ($proc) {
            # PID was recycled by an unrelated process (can happen after reboot).
            # Never kill it - only drop the stale record.
            Write-Host "Skip    : $name (pid=$pidVal is $($proc.Name), not ssh - stale record dropped)"
        }
        else { Write-Host "Gone    : $name (cleanup pid)" }
        Remove-Item -LiteralPath (Join-Path $script:RuntimeDir ($name + '.pid')) -ErrorAction SilentlyContinue
    } else { Write-Host "No record: $name" }
    $askFileRef = Join-Path $script:RuntimeDir ($name + '.askpass')
    if (Test-Path -LiteralPath $askFileRef) {
        $askF = (Get-Content -LiteralPath $askFileRef -Raw -ErrorAction SilentlyContinue)
        if ($askF) {
            $askF = $askF.Trim()
            if ($askF -and (Test-Path -LiteralPath $askF)) { Remove-Item -LiteralPath $askF -Force -ErrorAction SilentlyContinue }
        }
        Remove-Item -LiteralPath $askFileRef -Force -ErrorAction SilentlyContinue
    }
}

function Stop-Tunnels {
    param($config, $filterSet)
    foreach ($t in $config.tunnels) {
        if (-not (Test-TunnelSelected $t $filterSet)) { continue }
        Stop-OneByName $t.name
        if ((Get-TunnelMode $t) -eq 'reverse' -and -not $t.via) { Stop-OneByName (Get-BridgeName $t.name) }
    }
    if (-not $filterSet) {
        Get-ChildItem -LiteralPath $script:RuntimeDir -Filter '__bridge_*.pid' -ErrorAction SilentlyContinue | ForEach-Object { Stop-OneByName $_.BaseName }
    }
}

$configPath = if ($Config) { $Config } else { $script:DefaultConfig }
if ($Action -eq 'help') { Get-Help $MyInvocation.MyCommand.Path -Detailed; exit 0 }

try {
    $cfg = Read-Config $configPath
    Initialize-Bastions $cfg
    if (-not $cfg.tunnels -or $cfg.tunnels.Count -eq 0) { Write-Error 'No tunnels in config'; exit 1 }
    $filterSet = Resolve-TunnelFilter $Tunnel
    Assert-TunnelFilterExists $cfg $filterSet
    switch ($Action) {
        'start'  { Start-Tunnels $cfg $filterSet }
        'stop'   { Stop-Tunnels $cfg $filterSet }
        'test'   { if (-not (Test-Tunnels $cfg $filterSet)) { exit 1 } }
        'status' { Get-TunnelStatus $cfg $filterSet }
    }
} catch {
    Write-Error $_.Exception.Message
    exit 1
}
