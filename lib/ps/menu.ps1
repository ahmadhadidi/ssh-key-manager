# lib/ps/menu.ps1 — Menu dispatcher and all menu case handlers
# Dot-sourced by hddssh.ps1 — do not execute directly.
# EXPORTS: Invoke-MenuChoice
#   handlers: _MenuGenerateAndInstall  _MenuInstallKey  _MenuTestConnection
#             _MenuDeleteRemoteKey  _MenuPromoteKey  _MenuGenerateKey
#             _MenuListKeys  _MenuAppendKeyToConfig  _MenuDeleteLocalKey
#             _MenuRemoveKeyFromConfig  _MenuShowBestPractices  _MenuConfDefaults
#             _MenuRemoveHost  _MenuViewConfig  _MenuEditConfig
#             _MenuListAuthorizedKeys  _MenuAddConfigBlock  _MenuImportKey

# ── Dispatcher ────────────────────────────────────────────────────────────────
# Returns $true to signal "skip Wait-UserAcknowledge"; $null otherwise.
function Invoke-MenuChoice {
    param([string]$Choice)
    switch ($Choice) {
        "1"  { return _MenuGenerateAndInstall }
        "2"  { return _MenuTestConnection }
        "3"  { return _MenuDeleteRemoteKey }
        "4"  { return _MenuPromoteKey }
        "5"  { return _MenuGenerateKey }
        "6"  { return _MenuListKeys }
        "7"  { return _MenuAppendKeyToConfig }
        "8"  { return _MenuDeleteLocalKey }
        "9"  { return _MenuRemoveKeyFromConfig }
        "10" { return _MenuShowBestPractices }
        "11" { return _MenuConfDefaults }
        "12" { return _MenuRemoveHost }
        "13" { return _MenuViewConfig }
        "14" { return _MenuEditConfig }
        "15" { return _MenuInstallKey }
        "16" { return _MenuListAuthorizedKeys }
        "17" { return _MenuAddConfigBlock }
        "18" { return _MenuImportKey }
    }
}

# ── Menu case handlers ────────────────────────────────────────────────────────

function _MenuGenerateAndInstall {   # choice 1 — generate if missing, deploy to remote
    Show-OpBanner @("host", $env:COMPUTERNAME)
    $KeyName = Read-SSHKeyName
    Deploy-SSHKeyToRemote -KeyName $KeyName
}

function _MenuInstallKey {           # choice 15 — key must already exist locally
    Show-OpBanner @("host", $env:COMPUTERNAME)
    $KeyName = Read-SSHKeyName
    if (-not (Find-PrivateKeyInHost -KeyName $KeyName -ReturnResult $true)) {
        Write-Out 'error' "Key '$KeyName' not found locally. Use 'Generate & Install' to create it first."
        return
    }
    Install-SSHKeyOnRemote -KeyName $KeyName
}

function _MenuTestConnection {       # choice 2 — pick key from host config or all local keys; supports Test ALL sweep
    Show-OpBanner @("host", $env:COMPUTERNAME, "user", $DefaultUserName)
    Invoke-RemotePrompt
    $RemoteHost = $script:_RemoteHost
    $RemoteUser = $script:_RemoteUser
    $selAlias   = $script:_RemoteAlias

    $cfgKeys = @(Get-IdentityFilesForHost ($(if ($selAlias) { $selAlias } else { $RemoteHost })))

    if ($cfgKeys.Count -gt 1) {
        $allLabel  = "-- Test ALL ($($cfgKeys.Count) keys)"
        $keyLabels = @($allLabel) + $cfgKeys
        $selected  = Select-FromList -Items $keyLabels -Prompt "Select key to test:"
        if ($selected -and $selected.StartsWith("--")) {
            $isFirst = $true
            $cfgKeys | ForEach-Object {
                if (-not $isFirst) { Write-Host "" }
                $isFirst = $false
                Write-Out 'dim' "Testing with key: $_"
                Test-SSHConnection -RemoteUser $RemoteUser -RemoteHost $RemoteHost -IdentityFile $_
            }
        } elseif ($selected) {
            Write-Out 'dim' "Testing with key: $selected"
            Test-SSHConnection -RemoteUser $RemoteUser -RemoteHost $RemoteHost -IdentityFile $selected
        }
    } else {
        if ($cfgKeys.Count -eq 1) { Write-Out 'dim' "Testing with key: $($cfgKeys[0])" }
        Test-SSHConnection -RemoteUser $RemoteUser -RemoteHost $RemoteHost
    }
}

function _MenuDeleteRemoteKey {      # choice 3 — fetch remote authorized_keys, cross-match local .pub, remove selected; offer to strip config + local files
    Show-OpBanner @("host", $env:COMPUTERNAME)
    Invoke-RemotePrompt
    $RemoteHostAddress = $script:_RemoteHost
    $RemoteUser        = $script:_RemoteUser
    $selectedAlias     = $script:_RemoteAlias
    $target            = Resolve-SSHTarget -RemoteHostAddress $RemoteHostAddress -RemoteUser $RemoteUser
    $idLookup          = if ($selectedAlias) { $selectedAlias } else { $RemoteHostAddress }
    Write-IdentityFiles $idLookup

    Write-Out 'dim' "Fetching authorized keys from $target..."
    Write-SSHFence $target
    try {
        $rawKeys = ssh $target "cat ~/.ssh/authorized_keys 2>/dev/null"
    } catch {
        Write-SSHFenceClose
        Write-Out 'error' "Could not connect to ${target}: $($_.Exception.Message)"
        return
    }
    Write-SSHFenceClose

    $remoteLines = @($rawKeys -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($remoteLines.Count -eq 0) {
        Write-Out 'dim' "No authorized_keys found on $target."
        return
    }

    $sshDir      = "$env:USERPROFILE\.ssh"
    $matchedKeys = @()
    foreach ($pub in (Get-ChildItem -Path $sshDir -Filter "*.pub" -File -ErrorAction SilentlyContinue)) {
        $content = (Get-Content $pub.FullName -Raw -Encoding UTF8).Trim()
        if ($remoteLines -contains $content) {
            $matchedKeys += [pscustomobject]@{ KeyName = $pub.BaseName; PubPath = $pub.FullName; PubContent = $content }
        }
    }
    if ($matchedKeys.Count -eq 0) {
        Write-Out 'warn' "No local public keys found in $target authorized_keys."
        return
    }

    $labels   = @($matchedKeys | ForEach-Object { "$($_.KeyName)  ($($_.PubPath))" })
    $selected = Select-FromList -Items $labels -Prompt "Select key to remove from remote:" -StrictList
    if (-not $selected) { return }
    $pick     = $matchedKeys[$labels.IndexOf($selected)]

    $pubContent    = $pick.PubContent
    $RemoteCommand = "TMP_FILE=`$(mktemp) && printf '%s`\n' '$pubContent' > `$TMP_FILE && awk 'NR==FNR { keys[`$0]; next } !(`$0 in keys)' `$TMP_FILE ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.tmp && mv ~/.ssh/authorized_keys.tmp ~/.ssh/authorized_keys && rm -f `$TMP_FILE"
    Write-Out 'warn' "Removing key '$($pick.KeyName)' from $target..."
    Write-SSHFence $target
    try {
        ssh $target $RemoteCommand
        Write-SSHFenceClose
        Write-Out 'ok' "Key removed from remote authorized_keys."
    } catch {
        Write-SSHFenceClose
        Write-Out 'error' "Failed to remove key from remote."
        return
    }

    if ($selectedAlias) {
        Confirm-UserChoice -Message "  Remove IdentityFile '$($pick.KeyName)' from config block '$selectedAlias'?" -Action {
            Remove-IdentityFileFromConfigBlock -KeyName $pick.KeyName -HostAlias $selectedAlias
        } -DefaultAnswer "y"
    }

    $privPath = "$sshDir\$($pick.KeyName)"
    $pubPath  = "$privPath.pub"
    Confirm-UserChoice -Message "  Delete local key '$($pick.KeyName)' from this machine?" -Action {
        if (Test-Path $privPath) { Remove-Item $privPath -Force; Write-Out 'ok' "Deleted: $privPath" }
        if (Test-Path $pubPath)  { Remove-Item $pubPath  -Force; Write-Out 'ok' "Deleted: $pubPath"  }
    } -DefaultAnswer "n"
}

function _MenuPromoteKey {           # choice 4 — install new key, remove old in one operation
    Show-OpBanner @("host", $env:COMPUTERNAME)
    Deploy-PromotedKey
}

function _MenuGenerateKey {          # choice 5 — generate ED25519 pair locally without deploying
    Show-OpBanner @("host", $env:COMPUTERNAME)
    $KeyName = Read-SSHKeyName
    $Comment = Read-SSHKeyComment -DefaultComment "$KeyName$DefaultCommentSuffix"
    Add-SSHKeyInHost -KeyName $KeyName -Comment $Comment
}

function _MenuListKeys {             # choice 6 — show key inventory with fingerprints and host refs
    Show-SSHKeyInventory
    return $true
}

function _MenuAppendKeyToConfig {    # choice 7 — verify key works on remote, then add IdentityFile to host config block
    Show-OpBanner @("config", "$env:USERPROFILE\.ssh\config")
    $KeyName = Read-SSHKeyName
    Invoke-RemotePrompt
    $RemoteHostAddress = $script:_RemoteHost
    $RemoteUser        = $script:_RemoteUser
    $hostName          = if ($script:_RemoteAlias) { $script:_RemoteAlias } else { $script:_RemoteHost }
    $hostDisplay       = if ($hostName -ne $RemoteHostAddress) { "$hostName ($RemoteHostAddress)" } else { $hostName }

    $keyPath = "$env:USERPROFILE\.ssh\$KeyName"
    Write-SSHFence
    $testOut = & ssh -F NUL -i $keyPath -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=6 `
                     -o StrictHostKeyChecking=accept-new "$RemoteUser@$RemoteHostAddress" "echo ok" 2>&1
    Write-SSHFenceClose

    if ($testOut -eq "ok") {
        Write-Out 'ok' "Key verified on $hostDisplay."
    } else {
        Write-Out 'warn' "Could not verify '$KeyName' on $hostDisplay — it may not be installed yet."
        $proceed = Read-HostWithDefault -Prompt "Add to config anyway? (y/N):" -Default "N"
        if ($proceed -notmatch '^[Yy]') { return }
    }
    Add-SSHKeyToHostConfig -KeyName $KeyName -RemoteHostName $hostName -RemoteHostAddress $RemoteHostAddress -RemoteUser $RemoteUser
}

function _MenuDeleteLocalKey {       # choice 8 — optionally remove from remote(s), then delete local key files
    Show-OpBanner @("ssh dir", "$env:USERPROFILE\.ssh")
    $KeyName = Read-SSHKeyName
    if (-not $KeyName) { return }

    $keyHosts = Get-HostsUsingKey -KeyName $KeyName

    if ($keyHosts.Count -gt 0) {
        $allLabel   = "-- ALL  ($($keyHosts.Count) host$(if ($keyHosts.Count -ne 1){'s'}))"
        $hostLabels = @($allLabel) + @($keyHosts | ForEach-Object {
            if ($_.HostName) { "$($_.Alias)  ($($_.HostName))" } else { $_.Alias }
        })
        $selectedHost = $null
        try { $selectedHost = Select-FromList -Items $hostLabels -Prompt "Remove key from remote host(s)  (Esc = skip remote)" }
        catch [System.OperationCanceledException] { $selectedHost = $null }

        $targetsToRemove = if ($selectedHost -and $selectedHost.StartsWith("--")) {
            $keyHosts
        } elseif ($selectedHost) {
            $alias = ($selectedHost -split '\s+\(')[0].Trim()
            @($keyHosts | Where-Object { $_.Alias -eq $alias })
        } else { @() }

        foreach ($h in $targetsToRemove) {
            $rUser = if ($h.User) { $h.User } else { $DefaultUserName }
            $rHost = if ($h.HostName) { $h.HostName } else { $h.Alias }
            Write-Out 'dim' "Removing key from $($h.Alias)..."
            Remove-SSHKeyFromRemote -RemoteUser $rUser -RemoteHost $rHost -KeyName $KeyName
        }
    } else {
        Write-Out 'dim' "No configured hosts reference this key."
    }

    $privPath = "$env:USERPROFILE\.ssh\$KeyName"
    $pubPath  = "$privPath.pub"
    $deleted  = @()
    if (Test-Path $privPath) { Remove-Item $privPath -Force; $deleted += $privPath }
    if (Test-Path $pubPath)  { Remove-Item $pubPath  -Force; $deleted += $pubPath  }
    if ($deleted.Count -gt 0) {
        $deleted | ForEach-Object { Write-Out 'ok' "Deleted: $_" }
        Write-Out 'ok' "Key '$KeyName' removed locally."
    } else {
        Write-Out 'warn' "No local key files found for '$KeyName'."
    }
}

function _MenuRemoveKeyFromConfig {  # choice 9 — pick host then IdentityFile entry, remove that line from config block
    Show-OpBanner @("config", "$env:USERPROFILE\.ssh\config")
    $allHosts = Get-ConfiguredSSHHosts
    if ($allHosts.Count -eq 0) {
        Write-Out 'dim' "No configured hosts found in ~/.ssh/config."
        return
    }
    $hostName = Select-FromList -Items @($allHosts | ForEach-Object { $_.Alias }) -Prompt "Select host:" -StrictList
    if (-not $hostName) { return }

    $configRaw = Get-Content "$env:USERPROFILE\.ssh\config" -Raw -Encoding UTF8
    $hostEsc   = [regex]::Escape($hostName)
    $block     = [regex]::Match($configRaw, "(?ms)^Host\s+$hostEsc\b.*?(?=^Host\s|\z)").Value
    $keyNames  = @([regex]::Matches($block, '(?m)^\s*IdentityFile\s+(.+?)\s*$') |
                   ForEach-Object { [System.IO.Path]::GetFileName($_.Groups[1].Value.Trim().Trim('"')) })

    if ($keyNames.Count -eq 0) {
        Write-Out 'dim' "No IdentityFile entries found under host '$hostName'."
        return
    }
    $KeyName = Select-FromList -Items $keyNames -Prompt "Select key to remove from '$hostName':"
    if (-not $KeyName) { return }

    Remove-IdentityFileFromConfigEntry -KeyName $KeyName -RemoteHostName $hostName
}

function _MenuShowBestPractices {    # choice 10 — 4-rule key-naming guide; no interactive input
    Write-Host ""
    Write-Out 'info' "Best Practices"
    Write-Out 'dim'  "--------------"
    Write-Out 'info' "1. CTs demo'd over LAN         -> shared key (e.g. demo-lan)"
    Write-Out 'info' "2. CTs in development over LAN -> shared key (e.g. dev-lan)"
    Write-Out 'info' "3. CTs promoted into the stack -> shared key (e.g. prod-lan)"
    Write-Out 'error' "4. CTs accessed over the WAN   -> individual key (e.g. sonarr-wan)"
}

function _MenuConfDefaults {         # choice 11 — inline TUI for editing DEFAULT_* globals; shows 4 copy-paste launch commands
    $fieldDefs = @(
        @{ Name = "DefaultUserName";      Label = "Default Username      " }
        @{ Name = "DefaultSubnetPrefix";  Label = "Default Subnet Prefix " }
        @{ Name = "DefaultCommentSuffix"; Label = "Default Comment Suffix" }
        @{ Name = "DefaultPassword";      Label = "Default Password      " }
    )
    $confSel = 0
    $confRun = $true
    [Console]::Write("`e[?25l")

    while ($confRun) {
        $tw = $Host.UI.RawUI.WindowSize.Width
        $th = $Host.UI.RawUI.WindowSize.Height
        $rule  = ([char]0x2500).ToString() * [Math]::Max(0, $tw - 4)
        $title = "Conf: Global Defaults"
        $tpad  = " " * [Math]::Max(0, [int](($tw - 4 - $title.Length) / 2))
        $cf  = "`e[2J`e[H"
        $cf += "`e[2;1H  `e[96m$rule`e[0m`e[K"
        $cf += "`e[3;1H  `e[96m$tpad$title`e[0m`e[K"
        $cf += "`e[4;1H  `e[96m$rule`e[0m`e[K"
        for ($i = 0; $i -lt $fieldDefs.Count; $i++) {
            $val  = (Get-Variable -Name $fieldDefs[$i].Name -Scope Script -ErrorAction SilentlyContinue).Value
            $disp = if ($fieldDefs[$i].Name -eq "DefaultPassword" -and $val) { "*" * $val.Length } else { $val }
            $row  = 6 + $i
            $cf  += "`e[$row;1H"
            if ($i -eq $confSel) {
                $cf += "  `e[7m  $($fieldDefs[$i].Label)  $disp`e[K`e[0m"
            } else {
                $cf += "  `e[0;37m    $($fieldDefs[$i].Label)  `e[90m$disp`e[0m`e[K"
            }
        }

        # ── Persist commands (4 methods) ────────────────────────────────────
        $rawUrl = "https://raw.githubusercontent.com/ahmadhadidi/ssh-key-manager/refs/heads/main"
        $bf = ""; $pf = ""
        $uVal = (Get-Variable -Name "DefaultUserName"      -Scope Script -EA SilentlyContinue).Value
        $sVal = (Get-Variable -Name "DefaultSubnetPrefix"  -Scope Script -EA SilentlyContinue).Value
        $cVal = (Get-Variable -Name "DefaultCommentSuffix" -Scope Script -EA SilentlyContinue).Value
        $pVal = (Get-Variable -Name "DefaultPassword"      -Scope Script -EA SilentlyContinue).Value
        if ($uVal) { $bf += " --user `"$uVal`"";           $pf += " -DefaultUserName `"$uVal`"" }
        if ($sVal) { $bf += " --subnet `"$sVal`"";         $pf += " -DefaultSubnetPrefix `"$sVal`"" }
        if ($cVal) { $bf += " --comment-suffix `"$cVal`""; $pf += " -DefaultCommentSuffix `"$cVal`"" }
        if ($pVal) { $bf += " --password `"$pVal`"";       $pf += " -DefaultPassword `"$pVal`"" }

        $maxCw = $tw - 6
        $c1 = "bash <(curl -fsSL $rawUrl/hddssh.sh)$bf"
        $c2 = "bash hddssh.sh$bf"
        $c3 = "`$sb=[scriptblock]::Create((irm `"$rawUrl/hddssh.ps1`")); & `$sb$pf"
        $c4 = "& ./hddssh.ps1$pf"
        if ($c1.Length -gt $maxCw) { $c1 = $c1.Substring(0, $maxCw - 3) + "..." }
        if ($c2.Length -gt $maxCw) { $c2 = $c2.Substring(0, $maxCw - 3) + "..." }
        if ($c3.Length -gt $maxCw) { $c3 = $c3.Substring(0, $maxCw - 3) + "..." }
        if ($c4.Length -gt $maxCw) { $c4 = $c4.Substring(0, $maxCw - 3) + "..." }

        $cf += "`e[11;1H`e[K"
        $cf += "`e[12;1H  `e[90mTo persist across sessions:`e[0m`e[K"
        $cf += "`e[13;1H`e[K"
        $cf += "`e[14;1H  `e[90m`u{2601}`u{FE0F}  Bash `u{00B7} cloud`e[0m`e[K"
        $cf += "`e[15;1H    `e[33m$c1`e[0m`e[K"
        $cf += "`e[16;1H  `e[90m`u{1F3E0}  Bash `u{00B7} local`e[0m`e[K"
        $cf += "`e[17;1H    `e[33m$c2`e[0m`e[K"
        $cf += "`e[18;1H`e[K"
        $cf += "`e[19;1H  `e[90m`u{2601}`u{FE0F}  PowerShell `u{00B7} cloud`e[0m`e[K"
        $cf += "`e[20;1H    `e[36m$c3`e[0m`e[K"
        $cf += "`e[21;1H  `e[90m`u{1F3E0}  PowerShell `u{00B7} local`e[0m`e[K"
        $cf += "`e[22;1H    `e[36m$c4`e[0m`e[K"

        $hint = "  Up/Dn  navigate     Enter  edit     Q  back  "
        $cf += "`e[$th;1H`e[7m$hint$(" " * [Math]::Max(0, $tw - $hint.Length))`e[0m"
        [Console]::Write($cf)

        try { $k = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") } catch { break }

        switch ($k.VirtualKeyCode) {
            38 { $confSel = ($confSel - 1 + $fieldDefs.Count) % $fieldDefs.Count }
            40 { $confSel = ($confSel + 1) % $fieldDefs.Count }
            13 {
                $row = 6 + $confSel
                [Console]::Write("`e[$row;1H`e[K  `e[1;33m> $($fieldDefs[$confSel].Label)  `e[0;33m")
                [Console]::Write("`e[?25h")
                $newVal = Read-Host
                [Console]::Write("`e[?25l")
                if (![string]::IsNullOrWhiteSpace($newVal)) {
                    Set-Variable -Name $fieldDefs[$confSel].Name -Value $newVal -Scope Script
                }
            }
        }
        if ($k.Character -eq 'q' -or $k.Character -eq 'Q') { $confRun = $false }
    }

    [Console]::Write("`e[?25h")
    Write-Host ""
    Write-Out 'ok'   "Defaults updated for this session."
    Write-Out 'warn' "To persist: pass as script parameters (-DefaultUserName, etc.)"
    return $true
}

function _MenuRemoveHost {           # choice 12 — remove entire Host block from ~/.ssh/config
    Remove-HostFromSSHConfig
}

function _MenuViewConfig {           # choice 13 — paginated SSH config viewer
    Show-SSHConfigFile
    return $true
}

function _MenuEditConfig {           # choice 14 — open config in editor
    Edit-SSHConfigFile
    return $true
}

function _MenuListAuthorizedKeys {   # choice 16 — SSH to target, fetch authorized_keys, display numbered list
    Show-OpBanner @("host", $env:COMPUTERNAME, "user", $DefaultUserName)
    Invoke-RemotePrompt
    $RemoteHostAddress = $script:_RemoteHost
    $RemoteUser        = $script:_RemoteUser
    $target = Resolve-SSHTarget -RemoteHostAddress $RemoteHostAddress -RemoteUser $RemoteUser
    Write-Out 'dim' "Fetching authorized_keys from $target..."
    Write-SSHFence $target
    try {
        $keys = ssh $target "cat ~/.ssh/authorized_keys 2>/dev/null"
        Write-SSHFenceClose
        if (-not $keys) {
            Write-Out 'dim' "No authorized_keys found on $target."
        } else {
            Write-Host "  `e[1;37mAuthorized keys on ${target}:`e[0m"
            $i = 1
            $keys -split "`n" | Where-Object { $_.Trim() } | ForEach-Object {
                Write-Host "  `e[90m$($i.ToString().PadLeft(3))`e[0m  `e[36m$_`e[0m"
                $i++
            }
        }
    } catch {
        Write-SSHFenceClose
        Write-Out 'error' "Failed to fetch authorized_keys: $($_.Exception.Message)"
    }
}

function _MenuAddConfigBlock {       # choice 17 — read remote auth_keys, create host config entry
    Show-OpBanner @("host", $env:COMPUTERNAME, "config", "$env:USERPROFILE\.ssh\config")
    Register-RemoteHostConfig
}

function _MenuImportKey {            # choice 18 — import from local path, SCP, or paste
    Show-OpBanner @("host", $env:COMPUTERNAME, "ssh dir", "$env:USERPROFILE\.ssh")
    Import-ExternalSSHKey
}
