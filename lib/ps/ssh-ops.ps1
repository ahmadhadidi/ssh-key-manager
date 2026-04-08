# lib/ps/ssh-ops.ps1 — SSH operations: deploy, install, test, remove, promote

function Resolve-SSHTarget {
    # Given an IP/address and user, returns "user@alias" if a matching HostName
    # entry exists in ~/.ssh/config so SSH applies the full config block.
    # Falls back to "user@address" if nothing matches.
    param(
        [string]$RemoteHostAddress,
        [string]$RemoteUser
    )
    $configPath = "$env:USERPROFILE\.ssh\config"
    if (Test-Path $configPath) {
        $config  = Get-Content $configPath -Raw -Encoding UTF8
        $pattern = "(?ms)^Host\s+(\S+).*?(?=^Host\s|\z)"
        foreach ($hb in [regex]::Matches($config, $pattern)) {
            $alias = $hb.Groups[1].Value.Trim()
            if ($alias -eq $RemoteHostAddress) {
                Write-Host "  SSH config entry '$alias' will be used." -ForegroundColor DarkGray
                return "$RemoteUser@$alias"
            }
            if ($hb.Value -match "(?m)^\s*HostName\s+$([regex]::Escape($RemoteHostAddress))\s*$") {
                Write-Host "  SSH config entry '$alias' found for $RemoteHostAddress — key from config will be used." -ForegroundColor DarkGray
                return "$RemoteUser@$alias"
            }
        }
    }
    return "$RemoteUser@$RemoteHostAddress"
}


function Install-SSHKeyOnRemote {
    param ([string]$KeyName)

    $PublicKey = Get-PublicKeyInHost -KeyName $KeyName
    if (-not $PublicKey) { return }

    $RemoteHostAddress = Read-RemoteHostAddress -SubnetPrefix "$DefaultSubnetPrefix"
    $selectedAlias     = $script:_LastSelectedAlias
    $RemoteUser        = Read-RemoteUser -DefaultUser "$DefaultUserName"

    $target = Resolve-SSHTarget -RemoteHostAddress $RemoteHostAddress -RemoteUser $RemoteUser
    $_idLookup = if ($selectedAlias) { $selectedAlias } else { $RemoteHostAddress }
    foreach ($k in (Get-IdentityFilesForHost $_idLookup)) {
        Write-Host "  Using key: $k" -ForegroundColor DarkGray
    }
    Write-Host "  Connecting to $target..."

    try {
        if (![string]::IsNullOrEmpty($DefaultPassword) -and (Get-Command sshpass -ErrorAction SilentlyContinue)) {
            Write-Host "  Using sshpass with stored password." -ForegroundColor DarkGray
            $RemoteHostName = $PublicKey | sshpass -p $DefaultPassword ssh -o StrictHostKeyChecking=accept-new $target 'mkdir -p .ssh && cat >> .ssh/authorized_keys && hostname'
        } else {
            $RemoteHostName = $PublicKey | ssh $target 'mkdir -p .ssh && cat >> .ssh/authorized_keys && hostname'
        }
        Write-Host "  SSH Public Key installed successfully." -ForegroundColor Green

        $defaultAlias = if ($selectedAlias) { $selectedAlias } else { $RemoteHostName }
        Write-Host "  Remote hostname: $RemoteHostName" -ForegroundColor DarkGray
        $hostAlias = Read-HostWithDefault -Prompt "Name this Host in ~/.ssh/config:" -Default $defaultAlias
        if ([string]::IsNullOrWhiteSpace($hostAlias)) { $hostAlias = $defaultAlias }

        Write-Host "  Registering key to SSH config as '$hostAlias'..."
        Add-SSHKeyToHostConfig -KeyName $KeyName -RemoteHostAddress $RemoteHostAddress -RemoteHostName $hostAlias -RemoteUser $RemoteUser
    } catch {
        Write-Host "  Failed to inject SSH key. Check network, credentials, or host status." -ForegroundColor Red
    }
}


function Register-RemoteHostConfig {
    Write-Host "  Enter the IP or hostname of the remote machine (not yet in config)." -ForegroundColor Cyan
    $RemoteHostAddress = Read-ColoredInput -Prompt "  Remote IP / hostname" -ForegroundColor "Cyan"
    if ($RemoteHostAddress -match "^\d{1,3}$") { $RemoteHostAddress = "$DefaultSubnetPrefix.$RemoteHostAddress" }
    if ([string]::IsNullOrWhiteSpace($RemoteHostAddress)) { return }

    $RemoteUser = Read-RemoteUser -DefaultUser "$DefaultUserName"
    $target     = "$RemoteUser@$RemoteHostAddress"

    Write-Host "  Connecting to $target to read authorized_keys..." -ForegroundColor DarkGray
    try {
        $rawKeys = ssh -o StrictHostKeyChecking=accept-new $target "cat ~/.ssh/authorized_keys 2>/dev/null"
    } catch {
        Write-Host "  Connection failed: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    $remoteLines = @($rawKeys -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($remoteLines.Count -eq 0) {
        Write-Host "  No authorized_keys found on $target." -ForegroundColor Yellow
        return
    }

    $sshDir  = "$env:USERPROFILE\.ssh"
    $matches = @()
    foreach ($pub in (Get-ChildItem -Path $sshDir -Filter "*.pub" -File -ErrorAction SilentlyContinue)) {
        $content = (Get-Content $pub.FullName -Raw -Encoding UTF8).Trim()
        if ($remoteLines -contains $content) {
            $matches += [pscustomobject]@{ KeyName = $pub.BaseName; PubPath = $pub.FullName }
        }
    }

    if ($matches.Count -eq 0) {
        Write-Host "  No local public keys match the authorized_keys on $target." -ForegroundColor Yellow
        Write-Host "  Install a key first via 'Generate & Install' or 'Install SSH Key'." -ForegroundColor DarkGray
        return
    }

    Write-Host "  Found $($matches.Count) matching local key(s):" -ForegroundColor Green
    $matches | ForEach-Object { Write-Host "     $($_.KeyName)" -ForegroundColor Cyan }

    if ($matches.Count -gt 1) {
        $labels  = @($matches | ForEach-Object { $_.KeyName })
        $picked  = Select-FromList -Items $labels -Prompt "Select key for the config block:" -StrictList
        if (-not $picked) { return }
        $chosen  = $matches | Where-Object { $_.KeyName -eq $picked } | Select-Object -First 1
    } else {
        $chosen  = $matches[0]
    }

    $hostAlias = Read-HostWithDefault -Prompt "  Alias for this host in ~/.ssh/config:" -Default $RemoteHostAddress
    if ([string]::IsNullOrWhiteSpace($hostAlias)) { $hostAlias = $RemoteHostAddress }

    Add-SSHKeyToHostConfig -KeyName $chosen.KeyName -RemoteHostAddress $RemoteHostAddress -RemoteHostName $hostAlias -RemoteUser $RemoteUser
}


function Deploy-SSHKeyToRemote {
    param ([string]$KeyName)

    if (-not (Find-PrivateKeyInHost -KeyName $KeyName -ReturnResult $true)) {
        Write-Host "`n  Key does not exist. Generating..." -ForegroundColor Yellow
        $Comment = Read-SSHKeyComment -DefaultComment "$KeyName$DefaultCommentSuffix"
        Add-SSHKeyInHost -KeyName $KeyName -Comment $Comment
    } else {
        Write-Host "`n  Key already exists. Proceeding with installation...`n" -ForegroundColor Cyan
    }

    Install-SSHKeyOnRemote -KeyName $KeyName
}


function Test-SSHConnection {
    param (
        [string]$RemoteUser,
        [string]$RemoteHost,
        [string]$IdentityFile = "",
        [switch]$ReturnResult
    )

    $target = Resolve-SSHTarget -RemoteHostAddress $RemoteHost -RemoteUser $RemoteUser

    $tcpOk = $false
    try {
        $tcp   = New-Object System.Net.Sockets.TcpClient
        $ar    = $tcp.BeginConnect($RemoteHost, 22, $null, $null)
        $tcpOk = $ar.AsyncWaitHandle.WaitOne(3000)
        $tcp.Close()
    } catch { $tcpOk = $false }

    if (-not $tcpOk) {
        Write-Host "  Connection refused: $RemoteHost is not accepting SSH connections on port 22." -ForegroundColor Red
        if ($ReturnResult) { return $false } else { return }
    }

    try {
        $sshArgs = @($target, "echo SSH Connection Successful")
        if ($IdentityFile) {
            $sshArgs = @("-i", $IdentityFile, "-o", "BatchMode=yes") + $sshArgs
        }
        $result = ssh @sshArgs 2>&1

        if ($result -match "Name or service not known" -or $result -match "Could not resolve hostname") {
            Write-Host "  DNS error: Could not resolve $RemoteHost." -ForegroundColor Red
            if ($ReturnResult) { return $false } else { return }
        }
        elseif ($result -match "Permission denied") {
            if ($IdentityFile) {
                Write-Host "  Key rejected or passphrase required — add key to ssh-agent first." -ForegroundColor Yellow
            } else {
                Write-Host "  SSH reachable, but permission denied for user '$RemoteUser'." -ForegroundColor Yellow
            }
            if ($ReturnResult) { return $true } else { return }
        }
        else {
            Write-Host "  SSH connection to $RemoteHost is successful." -ForegroundColor Green
            if ($ReturnResult) { return $true } else { return }
        }
    } catch {
        Write-Host "  Unexpected error during SSH test:" -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)"
        if ($ReturnResult) { return $false } else { return }
    }
}


function Remove-IdentityFileFromConfigBlock {
    # Removes all IdentityFile lines referencing $KeyName from the Host block for $HostAlias.
    param([string]$KeyName, [string]$HostAlias)
    $sshConfig = Find-ConfigFileOnHost
    if (-not $sshConfig) { return }
    $config     = Get-Content $sshConfig -Raw -Encoding UTF8
    $aliasE     = [regex]::Escape($HostAlias)
    $blockMatch = [regex]::Match($config, "(?ms)^Host\s+$aliasE\b.*?(?=^Host\s|\z)")
    if (-not $blockMatch.Success) {
        Write-Host "  No config block found for '$HostAlias'." -ForegroundColor Yellow
        return
    }
    $block    = $blockMatch.Value
    $keyE     = [regex]::Escape($KeyName)
    $newBlock = [regex]::Replace($block, "(?m)^\s*IdentityFile\s+[^\r\n]*[\\/]$keyE[^\r\n]*(\r?\n|$)", "")
    if ($newBlock -eq $block) {
        Write-Host "  Key '$KeyName' not found in config block '$HostAlias'." -ForegroundColor DarkGray
        return
    }
    Set-Content $sshConfig -Value ($config.Replace($block, $newBlock)) -Encoding UTF8
    Write-Host "  IdentityFile '$KeyName' removed from config block '$HostAlias'." -ForegroundColor Green
}


function Remove-SSHKeyFromRemote {
    param (
        [string]$RemoteUser,
        [string]$RemoteHost,
        [string]$KeyName
    )

    $PublicKey     = Get-PublicKeyInHost -KeyName $KeyName
    $RemoteCommand = "TMP_FILE=`$(mktemp) && printf '%s`\n' '$PublicKey' > `$TMP_FILE && awk 'NR==FNR { keys[`$0]; next } !(`$0 in keys)' `$TMP_FILE ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.tmp && mv ~/.ssh/authorized_keys.tmp ~/.ssh/authorized_keys && rm -f `$TMP_FILE"
    $target        = Resolve-SSHTarget -RemoteHostAddress $RemoteHost -RemoteUser $RemoteUser

    foreach ($k in (Get-IdentityFilesForHost $RemoteHost)) {
        Write-Host "  Using key: $k" -ForegroundColor DarkGray
    }
    Write-Host "`n  Will connect to remove the public key from ${target}:`n  $($PublicKey.Trim())`n" -ForegroundColor Yellow

    try {
        ssh $target $RemoteCommand
        Write-Host "  SSH key removed from remote authorized_keys." -ForegroundColor Green

        $privPath = "$env:USERPROFILE\.ssh\$KeyName"
        $pubPath  = "$privPath.pub"
        Confirm-UserChoice -Message "  Remove local key '$KeyName' from THIS machine?" -Action {
            if (Test-Path $privPath) { Remove-Item $privPath -Force; Write-Host "  Deleted: $privPath" -ForegroundColor Green }
            if (Test-Path $pubPath)  { Remove-Item $pubPath  -Force; Write-Host "  Deleted: $pubPath"  -ForegroundColor Green }
        } -DefaultAnswer "n"
    } catch {
        Write-Host "  Failed to remove the SSH key from remote." -ForegroundColor Red
    }
}


function Deploy-PromotedKey {
    Write-Host "  Which key do you want to demote (remove from remote)?" -ForegroundColor Cyan
    $KeyNameToRemove = Read-SSHKeyName

    Write-Host "  From which remote machine?" -ForegroundColor Cyan
    $RemoteHostName = Read-RemoteHostName -SubnetPrefix "$DefaultSubnetPrefix"

    Write-Host "  Replace with which key?" -ForegroundColor Cyan
    $KeyNameNew = Read-SSHKeyName
    Deploy-SSHKeyToRemote -KeyName $KeyNameNew

    $RemoteHostAddress = Get-IPAddressFromHostConfigEntry -RemoteHostName $RemoteHostName
    $RemoteUser        = Get-RemoteUserFromConfigEntry    -RemoteHostName $RemoteHostName

    Confirm-UserChoice -Message "  Remove demoted key '$KeyNameToRemove' from remote '$RemoteHostName'?" -Action {
        Remove-SSHKeyFromRemote -RemoteUser $RemoteUser -RemoteHost $RemoteHostAddress -KeyName $KeyNameToRemove
    } -DefaultAnswer "n"
}


function Remove-IdentityFileFromConfigEntry {
    param (
        [Parameter(Mandatory)][string]$KeyName,
        [Parameter(Mandatory)][string]$RemoteHostName
    )
    $ConfigPath = "$env:USERPROFILE\.ssh\config"
    if (-not (Test-Path $ConfigPath)) {
        Write-Host "  SSH config not found at $ConfigPath" -ForegroundColor Red
        return
    }
    $config = Get-Content -Path $ConfigPath -Raw -Encoding UTF8
    $pattern = "(?ms)^Host\s+$RemoteHostName\b.*?(?=^Host\s|\z)"
    $match = [regex]::Match($config, $pattern)
    if (-not $match.Success) {
        Write-Host "  No Host block found for '$RemoteHostName'" -ForegroundColor Yellow
        return
    }
    $block = $match.Value
    $escapedKey = [regex]::Escape($KeyName)
    $identityPattern = "^\s*IdentityFile\s+.*[\\/]" + $escapedKey + "(\s*)$"
    $lines = $block -split "`n"
    $newLines = $lines | Where-Object { $_ -notmatch $identityPattern }
    if ($lines.Count -eq $newLines.Count) {
        Write-Host "  No IdentityFile ending in '$KeyName' was found under Host '$RemoteHostName'" -ForegroundColor Yellow
        return
    }
    $newBlock  = $newLines -join "`n"
    $newConfig = $config -replace [regex]::Escape($block), $newBlock
    Set-Content -Path $ConfigPath -Value $newConfig -Encoding UTF8
    Write-Host "  IdentityFile '$KeyName' removed from Host '$RemoteHostName'" -ForegroundColor Green
}


function Invoke-SSHWithKeyThenPassword {
    param(
        [Parameter(Mandatory)][string]$RemoteUser,
        [Parameter(Mandatory)][string]$RemoteHost,
        [string]$IdentityFile,
        [Parameter(Mandatory)][string]$RemoteCommand
    )
    $baseArgs = @("-o", "ConnectTimeout=6", "-o", "StrictHostKeyChecking=accept-new")
    if ($IdentityFile) { $baseArgs += @("-i", $IdentityFile) }
    $keyOnlyArgs = $baseArgs + @("-o", "BatchMode=yes", "$RemoteUser@$RemoteHost", $RemoteCommand)
    $out  = & ssh @keyOnlyArgs 2>&1
    $code = $LASTEXITCODE
    if ($code -eq 0) { return @{ Success = $true; UsedPassword = $false; Output = $out } }
    if ($out -match "Permission denied" -or $out -match "Authentication failed") {
        Write-Host "  No usable SSH key found for $RemoteUser@$RemoteHost. Falling back to password..." -ForegroundColor Yellow
        $passwordArgs = $baseArgs + @("$RemoteUser@$RemoteHost", $RemoteCommand)
        $out2  = & ssh @passwordArgs 2>&1
        $code2 = $LASTEXITCODE
        return @{ Success = ($code2 -eq 0); UsedPassword = $true; Output = $out2 }
    }
    return @{ Success = $false; UsedPassword = $false; Output = $out }
}
