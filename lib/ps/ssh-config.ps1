# lib/ps/ssh-config.ps1 — SSH config parsing helpers
# EXPORTS: Get-AvailableSSHKeys  Get-HostsUsingKey  Get-ConfiguredSSHHosts
#          Get-IdentityFilesForHost  Get-IdentityFileFromHostConfigEntry
#          Find-ConfigFileOnHost  Find-SSHKeyInHostConfig
#          Find-PrivateKeyInHost  Find-PublicKeyInHost
#          Get-IPAddressFromHostConfigEntry  Get-AliasForHostIP
#          Get-RemoteUserFromConfigEntry

function Get-AvailableSSHKeys {
    $sshDir  = "$env:USERPROFILE\.ssh"
    if (-not (Test-Path $sshDir)) { return @() }
    $exclude = @("config","known_hosts","known_hosts.old","authorized_keys","authorized_keys2","environment","rc")
    return @(Get-ChildItem -Path $sshDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -ine ".pub" -and $exclude -notcontains $_.Name.ToLowerInvariant() } |
        Select-Object -ExpandProperty Name | Sort-Object)
}


function Get-HostsUsingKey {
    # Returns configured SSH hosts whose config block references $KeyName as an IdentityFile.
    param([string]$KeyName)
    $configPath = "$env:USERPROFILE\.ssh\config"
    if (-not (Test-Path $configPath)) { return @() }
    $config  = Get-Content $configPath -Raw -Encoding UTF8
    $escaped = [regex]::Escape($KeyName)
    return @(Get-ConfiguredSSHHosts | Where-Object {
        $hostEsc = [regex]::Escape($_.Alias)
        $block   = [regex]::Match($config, "(?ms)^Host\s+$hostEsc\b.*?(?=^Host\s|\z)").Value
        $block -match "(?m)^\s*IdentityFile\s+.*[\\/]$escaped\s*$"
    })
}


function Get-ConfiguredSSHHosts {
    $configPath = "$env:USERPROFILE\.ssh\config"
    if (-not (Test-Path $configPath)) { return @() }
    $config  = Get-Content $configPath -Raw -Encoding UTF8
    $hosts   = @()
    $pattern = "(?ms)^Host\s+(\S+).*?(?=^Host\s|\z)"
    foreach ($hb in [regex]::Matches($config, $pattern)) {
        $alias = $hb.Groups[1].Value.Trim()
        if ($alias -eq "*") { continue }
        $hn = if ($hb.Value -match '(?m)^\s*HostName\s+(\S+)') { $Matches[1] } else { "" }
        $u  = if ($hb.Value -match '(?m)^\s*User\s+(\S+)')     { $Matches[1] } else { "" }
        $hosts += [pscustomobject]@{ Alias = $alias; HostName = $hn; User = $u }
    }
    return $hosts
}


function Get-IdentityFilesForHost {
    # Returns IdentityFile paths for a given alias or IP address from ~/.ssh/config.
    # Tries alias match first, then falls back to matching by HostName value.
    param([string]$AliasOrAddress)
    $cfgPath = "$env:USERPROFILE\.ssh\config"
    if (-not $AliasOrAddress -or -not (Test-Path $cfgPath)) { return @() }
    $cfgRaw = Get-Content $cfgPath -Raw -Encoding UTF8
    $aliasE = [regex]::Escape($AliasOrAddress)
    $block  = [regex]::Match($cfgRaw, "(?ms)^Host\s+$aliasE\b.*?(?=^Host\s|\z)").Value
    if (-not $block) {
        foreach ($hb in [regex]::Matches($cfgRaw, "(?ms)^Host\s+(\S+).*?(?=^Host\s|\z)")) {
            if ($hb.Value -match "(?m)^\s*HostName\s+$([regex]::Escape($AliasOrAddress))\s*$") {
                $block = $hb.Value; break
            }
        }
    }
    if (-not $block) { return @() }
    return @([regex]::Matches($block, '(?m)^\s*IdentityFile\s+(.+?)\s*$') |
             ForEach-Object { $_.Groups[1].Value.Trim().Trim('"') })
}


function Get-IdentityFileFromHostConfigEntry {
    param([Parameter(Mandatory)][string]$RemoteHostName)
    $sshConfig = Find-ConfigFileOnHost
    if (-not $sshConfig) { return $null }
    $config = Get-Content -Path $sshConfig -Raw -Encoding UTF8
    $pattern = "(?ms)^Host\s+$RemoteHostName\b.*?(?=^Host\s|\z)"
    $match = [regex]::Match($config, $pattern)
    if (-not $match.Success) { return $null }
    if ($match.Value -match '(?m)^\s*IdentityFile\s+(.+)$') {
        return $matches[1].Trim().Replace("`$HOME", $env:USERPROFILE)
    }
    return $null
}


function Find-ConfigFileOnHost {
    param ([string]$Path = "$env:USERPROFILE\.ssh\config")
    if (-not (Test-Path $Path)) {
        Write-Host "  SSH config file not found at $Path." -ForegroundColor Yellow
        return $false
    }
    return $Path
}


function Find-SSHKeyInHostConfig {
    param (
        [string]$KeyName,
        [string]$RemoteHostName,
        [switch]$ReturnResult
    )
    $sshConfig = Find-ConfigFileOnHost
    $config = Get-Content -Path $sshConfig -Raw -Encoding UTF8
    $pattern = "(?ms)^Host\s+$RemoteHostName\b.*?(?=^Host\s|\z)"
    $match = [regex]::Match($config, $pattern)
    if (-not $match.Success) {
        if ($ReturnResult) { return $false }
        Write-Host "  No SSH config block found for host '$RemoteHostName'." -ForegroundColor Yellow
        return $false
    }
    $block = $match.Value
    $escapedKey = [regex]::Escape($KeyName)
    $pattern = "IdentityFile\s+[^\r\n]*[\\/]" + $escapedKey + "(?:\r?\n|$)"
    if ([regex]::IsMatch($block, $pattern)) {
        Write-Host "  IdentityFile '$KeyName' is present in host '$RemoteHostName' config block." -ForegroundColor Green
        if ($ReturnResult) { return $true }
    } else {
        Write-Host "  IdentityFile '$KeyName' not found in host '$RemoteHostName' config block." -ForegroundColor Red
        if ($ReturnResult) { return $false }
    }
}


function Find-PrivateKeyInHost {
    param (
        [string]$KeyName,
        [switch]$ReturnResult
    )
    if (Test-Path "$env:USERPROFILE\.ssh\$KeyName" -PathType Leaf) {
        if ($ReturnResult) { return $true } else { return }
    } else {
        if ($ReturnResult) { return $false } else { return }
    }
}


function Find-PublicKeyInHost {
    param (
        [string]$KeyName,
        [switch]$ReturnResult
    )
    if (Test-Path "$env:USERPROFILE\.ssh\$KeyName.pub" -PathType Leaf) {
        if ($ReturnResult) { return $true } else { return }
    } else {
        if ($ReturnResult) { return $false } else { return }
    }
}


function Get-IPAddressFromHostConfigEntry {
    param ([Parameter(Mandatory = $true)][string]$RemoteHostName)
    $sshConfig = Find-ConfigFileOnHost
    $config = Get-Content -Path $sshConfig -Raw -Encoding UTF8
    $pattern = "(?ms)^Host\s+$RemoteHostName\b.*?(?=^Host\s|\z)"
    $match = [regex]::Match($config, $pattern)
    if (-not $match.Success) {
        Write-Host "  No Host block found for '$RemoteHostName'" -ForegroundColor Yellow
        return $null
    }
    if ($match.Value -match 'HostName\s+([^\s]+)') { return $matches[1] }
    Write-Host "  No HostName defined in Host '$RemoteHostName'" -ForegroundColor Yellow
    return $null
}


function Get-AliasForHostIP {
    # Reverse-lookup: given an IP address, return the first Host alias whose
    # HostName value matches. Returns $null if not found.
    param([string]$IPAddress)
    if (-not $IPAddress) { return $null }
    foreach ($h in (Get-ConfiguredSSHHosts)) {
        if ($h.HostName -eq $IPAddress) { return $h.Alias }
    }
    return $null
}


function Get-RemoteUserFromConfigEntry {
    param ([Parameter(Mandatory = $true)][string]$RemoteHostName)
    $sshConfig = Find-ConfigFileOnHost
    $config = Get-Content -Path $sshConfig -Raw -Encoding UTF8
    $pattern = "(?ms)^Host\s+$RemoteHostName\b.*?(?=^Host\s|\z)"
    $match = [regex]::Match($config, $pattern)
    if (-not $match.Success) {
        Write-Host "  No Host block found for '$RemoteHostName'" -ForegroundColor Yellow
        return $null
    }
    if ($match.Value -match 'User\s+([^\s]+)') { return $matches[1] }
    Write-Host "  No User defined in Host '$RemoteHostName'" -ForegroundColor Yellow
    return $null
}
