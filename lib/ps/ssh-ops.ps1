# lib/ps/ssh-ops.ps1 — SSH operations: key generation, deploy, install, test, remove, promote
# EXPORTS: Add-SSHKeyInHost  Add-SSHKeyToHostConfig
#          Resolve-SSHTarget  Install-SSHKeyOnRemote  Register-RemoteHostConfig
#          Deploy-SSHKeyToRemote  Test-SSHConnection
#          Remove-IdentityFileFromConfigBlock  Remove-SSHKeyFromRemote
#          Deploy-PromotedKey  Add-KeyToHosts  Import-ExternalSSHKey
#          Remove-IdentityFileFromConfigEntry  Invoke-SSHWithKeyThenPassword

function Add-SSHKeyInHost {
    param (
        [string]$KeyName,
        [string]$Comment
    )

    Write-Host -NoNewline "  `e[36mPassphrase`e[0m `e[90m(empty = passwordless)`e[0m  " -ForegroundColor Cyan
    $securePass = Read-Host -AsSecureString
    $Password   = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                      [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass))

    $stars = if ($Password) { "*" * $Password.Length } else { "`e[90m(none)`e[0m" }
    Write-Host ""
    Write-Host "  `e[90m  key      `e[0m`e[36m$KeyName`e[0m"
    Write-Host "  `e[90m  comment  `e[0m`e[36m$Comment`e[0m"
    Write-Host "  `e[90m  password `e[0m`e[90m$stars`e[0m"
    Write-Host ""

    $th = $Host.UI.RawUI.WindowSize.Height
    [Console]::Write("`e[s`e[$th;1H`e[K`e[u")

    Write-Out 'dim' "Generating SSH key..."

    $sshKeygenCmd = "ssh-keygen -t ed25519 -f `"$env:USERPROFILE\.ssh\$KeyName`" -C `"$Comment`""
    $sshKeygenCmd += if ($Password) { " -N `"$Password`"" } else { " -N ''" }
    Invoke-Expression $sshKeygenCmd

    Write-OutItem "$env:USERPROFILE\.ssh\$KeyName  generated."
}


function Add-SSHKeyToHostConfig {
    param (
        [string]$KeyName,
        [string]$RemoteHostName,
        [string]$RemoteHostAddress,
        [string]$RemoteUser
    )

    $keyPath      = "$env:USERPROFILE\.ssh\$KeyName"
    $identityLine = "    IdentityFile $keyPath"

    if (Find-PrivateKeyInHost -KeyName $KeyName -ReturnResult $true) {
        $sshConfig = Find-ConfigFileOnHost
        $config    = Get-Content -Path $sshConfig -Raw -Encoding UTF8
        $hostPattern = "(?ms)^Host\s+$RemoteHostName\b.*?(?=^Host\s|\z)"
        $match = [regex]::Match($config, $hostPattern)

        if ($match.Success) {
            $block = $match.Value
            if ($block -notmatch [regex]::Escape($identityLine.Trim())) {
                $lines = $block -split "`n"
                $insertIndex = ($lines |
                    Select-String '^\s*IdentityFile\b' |
                    Select-Object -Last 1).LineNumber
                if ($insertIndex) {
                    $lines = $lines[0..($insertIndex - 1)] + $identityLine + $lines[$insertIndex..($lines.Count - 1)]
                } else {
                    $lines = $lines[0..0] + $identityLine + $lines[1..($lines.Count - 1)]
                }
                $newBlock  = ($lines -join "`n")
                $newConfig = $config -replace [regex]::Escape($block), $newBlock
                Set-Content -Path $sshConfig -Value $newConfig -Encoding UTF8
                Write-Out 'ok' "IdentityFile added to existing Host $RemoteHostName."
            } else {
                Write-Out 'warn' "IdentityFile already exists under Host $RemoteHostName."
            }
        } else {
            $hostEntry = "Host $RemoteHostName`n    HostName $RemoteHostAddress`n    User $RemoteUser`n    IdentityFile $keyPath"
            $existing  = (Get-Content $sshConfig -Raw -Encoding UTF8).TrimEnd()
            Set-Content $sshConfig -Value ($existing + "`n`n" + $hostEntry + "`n") -Encoding UTF8 -NoNewline
            Write-Out 'ok'   "SSH config block created for $RemoteHostName."
            Write-Out 'info' "Connect with: ssh $RemoteHostName"
        }
    } else {
        Write-Out 'error' "Could not find private SSH key at $keyPath"
    }
}


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
                Write-Out 'dim' "SSH config entry '$alias' will be used."
                return "$RemoteUser@$alias"
            }
            if ($hb.Value -match "(?m)^\s*HostName\s+$([regex]::Escape($RemoteHostAddress))\s*$") {
                Write-Out 'dim' "SSH config entry '$alias' found for $RemoteHostAddress — key from config will be used."
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

    Invoke-RemotePrompt
    $RemoteHostAddress = $script:_RemoteHost
    $selectedAlias     = $script:_RemoteAlias
    $RemoteUser        = $script:_RemoteUser

    $target    = Resolve-SSHTarget -RemoteHostAddress $RemoteHostAddress -RemoteUser $RemoteUser
    $idLookup  = if ($selectedAlias) { $selectedAlias } else { $RemoteHostAddress }
    Write-IdentityFiles $idLookup
    Write-Out 'plain' "Connecting to $target..."

    try {
        if (![string]::IsNullOrEmpty($DefaultPassword) -and (Get-Command sshpass -ErrorAction SilentlyContinue)) {
            Write-Out 'dim' "Using sshpass with stored password."
            $RemoteHostName = $PublicKey | sshpass -p $DefaultPassword ssh -o StrictHostKeyChecking=accept-new $target 'mkdir -p .ssh && cat >> .ssh/authorized_keys && hostname'
        } else {
            Write-SSHFence $target
            $RemoteHostName = $PublicKey | ssh $target 'mkdir -p .ssh && cat >> .ssh/authorized_keys && hostname'
            Write-SSHFenceClose
        }
        Write-Out 'ok' 'SSH Public Key installed successfully.'
        Write-Out 'dim' "Remote hostname: $RemoteHostName"

        $defaultAlias = if ($selectedAlias) { $selectedAlias } else { $RemoteHostName }
        $hostAlias    = Read-HostWithDefault -Prompt "Name this Host in ~/.ssh/config:" -Default $defaultAlias
        if ([string]::IsNullOrWhiteSpace($hostAlias)) { $hostAlias = $defaultAlias }

        Confirm-UserChoice -Message "  Add '$KeyName' as IdentityFile in config block '$hostAlias'?" -Action {
            Write-Out 'plain' "Registering key to SSH config as '$hostAlias'..."
            Add-SSHKeyToHostConfig -KeyName $KeyName -RemoteHostAddress $RemoteHostAddress -RemoteHostName $hostAlias -RemoteUser $RemoteUser
        } -DefaultAnswer "y"
    } catch [System.OperationCanceledException] {
        throw
    } catch {
        Write-Out 'error' 'Failed to inject SSH key. Check network, credentials, or host status.'
    }
}


function Register-RemoteHostConfig {
    Write-Out 'info' "Enter the IP or hostname of the remote machine (not yet in config)."
    Invoke-RemotePrompt
    $RemoteHostAddress = $script:_RemoteHost
    $RemoteUser        = $script:_RemoteUser
    $target            = "$RemoteUser@$RemoteHostAddress"

    Write-Out 'dim' "Connecting to $target to read authorized_keys..."
    Write-SSHFence $target
    try {
        $rawKeys = ssh -o StrictHostKeyChecking=accept-new $target "cat ~/.ssh/authorized_keys 2>/dev/null"
    } catch {
        Write-SSHFenceClose
        Write-Out 'error' "Connection failed: $($_.Exception.Message)"
        return
    }
    Write-SSHFenceClose

    $remoteLines = @($rawKeys -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($remoteLines.Count -eq 0) {
        Write-Out 'warn' "No authorized_keys found on $target."
        return
    }

    $sshDir      = "$env:USERPROFILE\.ssh"
    $matchedKeys = @()
    foreach ($pub in (Get-ChildItem -Path $sshDir -Filter "*.pub" -File -ErrorAction SilentlyContinue)) {
        $content = (Get-Content $pub.FullName -Raw -Encoding UTF8).Trim()
        if ($remoteLines -contains $content) {
            $matchedKeys += [pscustomobject]@{ KeyName = $pub.BaseName; PubPath = $pub.FullName }
        }
    }

    if ($matchedKeys.Count -eq 0) {
        Write-Out 'warn' "No local public keys match the authorized_keys on $target."
        Write-Out 'dim'  "Install a key first via 'Generate & Install' or 'Install SSH Key'."
        return
    }

    Write-Out 'ok' "Found $($matchedKeys.Count) matching local key(s):"
    $matchedKeys | ForEach-Object { Write-Out 'info' "  $($_.KeyName)" }

    if ($matchedKeys.Count -gt 1) {
        $labels  = @($matchedKeys | ForEach-Object { $_.KeyName })
        $picked  = Select-FromList -Items $labels -Prompt "Select key for the config block:" -StrictList
        if (-not $picked) { return }
        $chosen  = $matchedKeys | Where-Object { $_.KeyName -eq $picked } | Select-Object -First 1
    } else {
        $chosen  = $matchedKeys[0]
    }

    $hostAlias = Read-HostWithDefault -Prompt "Alias for this host in ~/.ssh/config:" -Default $RemoteHostAddress
    if ([string]::IsNullOrWhiteSpace($hostAlias)) { $hostAlias = $RemoteHostAddress }

    Add-SSHKeyToHostConfig -KeyName $chosen.KeyName -RemoteHostAddress $RemoteHostAddress -RemoteHostName $hostAlias -RemoteUser $RemoteUser
}


function Deploy-SSHKeyToRemote {
    param ([string]$KeyName)

    if (-not (Find-PrivateKeyInHost -KeyName $KeyName -ReturnResult $true)) {
        Write-Out 'warn' 'Key does not exist. Generating...'
        $Comment = Read-SSHKeyComment -DefaultComment "$KeyName$DefaultCommentSuffix"
        Add-SSHKeyInHost -KeyName $KeyName -Comment $Comment
    } else {
        Write-Out 'info' 'Key already exists. Proceeding with installation...'
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

    $tcpOk = $false
    try {
        $tcp   = New-Object System.Net.Sockets.TcpClient
        $ar    = $tcp.BeginConnect($RemoteHost, 22, $null, $null)
        $tcpOk = $ar.AsyncWaitHandle.WaitOne(3000)
        $tcp.Close()
    } catch { $tcpOk = $false }

    if (-not $tcpOk) {
        Write-Out 'error' "Connection refused: $RemoteHost is not accepting SSH connections on port 22."
        if ($ReturnResult) { return $false } else { return }
    }

    $sshArgs = @("-o", "ConnectTimeout=6", "-o", "StrictHostKeyChecking=accept-new")
    if ($IdentityFile) {
        # Bypass config entirely so no fallback keys from the host's block can succeed.
        # Do NOT use BatchMode=yes — passphrase-protected keys need to prompt.
        $sshArgs = @("-F", "NUL", "-i", $IdentityFile, "-o", "IdentitiesOnly=yes",
                     "-o", "PreferredAuthentications=publickey") + $sshArgs
        $target = "$RemoteUser@$RemoteHost"
    } else {
        $target = Resolve-SSHTarget -RemoteHostAddress $RemoteHost -RemoteUser $RemoteUser
    }
    $sshArgs += @($target, "echo SSH Connection Successful")

    Write-SSHFence $target
    try {
        $result = & ssh @sshArgs 2>&1
    } finally {
        Write-SSHFenceClose
    }

    if ($result -match "Name or service not known" -or $result -match "Could not resolve hostname") {
        Write-Out 'error' "DNS error: Could not resolve $RemoteHost."
        if ($ReturnResult) { return $false } else { return }
    } elseif ($result -match "Permission denied") {
        if ($IdentityFile) {
            Write-Out 'warn' "Key not authorized on $RemoteHost."
        } else {
            Write-Out 'warn' "SSH reachable, but permission denied for user '$RemoteUser'."
        }
        if ($ReturnResult) { return $true } else { return }
    } else {
        Write-Out 'ok' "SSH connection to $RemoteHost is successful."
        if ($ReturnResult) { return $true } else { return }
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
        Write-Out 'warn' "No config block found for '$HostAlias'."
        return
    }
    $block    = $blockMatch.Value
    $keyE     = [regex]::Escape($KeyName)
    $newBlock = [regex]::Replace($block, "(?m)^\s*IdentityFile\s+[^\r\n]*[\\/]$keyE[^\r\n]*(\r?\n|$)", "")
    if ($newBlock -eq $block) {
        Write-Out 'dim' "Key '$KeyName' not found in config block '$HostAlias'."
        return
    }
    Set-Content $sshConfig -Value ($config.Replace($block, $newBlock)) -Encoding UTF8
    Write-Out 'ok' "IdentityFile '$KeyName' removed from config block '$HostAlias'."
}


function Remove-SSHKeyFromRemote {
    param (
        [string]$RemoteUser,
        [string]$RemoteHost,
        [string]$KeyName
    )

    $PublicKey     = Get-PublicKeyInHost -KeyName $KeyName
    if (-not $PublicKey) { return }

    $target        = Resolve-SSHTarget -RemoteHostAddress $RemoteHost -RemoteUser $RemoteUser
    Write-IdentityFiles $RemoteHost

    $RemoteCommand = "TMP_FILE=`$(mktemp) && printf '%s`\n' '$PublicKey' > `$TMP_FILE && awk 'NR==FNR { keys[`$0]; next } !(`$0 in keys)' `$TMP_FILE ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.tmp && mv ~/.ssh/authorized_keys.tmp ~/.ssh/authorized_keys && rm -f `$TMP_FILE"

    Write-Out 'warn' "Will connect to remove the public key from ${target}:"
    Write-Out 'dim'  "  $($PublicKey.Trim())"

    Write-SSHFence $target
    try {
        ssh $target $RemoteCommand
        Write-SSHFenceClose
        Write-Out 'ok' 'SSH key removed from remote authorized_keys.'

        $privPath = "$env:USERPROFILE\.ssh\$KeyName"
        $pubPath  = "$privPath.pub"
        Confirm-UserChoice -Message "  Remove local key '$KeyName' from THIS machine?" -Action {
            if (Test-Path $privPath) { Remove-Item $privPath -Force; Write-Out 'ok' "Deleted: $privPath" }
            if (Test-Path $pubPath)  { Remove-Item $pubPath  -Force; Write-Out 'ok' "Deleted: $pubPath"  }
        } -DefaultAnswer "n"
    } catch [System.OperationCanceledException] {
        Write-SSHFenceClose
        throw
    } catch {
        Write-SSHFenceClose
        Write-Out 'error' 'Failed to remove the SSH key from remote.'
    }
}


function Deploy-PromotedKey {
    Write-Out 'info' 'Which key do you want to demote (remove from remote)?'
    $KeyNameToRemove = Read-SSHKeyName

    Write-Out 'info' 'From which remote machine?'
    $RemoteHostName = Read-RemoteHostName -SubnetPrefix "$DefaultSubnetPrefix"

    Write-Out 'info' 'Replace with which key?'
    $KeyNameNew = Read-SSHKeyName
    Deploy-SSHKeyToRemote -KeyName $KeyNameNew

    $RemoteHostAddress = Get-IPAddressFromHostConfigEntry -RemoteHostName $RemoteHostName
    $RemoteUser        = Get-RemoteUserFromConfigEntry    -RemoteHostName $RemoteHostName

    Confirm-UserChoice -Message "  Remove demoted key '$KeyNameToRemove' from remote '$RemoteHostName'?" -Action {
        Remove-SSHKeyFromRemote -RemoteUser $RemoteUser -RemoteHost $RemoteHostAddress -KeyName $KeyNameToRemove
    } -DefaultAnswer "n"
}


function Add-KeyToHosts {
    # Multi-select configured hosts and append $KeyName as IdentityFile to each chosen block.
    param([string]$KeyName)

    $hosts = @(Get-ConfiguredSSHHosts)
    if ($hosts.Count -eq 0) {
        Write-Out 'warn' "No configured hosts — add a host block first."
        return
    }

    $labels = @($hosts | ForEach-Object {
        if ($_.HostName) { "$($_.Alias)  ($($_.HostName))" } else { $_.Alias }
    })

    try {
        $selected = Select-MultiFromList -Items $labels -Prompt "Add '$KeyName' as IdentityFile in:"
    } catch [System.OperationCanceledException] {
        return
    }

    if ($selected.Count -eq 0) {
        Write-Out 'warn' 'No hosts selected.'
        return
    }

    foreach ($lbl in $selected) {
        $alias = ($lbl -split '\s+\(')[0].Trim()
        $h     = $hosts | Where-Object { $_.Alias -eq $alias } | Select-Object -First 1
        if ($h) {
            Add-SSHKeyToHostConfig -KeyName $KeyName -RemoteHostAddress $h.HostName -RemoteHostName $h.Alias -RemoteUser $h.User
        }
    }
}


function Import-ExternalSSHKey {
    # Import a key pair from a local path, a remote machine (SCP), or pasted content.
    $choice = $null
    try {
        $choice = Select-FromList -Items @("Local file path", "Remote machine (SCP)", "Paste key content") `
                                  -Prompt "Import source" -StrictList
    } catch [System.OperationCanceledException] { return }
    if (-not $choice) { return }

    $sshDir = "$env:USERPROFILE\.ssh"

    if ($choice -eq "Local file path") {
        # ── Local path ──────────────────────────────────────────────────────────
        $privPath = Read-ColoredInput -Prompt "  Path to private key file" -ForegroundColor Cyan
        if ([string]::IsNullOrWhiteSpace($privPath)) { Write-Out 'error' 'Path is required.'; return }
        $privPath = $privPath -replace '^~', $env:USERPROFILE
        if (-not (Test-Path $privPath)) { Write-Out 'error' "File not found: $privPath"; return }

        $autoPub = "$privPath.pub"
        Write-Out 'dim' "Public key — leave blank to use $autoPub"
        $pubPath = Read-ColoredInput -Prompt "  Path to public key file" -ForegroundColor Cyan
        if ([string]::IsNullOrWhiteSpace($pubPath)) { $pubPath = $autoPub }
        $pubPath = $pubPath -replace '^~', $env:USERPROFILE
        if (-not (Test-Path $pubPath)) { Write-Out 'error' "Public key not found: $pubPath"; return }

        $keyName  = Split-Path $privPath -Leaf
        $destPriv = Join-Path $sshDir $keyName
        $destPub  = "$destPriv.pub"
        Ensure-SSHDir
        $ok = Write-KeyPair $destPriv $destPub $privPath $pubPath $true
        if ($ok) { Add-KeyToHosts $keyName }

    } elseif ($choice -eq "Remote machine (SCP)") {
        # ── Remote SCP ──────────────────────────────────────────────────────────
        Write-Out 'dim' "Connect to the machine that holds the keys."
        Invoke-RemotePrompt
        $RemoteHostAddress = $script:_RemoteHost
        $RemoteUser        = $script:_RemoteUser
        $target            = "${RemoteUser}@${RemoteHostAddress}"

        $remotePath = Read-ColoredInput -Prompt "  Full path to private key on remote" -ForegroundColor Cyan
        if ([string]::IsNullOrWhiteSpace($remotePath)) { Write-Out 'error' 'Path is required.'; return }

        $keyName  = Split-Path $remotePath -Leaf
        $destPriv = Join-Path $sshDir $keyName
        $destPub  = "$destPriv.pub"

        Ensure-SSHDir
        Write-Out 'dim' "Downloading $remotePath ..."
        Write-SSHFence $target
        $scpOk = $true
        try {
            scp -q "${target}:${remotePath}" $destPriv 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { $scpOk = $false }
        } catch { $scpOk = $false }

        if (-not $scpOk) {
            Write-SSHFenceClose
            Write-Out 'error' 'Failed to download private key.'
            return
        }

        Write-Out 'dim' "Downloading $remotePath.pub ..."
        try {
            scp -q "${target}:${remotePath}.pub" $destPub 2>&1 | Out-Null
        } catch {
            Write-Out 'warn' "Public key not found at $remotePath.pub — skipping."
        }
        Write-SSHFenceClose
        Write-Out 'ok' "Keys downloaded to $sshDir."
        Add-KeyToHosts $keyName

    } elseif ($choice -eq "Paste key content") {
        # ── Paste ───────────────────────────────────────────────────────────────
        $keyName = Read-HostWithDefault -Prompt "Key name:" -Default "imported-key"
        if ([string]::IsNullOrWhiteSpace($keyName)) { Write-Out 'error' 'Key name is required.'; return }

        Write-Out 'info' "Paste the private key."
        Write-Out 'dim'  "Input ends automatically at the -----END...----- line."
        Write-Host ""

        $privContent = ""
        do {
            $pl = Read-Host
            $privContent += $pl + "`n"
        } while ($pl -notlike "-----END*")

        if ($privContent -notmatch "-----BEGIN" -or $privContent -notmatch "-----END") {
            Write-Out 'error' 'Invalid private key — BEGIN/END markers not found.'
            return
        }

        Write-Host ""
        Write-Out 'info' "Paste the public key (single line, e.g. ssh-ed25519 AAAA...):"
        do { $pubContent = Read-Host } while ([string]::IsNullOrWhiteSpace($pubContent))

        $destPriv = Join-Path $sshDir $keyName
        $destPub  = "$destPriv.pub"
        Ensure-SSHDir
        $ok = Write-KeyPair $destPriv $destPub $privContent $pubContent $false
        if ($ok) { Add-KeyToHosts $keyName }
    }
}


function Remove-IdentityFileFromConfigEntry {
    param (
        [Parameter(Mandatory)][string]$KeyName,
        [Parameter(Mandatory)][string]$RemoteHostName
    )
    $ConfigPath = "$env:USERPROFILE\.ssh\config"
    if (-not (Test-Path $ConfigPath)) {
        Write-Out 'error' "SSH config not found at $ConfigPath"
        return
    }
    $config = Get-Content -Path $ConfigPath -Raw -Encoding UTF8
    $pattern = "(?ms)^Host\s+$RemoteHostName\b.*?(?=^Host\s|\z)"
    $match = [regex]::Match($config, $pattern)
    if (-not $match.Success) {
        Write-Out 'warn' "No Host block found for '$RemoteHostName'"
        return
    }
    $block = $match.Value
    $escapedKey = [regex]::Escape($KeyName)
    $identityPattern = "^\s*IdentityFile\s+.*[\\/]" + $escapedKey + "(\s*)$"
    $lines = $block -split "`n"
    $newLines = $lines | Where-Object { $_ -notmatch $identityPattern }
    if ($lines.Count -eq $newLines.Count) {
        Write-Out 'warn' "No IdentityFile ending in '$KeyName' was found under Host '$RemoteHostName'"
        return
    }
    $newBlock  = $newLines -join "`n"
    $newConfig = $config -replace [regex]::Escape($block), $newBlock
    Set-Content -Path $ConfigPath -Value $newConfig -Encoding UTF8
    Write-Out 'ok' "IdentityFile '$KeyName' removed from Host '$RemoteHostName'"
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
        Write-Out 'warn' "No usable SSH key found for $RemoteUser@$RemoteHost. Falling back to password..."
        $passwordArgs = $baseArgs + @("$RemoteUser@$RemoteHost", $RemoteCommand)
        $out2  = & ssh @passwordArgs 2>&1
        $code2 = $LASTEXITCODE
        return @{ Success = ($code2 -eq 0); UsedPassword = $true; Output = $out2 }
    }
    return @{ Success = $false; UsedPassword = $false; Output = $out }
}
