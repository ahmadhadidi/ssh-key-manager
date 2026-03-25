param(
  [string]$DefaultUserName = "default_non_root_username",
  [string]$DefaultSubnetPrefix = "192.168.0",
  [string]$DefaultCommentSuffix = "-[my-machine]"
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Wait-UserAcknowledge {
    # Pin the prompt to the last terminal row as a status-bar style message.
    $h = $Host.UI.RawUI.WindowSize.Height
    [Console]::Write("`e[$h;1H`e[0m`e[7m  Press Enter to return to menu  `e[0m`e[K")
    try {
        do { $k = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") } while ($k.VirtualKeyCode -ne 13)
    } catch {
        $null = Read-Host
    }
}


function Show-Paged {
    param([string[]]$Lines)

    try { $pageSize = [Math]::Max(5, $Host.UI.RawUI.WindowSize.Height - 4) }
    catch { $pageSize = 20 }

    $total = $Lines.Count
    $i = 0

    while ($i -lt $total) {
        $end = [Math]::Min($i + $pageSize - 1, $total - 1)
        $Lines[$i..$end] | ForEach-Object { Write-Host $_ }
        $i += $pageSize

        if ($i -lt $total) {
            Write-Host "-- $i/$total lines shown | Enter=more, Q=quit --" -ForegroundColor DarkGray -NoNewline
            try {
                $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                Write-Host ""
                if ($key.Character -eq 'q' -or $key.Character -eq 'Q') { break }
            } catch {
                $null = Read-Host
            }
        }
    }
}


function Show-MainMenu {
    $menuDef = @(
        [pscustomobject]@{ Type = "header"; Label = "Remote" }
        [pscustomobject]@{ Type = "item";   Label = "Generate & Install SSH Key on A Remote Machine"; Choice = "1" }
        [pscustomobject]@{ Type = "item";   Label = "Test SSH Connection";                            Choice = "2" }
        [pscustomobject]@{ Type = "item";   Label = "Delete SSH Key From A Remote Machine";           Choice = "3" }
        [pscustomobject]@{ Type = "item";   Label = "Promote Key on A Remote Machine";                Choice = "4" }
        [pscustomobject]@{ Type = "header"; Label = "Local" }
        [pscustomobject]@{ Type = "item";   Label = "Generate SSH Key (Without installation)";        Choice = "5" }
        [pscustomobject]@{ Type = "item";   Label = "List SSH Keys";                                  Choice = "6" }
        [pscustomobject]@{ Type = "item";   Label = "Append SSH Key to Hostname in Host Config";      Choice = "7" }
        [pscustomobject]@{ Type = "item";   Label = "Delete an SSH Key Locally";                      Choice = "8" }
        [pscustomobject]@{ Type = "item";   Label = "Remove an SSH Key From Config";                  Choice = "9" }
        [pscustomobject]@{ Type = "header"; Label = "Config File" }
        [pscustomobject]@{ Type = "item";   Label = "Remove Host from SSH Config";                    Choice = "12" }
        [pscustomobject]@{ Type = "item";   Label = "View SSH Config";                                Choice = "13" }
        [pscustomobject]@{ Type = "item";   Label = "Edit SSH Config";                                Choice = "14" }
        [pscustomobject]@{ Type = "header"; Label = "🌊" }
        [pscustomobject]@{ Type = "item";   Label = "Help: Best Practices";                           Choice = "10" }
        [pscustomobject]@{ Type = "item";   Label = "Conf: Global Defaults";                          Choice = "11" }
        [pscustomobject]@{ Type = "item";   Label = "Exit";                                           Choice = "q" }
    )

    $navItems   = @($menuDef | Where-Object { $_.Type -eq "item" })
    $sel        = 0
    $prevSel    = -1
    $itemRows   = @{}
    $needFull   = $true
    $running    = $true
    $termWidth  = 0
    $termHeight = 0

    [Console]::Write("`e[?1049h`e[?25l")

    try {
        while ($running) {

            # ── Full render ────────────────────────────────────────────────────────
            if ($needFull) {
                $termWidth  = $Host.UI.RawUI.WindowSize.Width
                $termHeight = $Host.UI.RawUI.WindowSize.Height

                $f  = "`e[2J`e[H`n"
                $f += "  `e[96m=====================================================`e[0m`n"
                $f += "  `e[96m             🌊  HDD SSH Keys                       `e[0m`n"
                $f += "  `e[96m=====================================================`e[0m`n"

                $row  = 5
                $nIdx = 0
                $itemRows = @{}

                foreach ($entry in $menuDef) {
                    if ($entry.Type -eq "header") {
                        $f   += "`n  `e[90m  ▸ `e[1m$($entry.Label)`e[0m`n"
                        $row += 2
                    } else {
                        $itemRows[$nIdx] = $row
                        if ($nIdx -eq $sel) {
                            $f += "  `e[1;36m▶ $($entry.Label)`e[0m`e[K`n"
                        } else {
                            $f += "`e[0m`e[37m    $($entry.Label)`e[0m`e[K`n"
                        }
                        $nIdx++
                        $row++
                    }
                }

                # Status bar pinned to last row; ESC[K before ESC[0m fills full width.
                $f += "`e[$termHeight;1H`e[7m  ↑↓ / Home / End  navigate     Enter  select     Q  quit  `e[K`e[0m"

                [Console]::Write($f)
                $prevSel  = $sel
                $needFull = $false

            # ── Differential update ────────────────────────────────────────────────
            } elseif ($prevSel -ne $sel) {
                $r = $itemRows[$prevSel]
                [Console]::Write("`e[${r};1H`e[0m`e[37m    $($navItems[$prevSel].Label)`e[0m`e[K")
                $r = $itemRows[$sel]
                [Console]::Write("`e[${r};1H  `e[1;36m▶ $($navItems[$sel].Label)`e[0m`e[K")
                $prevSel = $sel
            }

            # ── Poll for input — detects resize while idle ─────────────────────────
            $key = $null
            while ($null -eq $key) {
                $available = $false
                try { $available = $Host.UI.RawUI.KeyAvailable } catch {}
                if ($available) {
                    $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                } else {
                    $newW = $Host.UI.RawUI.WindowSize.Width
                    $newH = $Host.UI.RawUI.WindowSize.Height
                    if ($newW -ne $termWidth -or $newH -ne $termHeight) {
                        $termWidth  = $newW
                        $termHeight = $newH
                        $needFull   = $true
                        break
                    }
                    Start-Sleep -Milliseconds 50
                }
            }

            if ($null -eq $key) { continue }   # resize detected — redraw, no key to process

            switch ($key.VirtualKeyCode) {
                38  { $sel = ($sel - 1 + $navItems.Count) % $navItems.Count }  # Up
                40  { $sel = ($sel + 1) % $navItems.Count }                     # Down
                36  { $sel = 0 }                                                 # Home
                35  { $sel = $navItems.Count - 1 }                              # End
                13  {                                                            # Enter
                    $choice = $navItems[$sel].Choice
                    if ($choice -eq 'q') {
                        $running = $false
                    } else {
                        $opLabel = $navItems[$sel].Label
                        $rule    = "─" * [Math]::Max(0, $termWidth - 4)
                        $f  = "`e[2J`e[H`e[?25h`n"
                        $f += "  `e[1;97m$opLabel`e[0m`n"
                        $f += "  `e[90m$rule`e[0m`n`n"
                        [Console]::Write($f)
                        Invoke-MenuChoice -Choice $choice
                        Wait-UserAcknowledge
                        [Console]::Write("`e[?25l")
                        $needFull = $true
                    }
                }
            }

            if ($key.Character -eq 'q' -or $key.Character -eq 'Q') {
                $running = $false
            }
        }
    } finally {
        [Console]::Write("`e[?25h`e[?1049l")
    }
}


function Invoke-MenuChoice {
    param([string]$Choice)

    switch ($Choice) {
        "1" {
            Write-Host "`n"
            $KeyName = Read-SSHKeyName
            Deploy-SSHKeyToRemote -KeyName $KeyName
        }
        "2" {
            $RemoteUser = Read-RemoteUser -DefaultUser "$DefaultUserName"
            $RemoteHost = Read-RemoteHostAddress -SubnetPrefix "$DefaultSubnetPrefix"
            Test-SSHConnection -RemoteUser $RemoteUser -RemoteHost $RemoteHost
        }
        "3" {
            $KeyName = Read-SSHKeyName
            $RemoteHost = Read-RemoteHostAddress -SubnetPrefix "$DefaultSubnetPrefix"
            $RemoteUser = Read-RemoteUser -DefaultUser "$DefaultUserName"
            Remove-SSHKeyFromRemote -RemoteUser $RemoteUser -RemoteHost $RemoteHost -KeyName $KeyName
        }
        "4" {
            Deploy-PromotedKey
        }
        "5" {
            $KeyName = Read-SSHKeyName
            $Comment = Read-SSHKeyComment -DefaultComment "$KeyName$DefaultCommentSuffix"
            Add-SSHKeyInHost -KeyName $KeyName -Comment $Comment
        }
        "6" {
            Show-SSHKeyInventory
        }
        "7" {
            $KeyName           = Read-SSHKeyName
            $RemoteHostName    = Read-RemoteHostName -SubnetPrefix "$DefaultSubnetPrefix"
            $RemoteHostAddress = Read-RemoteHostAddress -SubnetPrefix "$DefaultSubnetPrefix"
            $RemoteUser        = Read-RemoteUser -DefaultUser "$DefaultUserName"
            Add-SSHKeyToHostConfig -KeyName $KeyName -RemoteHostName $RemoteHostName -RemoteHostAddress $RemoteHostAddress -RemoteUser $RemoteUser
        }
        "8" {
            Write-Host "❌  Not yet implemented!" -ForegroundColor Yellow
            $KeyName = Read-SSHKeyName
            $RemoteHostAddress = Read-RemoteHostAddress -SubnetPrefix "$DefaultSubnetPrefix"
            $RemoteUser = Read-RemoteUser -DefaultUser "$DefaultUserName"
            $RemoteHostName = Read-RemoteHostName -SubnetPrefix "$DefaultSubnetPrefix"
        }
        "9" {
            $KeyName = Read-SSHKeyName
            $RemoteHostName = Read-RemoteHostName -SubnetPrefix "$DefaultSubnetPrefix"
            Remove-IdentityFileFromConfigEntry -KeyName $KeyName -RemoteHostName $RemoteHostName
        }
        "10" {
            Write-Host ""
            Write-Host "  Best Practices" -ForegroundColor Cyan
            Write-Host "  ──────────────" -ForegroundColor DarkGray
            Write-Host "  1. CTs demo'd over LAN         → shared key (e.g. demo-lan)" -ForegroundColor Cyan
            Write-Host "  2. CTs in development over LAN → shared key (e.g. dev-lan)" -ForegroundColor Cyan
            Write-Host "  3. CTs promoted into the stack → shared key (e.g. prod-lan)" -ForegroundColor Cyan
            Write-Host "  4. CTs accessed over the WAN   → individual key (e.g. sonarr-wan)" -ForegroundColor Red
        }
        "11" {
            Write-Host ""
            Write-Host "  `e[1mGlobal Defaults`e[0m" -ForegroundColor Cyan
            Write-Host "  ───────────────" -ForegroundColor DarkGray
            Write-Host "  Leave blank to keep the current value." -ForegroundColor DarkGray
            Write-Host ""

            $newUser = Read-ColoredInput -Prompt "  DefaultUserName     [$DefaultUserName]:" -ForegroundColor "Cyan"
            if (![string]::IsNullOrWhiteSpace($newUser)) { $script:DefaultUserName = $newUser }

            $newPrefix = Read-ColoredInput -Prompt "  DefaultSubnetPrefix [$DefaultSubnetPrefix]:" -ForegroundColor "Cyan"
            if (![string]::IsNullOrWhiteSpace($newPrefix)) { $script:DefaultSubnetPrefix = $newPrefix }

            $newSuffix = Read-ColoredInput -Prompt "  DefaultCommentSuffix [$DefaultCommentSuffix]:" -ForegroundColor "Cyan"
            if (![string]::IsNullOrWhiteSpace($newSuffix)) { $script:DefaultCommentSuffix = $newSuffix }

            Write-Host ""
            Write-Host "  ✅ Defaults updated for this session." -ForegroundColor Green
            Write-Host "  ℹ  To persist: -DefaultUserName / -DefaultSubnetPrefix / -DefaultCommentSuffix" -ForegroundColor Yellow
        }
        "12" { Remove-HostFromSSHConfig }
        "13" { Show-SSHConfigFile }
        "14" { Edit-SSHConfigFile }
    }
}


#region Main Functions
function Deploy-SSHKeyToRemote {
    param (
        [string]$KeyName
    )

    # Check if key exists
    if (-not (Find-PrivateKeyInHost -KeyName $KeyName -ReturnResult $true)) {
        Write-Host "`n🔑 Key does not exist. Generating..." -ForegroundColor Yellow
        
        $Comment = Read-SSHKeyComment -DefaultComment "$KeyName$DefaultCommentSuffix"

        Add-SSHKeyInHost -KeyName $KeyName -Comment $Comment

    } else {
        Write-Host "`nℹ  Key already exists. Proceeding with installation...`n" -ForegroundColor Cyan
    }

    # Get the public key entered locally
    # $PublicKeyPath = Get-PublicKeyInHost -KeyName $KeyName
    $PublicKey = Get-PublicKeyInHost -KeyName $KeyName
    
    # Prompt the user for the remote host and username
    $RemoteHostAddress = Read-RemoteHostAddress -SubnetPrefix "$DefaultSubnetPrefix"
    $RemoteUser = Read-RemoteUser -DefaultUser "$DefaultUserName"

    $target = Resolve-SSHTarget -RemoteHostAddress $RemoteHostAddress -RemoteUser $RemoteUser
    Write-Host "🔃 Connecting to $target..."

    try {
        $RemoteHostName = $PublicKey | ssh $target 'mkdir -p .ssh && cat >> .ssh/authorized_keys && hostname'
        # type "$PublicKeyPath" | ssh "$RemoteUser@$RemoteHost" "mkdir -p .ssh && cat >> .ssh/authorized_keys"
        Write-Host "✅ SSH Public Key installed successfully." -ForegroundColor Green

        # Ask the user what to call this Host in the config, defaulting to the
        # actual hostname reported by the remote machine.
        Write-Host "🏷  Remote hostname is: $RemoteHostName" -ForegroundColor DarkGray
        $hostAlias = Read-ColoredInput -Prompt "  Name this Host in ~/.ssh/config (default: $RemoteHostName):" -ForegroundColor "Cyan"
        if ([string]::IsNullOrWhiteSpace($hostAlias)) { $hostAlias = $RemoteHostName }

        Write-Host "Registering key to SSH config as '$hostAlias'..."
        Add-SSHKeyToHostConfig -KeyName $KeyName -RemoteHostAddress $RemoteHostAddress -RemoteHostName $hostAlias -RemoteUser $RemoteUser
    } catch {
        Write-Host "❌ Failed to inject SSH key. Check network, credentials, or host status." -ForegroundColor Red
    }
}

function Test-SSHConnection {
    param (
        [string]$RemoteUser,
        [string]$RemoteHost,
        [switch]$ReturnResult
    )

    $target = Resolve-SSHTarget -RemoteHostAddress $RemoteHost -RemoteUser $RemoteUser

    try {
        $result = ssh $target "echo SSH Connection Successful" 2>&1

        if ($result -match "ssh: connect to host .* port 22: Connection refused") {
            Write-Host "❌ Connection refused: $RemoteHost is not accepting SSH connections." -ForegroundColor Red
            Write-Host "`n"
            if ($ReturnResult) { return $false } else { return }
        }
        elseif ($result -match "Name or service not known" -or $result -match "Could not resolve hostname") {
            Write-Host "❌ DNS error: Could not resolve $RemoteHost." -ForegroundColor Red
            Write-Host "`n"
            if ($ReturnResult) { return $false } else { return }
        }
        elseif ($result -match "Permission denied") {
            Write-Host "⚠️ SSH reachable, but permission denied for user '$RemoteUser'." -ForegroundColor Yellow
            Write-Host "`n"
            if ($ReturnResult) { return $true } else { return }  # SSH is reachable, credentials just need fixing
        }
        else {
            Write-Host "✅ SSH connection to $RemoteHost is successful." -ForegroundColor Green
            Write-Host "`n"
            if ($ReturnResult) { return $true } else { return }
        }

    } catch {
        Write-Host "❌ Unexpected error during SSH test:" -ForegroundColor Red
        Write-Host $_.Exception.Message
        if ($ReturnResult) { return $false } else { return }
    }
}


function Remove-SSHKeyFromRemote {
    param (
        [string]$RemoteUser,
        [string]$RemoteHost,
        [string]$KeyName
    )

    $PublicKey = Get-PublicKeyInHost -KeyName $KeyName

    # # Read the full public key content
    # $PublicKey = Get-Content $PublicKeyPath -Raw

    # I will do it with AWK
    $RemoteCommand = "TMP_FILE=`$(mktemp) && printf '%s`\n' '$PublicKey' > `$TMP_FILE && awk 'NR==FNR { keys[`$0]; next } !(`$0 in keys)' `$TMP_FILE ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.tmp && mv ~/.ssh/authorized_keys.tmp ~/.ssh/authorized_keys && rm -f `$TMP_FILE"

    # Write-Host "`n🐞 HDD-DEBUG:: $RemoteCommand" -ForegroundColor Red
    $target = Resolve-SSHTarget -RemoteHostAddress $RemoteHost -RemoteUser $RemoteUser
    Write-Host "`n🔒 Will connect to remove the public key from $target`:`n$PublicKey`n" -ForegroundColor Yellow

    try {
        ssh $target $RemoteCommand
        # ssh "$RemoteUser@$RemoteHost" "sed -i '/$PublicKeyPath/d' ~/.ssh/authorized_keys"
        Write-Host "✅ SSH key removed from remote authorized_keys." -ForegroundColor Green

        Confirm-UserChoice -Message "Do you want to remove the SSH key from THIS machine? ⚠" -Action {
            Remove-SSHKeyFromRemote -RemoteUser "$DefaultUserName" -RemoteHost "192.168.0.10" -KeyName "demo-lan"
        } -DefaultAnswer "n"
    } catch {
        Write-Host "❌ Failed to remove the SSH key from remote." -ForegroundColor Red
    }
}


function Deploy-PromotedKey {
    Write-Host "Which key do you want to remove?" -ForegroundColor Cyan
    $KeyNameToRemove = Read-SSHKeyName
    $CommentToRemove = Read-SSHKeyComment -DefaultComment "$KeyNameToRemove$DefaultCommentSuffix"

    Write-Host "From which remote machine?" -ForegroundColor Cyan
    $RemoteHostName = Read-RemoteHostName -SubnetPrefix "$DefaultSubnetPrefix"

    # Check if the key is registered as an IdentityFile for this remote host first
    if (Find-SSHKeyInHostConfig -KeyName $KeyNameToRemove -RemoteHostName $RemoteHostName -ReturnResult $true) {
        Write-Host "Replace with which key?" -ForegroundColor Cyan
        $KeyNameNew = Read-SSHKeyName
        Deploy-SSHKeyToRemote -KeyName $KeyNameNew
        $RemoteHostAddress = Get-IPAddressFromHostConfigEntry -RemoteHostName $RemoteHostName
        $RemoteUser = Get-RemoteUserFromConfigEntry -RemoteHostName $RemoteHostName

        Confirm-UserChoice -Message "Do you want to remove the demoted SSH key ($KeyNameToRemove) from the remote machine? ⚠" -Action {
            Remove-SSHKeyFromRemote -RemoteUser $RemoteUser -RemoteHost $RemoteHostAddress -KeyName $KeyNameToRemove
        } -DefaultAnswer "n"

    }
}


function Remove-SSHKeyLocally {
    # 🚧 TODO: lessa ma itgayyaf
    $KeyName = Read-SSHKeyName

    $PrivateKeyPath = "$env:USERPROFILE\.ssh\$KeyName"
    $PublicKeyPath = "$env:USERPROFILE\.ssh\$KeyName.pub"

    $ConfigPath = Find-ConfigFileOnHost
    if (-not $ConfigPath) {
        Write-Host "⚠️ SSH config file not found. Skipping config check." -ForegroundColor Yellow
    }

    # Step 1: Look for IdentityFile matches in the config file
    $HostsUsingKey = @()
    if ($ConfigPath) {
        $ConfigLines = Get-Content $ConfigPath
        $CurrentHost = $null

        foreach ($line in $ConfigLines) {
            if ($line -match '^\s*Host\s+(.+)$') {
                $CurrentHost = $Matches[1].Trim()
            }
            elseif ($line -match '^\s*IdentityFile\s+(.+)$') {
                $IdentityPath = $Matches[1].Trim().Replace("`$HOME", $env:USERPROFILE)
                if ($IdentityPath -eq $PrivateKeyPath) {
                    $HostsUsingKey += $CurrentHost
                }
            }
        }
    }

    # Step 2: If used, list hosts and confirm
    if ($HostsUsingKey.Count -gt 0) {
        Write-Host "`n🔐 The following SSH config Host entries are using this key:" -ForegroundColor Yellow
        $HostsUsingKey | ForEach-Object { Write-Host "  - $_" }

        $confirm = Read-Host "Are you sure you want to delete the key '$KeyName'? (y/n)"
        if ($confirm -notmatch '^(y|yes)$') {
            Write-Host "❌ Deletion cancelled." -ForegroundColor Yellow
            return
        }
    }

    # Step 3: Delete the key files
    if (Test-Path $PrivateKeyPath) {
        Remove-Item $PrivateKeyPath -Force
        Write-Host "🗑️ Deleted: $PrivateKeyPath" -ForegroundColor Green
    }

    if (Test-Path $PublicKeyPath) {
        Remove-Item $PublicKeyPath -Force
        Write-Host "🗑️ Deleted: $PublicKeyPath" -ForegroundColor Green
    }

    if (-not (Test-Path $PrivateKeyPath) -and -not (Test-Path $PublicKeyPath)) {
        Write-Host "`n✅ SSH key '$KeyName' deleted successfully." -ForegroundColor Green
    } else {
        Write-Host "`n⚠️ Some key files could not be deleted. Please check permissions." -ForegroundColor Red
    }
}


function Remove-IdentityFileFromConfigEntry {
    param (
        [Parameter(Mandatory)]
        [string]$KeyName,

        [Parameter(Mandatory)]
        [string]$RemoteHostName
    )

    $ConfigPath = "$env:USERPROFILE\.ssh\config"

    if (-not (Test-Path $ConfigPath)) {
        Write-Host "❌ SSH config not found at $ConfigPath" -ForegroundColor Red
        return
    }

    $config = Get-Content -Path $ConfigPath -Raw -Encoding UTF8

    # Match the full Host block
    $pattern = "(?ms)^Host\s+$RemoteHostName\b.*?(?=^Host\s|\z)"
    $match = [regex]::Match($config, $pattern)

    if (-not $match.Success) {
        Write-Host "⚠️ No Host block found for '$RemoteHostName'" -ForegroundColor Yellow
        return
    }

    $block = $match.Value
    $escapedKey = [regex]::Escape($KeyName)

    # Match any IdentityFile line ending in the key
    $identityPattern = "^\s*IdentityFile\s+.*[\\/]" + $escapedKey + "(\s*)$"

    $lines = $block -split "`n"
    $newLines = $lines | Where-Object { $_ -notmatch $identityPattern }

    if ($lines.Count -eq $newLines.Count) {
        Write-Host "ℹ️ No IdentityFile ending in '$KeyName' was found under Host '$RemoteHostName'" -ForegroundColor Yellow
        return
    }

    $newBlock = $newLines -join "`n"
    $newConfig = $config -replace [regex]::Escape($block), $newBlock

    Set-Content -Path $ConfigPath -Value $newConfig -Encoding UTF8
    Write-Host "✅ IdentityFile '$KeyName' removed from Host '$RemoteHostName'" -ForegroundColor Green
}


function Show-SSHKeyInventory {
    param(
        [string]$SshDir = "$env:USERPROFILE\.ssh",
        [string]$ConfigPath = "$env:USERPROFILE\.ssh\config"
    )

    if (-not (Test-Path $SshDir)) {
        Write-Host "❌ .ssh directory not found at $SshDir" -ForegroundColor Red
        return
    }

    # ----------------------------
    # 1) Inventory keys from .ssh/
    # ----------------------------
    $allFiles = Get-ChildItem -Path $SshDir -File -ErrorAction SilentlyContinue

    # Public keys are *.pub
    $pubFiles = $allFiles | Where-Object { $_.Extension -ieq ".pub" }

    # Private keys: common exclusions + not *.pub
    # (We keep this conservative; if a file is referenced as IdentityFile later, it will also be included in usage map.)
    $excludeNames = @(
        "config", "known_hosts", "known_hosts.old", "authorized_keys",
        "authorized_keys2", "environment", "rc"
    )

    $privateCandidates = $allFiles | Where-Object {
        $_.Extension -ine ".pub" -and
        ($excludeNames -notcontains $_.Name.ToLowerInvariant())
    }

    # Build key name sets
    $pubKeyNames = $pubFiles | ForEach-Object { $_.BaseName }
    $privKeyNames = $privateCandidates | ForEach-Object { $_.Name }

    $allKeyNames = @($pubKeyNames + $privKeyNames) | Sort-Object -Unique

    # ----------------------------
    # 2) Parse config usage map
    # ----------------------------
    $usageMap = @{}  # keyName -> HashSet(hosts)

    if (Test-Path $ConfigPath) {
        $config = Get-Content -Path $ConfigPath -Raw -Encoding UTF8

        # Each Host block
        $hostBlockPattern = "(?ms)^Host\s+(.+?)\s*$.*?(?=^Host\s|\z)"
        $hostBlocks = [regex]::Matches($config, $hostBlockPattern)

        foreach ($hb in $hostBlocks) {
            $hostHeader = $hb.Groups[1].Value.Trim()
            $block = $hb.Value

            # Host line can include multiple aliases: "Host a b c"
            $hosts = $hostHeader -split '\s+' | Where-Object { $_ }

            # IdentityFile lines
            $identityMatches = [regex]::Matches($block, '(?m)^\s*IdentityFile\s+(.+?)\s*$')
            foreach ($im in $identityMatches) {
                $rawPath = $im.Groups[1].Value.Trim().Trim('"')

                # Normalize `$HOME` / `~`
                $p = $rawPath
                $p = $p -replace '^\~', $env:USERPROFILE
                $p = $p -replace '^\$HOME', $env:USERPROFILE
                $p = $p -replace '^\`$HOME', $env:USERPROFILE

                # Convert to full path if relative (rare, but possible)
                if (-not [System.IO.Path]::IsPathRooted($p)) {
                    $p = Join-Path $SshDir $p
                }

                $keyName = [System.IO.Path]::GetFileName($p)

                if (-not $usageMap.ContainsKey($keyName)) {
                    $usageMap[$keyName] = New-Object System.Collections.Generic.HashSet[string]
                }

                foreach ($h in $hosts) { [void]$usageMap[$keyName].Add($h) }
            }
        }
    }

    # ----------------------------
    # 3) Build output rows
    # ----------------------------
    $rows = @()
    $i = 1

    foreach ($keyName in $allKeyNames) {
        $privatePath = Join-Path $SshDir $keyName
        $publicPath  = "$privatePath.pub"

        $privateOk = Test-Path $privatePath -PathType Leaf
        $publicOk  = Test-Path $publicPath -PathType Leaf

        $usage = ""
        if ($usageMap.ContainsKey($keyName)) {
            $usage = ($usageMap[$keyName] | Sort-Object) -join ", "
        }

        $rows += [pscustomobject]@{
            "#"       = $i
            "Key"     = $keyName
            "Public"  = $(if ($publicOk) { "✅" } else { "❌" })
            "Private" = $(if ($privateOk) { "✅" } else { "❌" })
            "Usage"   = $usage
        }

        $i++
    }

    if ($rows.Count -eq 0) {
        Write-Host "ℹ️ No key files found in $SshDir" -ForegroundColor Yellow
        return
    }

    $tableLines = ($rows | Format-Table -AutoSize | Out-String) -split "`r?`n"
    Show-Paged -Lines $tableLines
}
#endregion


#region Subfunctions
function Add-SSHKeyInHost {
    param (
        [string]$KeyName,
        [string]$Comment
    )

    # Avoid scoping problems
    $Password = Read-ColoredInput -Prompt "Enter the passphrase (leave empty for a passwordless key)" -ForegroundColor "Cyan"

    Write-Host "`n ---> KeyName is: >$KeyName< | Comment is: >$Comment< | Password is: >$Password<`n" -ForegroundColor "Yellow"
    Write-Host "Generating SSH key...`n" -ForegroundColor "Yellow"

    # Build the initial ssh-keygen command
    $sshKeygenCmd = "ssh-keygen -t ed25519 -f `"$env:USERPROFILE\.ssh\$KeyName`" -C `"$Comment`""

    # If the user enters a password, we append it using the -N argument.
    if ($Password -ne "") {
        $sshKeygenCmd += " -N `"$Password`""
    }

    # If the user wants a passwordless key, we enter the -N argument as empty
    if ($Password -eq "") {
        $sshKeygenCmd += " -N ''"
    }

    # DEBUG: Write-Host $sshKeygenCMD
    
    # Call the complete command
    Invoke-Expression $sshKeygenCmd

    Write-Host "SSH key generated: $env:USERPROFILE\.ssh\$KeyName" -ForegroundColor "Green"
}


function Add-SSHKeyToHostConfig {
    param (
        [string]$KeyName,
        [string]$RemoteHostName,
        [string]$RemoteHostAddress,
        [string]$RemoteUser
    )

    $keyPath = "$env:USERPROFILE\.ssh\$KeyName"
    $identityLine = "    IdentityFile $keyPath"

    # Check for key existence first
    if (Find-PrivateKeyInHost -KeyName $KeyName -ReturnResult $true) {
        $sshConfig = Find-ConfigFileOnHost

        # Read the entire config as text
        $config = Get-Content -Path $sshConfig -Raw -Encoding UTF8
        $hostPattern = "(?ms)^Host\s+$RemoteHostName\b.*?(?=^Host\s|\z)"
        $match = [regex]::Match($config, $hostPattern)

        if ($match.Success) {
            $block = $match.Value

            if ($block -notmatch [regex]::Escape($identityLine.Trim())) {
                # Insert IdentityFile line
                $lines = $block -split "`n"
                $insertIndex = ($lines |
                Select-String '^\s*IdentityFile\b' |
                Select-Object -Last 1).LineNumber

                if ($insertIndex) {
                    $lines = $lines[0..($insertIndex - 1)] + $identityLine + $lines[$insertIndex..($lines.Count - 1)]
                } else {
                    $lines = $lines[0..0] + $identityLine + $lines[1..($lines.Count - 1)]
                }

                $newBlock = ($lines -join "`n")

                # Replace raw string — DO NOT ESCAPE the new block
                $newConfig = $config -replace [regex]::Escape($block), $newBlock

                # Write back the file safely
                Set-Content -Path $sshConfig -Value $newConfig -Encoding UTF8

                Write-Host "✅ IdentityFile added to existing Host $RemoteHostName." -ForegroundColor Green
            } else {
                Write-Host "⚠  IdentityFile already exists under Host $RemoteHostName." -ForegroundColor Yellow
            }

        } else {
            # Create new host entry
            $hostEntry = @"
Host $RemoteHostName
    HostName $RemoteHostAddress
    User $RemoteUser
    IdentityFile $keyPath
"@

            Add-Content -Path $sshConfig -Value $hostEntry
            Write-Host "✅ SSH config block created for $RemoteHostName." -ForegroundColor Green
            Write-Host "Now you can connect by typing: ssh $RemoteHostName" -ForegroundColor Cyan
        }

    } else {
        Write-Host "❌ Could not find private SSH Key at $keyPath" -ForegroundColor Red
    }
}


function Disable-SSHRootLogin {
    pass
    # 🚧 TODO: calls sed on /etc/ssh/sshd_config
}

function Invoke-SSHWithKeyThenPassword {
    param(
        [Parameter(Mandatory)]
        [string]$RemoteUser,

        [Parameter(Mandatory)]
        [string]$RemoteHost,

        # Optional: if you can determine a specific key path (IdentityFile), pass it.
        [string]$IdentityFile,

        [Parameter(Mandatory)]
        [string]$RemoteCommand
    )

    $baseArgs = @(
        "-o", "ConnectTimeout=6",
        "-o", "StrictHostKeyChecking=accept-new"
    )

    if ($IdentityFile) {
        $baseArgs += @("-i", $IdentityFile)
    }

    # 1) Key-only attempt (no prompts)
    $keyOnlyArgs = $baseArgs + @(
        "-o", "BatchMode=yes",
        "$RemoteUser@$RemoteHost",
        $RemoteCommand
    )

    $out = & ssh @keyOnlyArgs 2>&1
    $code = $LASTEXITCODE

    if ($code -eq 0) {
        return @{ Success = $true; UsedPassword = $false; Output = $out }
    }

    # If auth failed, fall back to password (interactive)
    if ($out -match "Permission denied" -or $out -match "Authentication failed") {
        Write-Host "🔑 No usable SSH key found for $RemoteUser@$RemoteHost. Falling back to password..." -ForegroundColor Yellow

        $passwordArgs = $baseArgs + @(
            "$RemoteUser@$RemoteHost",
            $RemoteCommand
        )

        $out2 = & ssh @passwordArgs 2>&1
        $code2 = $LASTEXITCODE

        return @{ Success = ($code2 -eq 0); UsedPassword = $true; Output = $out2 }
    }

    # Other failures (DNS, refused, timeout, etc.) – return as-is
    return @{ Success = $false; UsedPassword = $false; Output = $out }
}
#endregion


#region Reads, a.k.a, Prompts
function Read-RemoteUser {
    param (
        [string]$DefaultUser = "$DefaultUserName"
    )

    $RemoteUser = Read-ColoredInput -Prompt "Enter remote username (default: $DefaultUser)" -ForegroundColor "Cyan"
    return (Resolve-NullToDefault -DefaultValue $DefaultUser -Value $RemoteUser)
}


function Read-RemoteHostName {
    param (
        [string]$SubnetPrefix = "$DefaultSubnetPrefix"
    )

    $RemoteHost = Read-ColoredInput -Prompt "Enter the Hostname | Full IP address | Last 2–3 digits for $SubnetPrefix.xx of the remote machine: " -ForegroundColor "Cyan"

    if ($RemoteHost -match '^\d{1,3}$') {
        # Input is a short numeric suffix like "123"
        $ResolvedHost = "$SubnetPrefix.$RemoteHost"
        Write-Host "📡 Interpreted as short IP: $ResolvedHost" -ForegroundColor Green
        return $ResolvedHost
    
    } elseif ($RemoteHost -match '^\d{1,3}(\.\d{1,3}){3}$') {
        # Input is a full IP address
        Write-Host "🌐 Full IP address given: $RemoteHost" -ForegroundColor Cyan
        return $RemoteHost
    
    } elseif ($RemoteHost) {
        # Input is likely a label or hostname
        Write-Host "🏷  Label Provided: $RemoteHost" -ForegroundColor Cyan
        return $RemoteHost
    
    } else {
        Write-Host "❗ No input provided." -ForegroundColor Red
        return $null
    }
    
}


function Read-RemoteHostAddress {
    param (
        [string]$SubnetPrefix = "$DefaultSubnetPrefix"
    )

    $RemoteHost = Read-ColoredInput -Prompt "Enter remote IP (or last 2–3 digits for $SubnetPrefix.xx)" -ForegroundColor "Cyan"

    if ($RemoteHost -match "^\d{2,3}$") {
        return "$SubnetPrefix.$RemoteHost"
    } else {
        Write-Host "🌐 Full IP address given: $RemoteHost" -ForegroundColor Cyan
        return $RemoteHost
    }
}


function Read-SSHKeyName {
    $KeyName = Read-ColoredInput -Prompt "Enter the SSH key name" -ForegroundColor "Cyan"
    $KeyName = Resolve-NullToAction -Action { Read-SSHKeyName } -RequiredValue $KeyName -RequiredValueLabel "Key Name"

    return $KeyName
}


function Read-SSHKeyComment {
    param (
        [string]$DefaultComment
    )

    $Comment = Read-ColoredInput -Prompt "Enter the key comment (default: $DefaultComment)" -ForegroundColor "Cyan"
    return (Resolve-NullToDefault -DefaultValue $DefaultComment -Value $Comment)
}


function Read-ColoredInput {
    param (
        [string]$Prompt,
        [ConsoleColor]$ForegroundColor = "Cyan"
    )

    Write-Host -NoNewline "$Prompt " -ForegroundColor $ForegroundColor
    return Read-Host
}
#endregion


#region Resolvers & Validations
function Resolve-NullToDefault {
    param (
        [string]$DefaultValue,
        [string]$Value
    )

    if (Test-ValueIsNull -Value $Value) {
        # Write-Host "Value is: $Value"
        return $DefaultValue
    } else {
        # Write-Host "Value is: $Value"
        return $Value
    }
}


function Resolve-NullToAction {
    param (
        [ScriptBlock]$Action,
        [string]$RequiredValue,
        [string]$RequiredValueLabel
    )

    if ([string]::IsNullOrWhiteSpace($RequiredValue)) {
        Write-Host "❗ $RequiredValueLabel is a required value." -ForegroundColor Red
        & $Action
        return
    }

    return $RequiredValue
}


function Confirm-UserChoice {
    # A function that's called on-demand when we wish to confirm an answer from the user
    # We pass to it the default value -- similar to how linux works, we juggle those
    # according to the destructiveness of the question we're asking the user.
    # The default answer (to increase the UX) is needed and then signified to the user
    # by capitalizing the default answer.
    # If the user wishes to move forward, it will invoke the passed action to it.
    # If the user declines, then we will return false and the passed action won't be executed.
    # It has a built-in validation where it loops itself 
    param (
        [string]$Message,
        [ScriptBlock]$Action,
        [string]$DefaultAnswer
    )

    # Normalize default answer
    $NormalizedDefault = $DefaultAnswer.ToLower()

    # Prompt string with default shown
    $promptSuffix = if ($NormalizedDefault -eq 'y' -or $NormalizedDefault -eq 'yes') {
        "[Y/n]"
    } elseif ($NormalizedDefault -eq 'n' -or $NormalizedDefault -eq 'no') {
        "[y/N]"
    } else {
        "[y/n]"
    }

    $response = Read-ColoredInput -Prompt "$Message $promptSuffix" -ForegroundColor "Cyan"

    $response = Resolve-NullToDefault -Value $response -DefaultValue $DefaultAnswer

    switch -Regex ($response) {
        '^(yes|y)$' {
            & $Action
            return $true
        }
        '^(no|n)$' {
            Write-Host "❌ Action cancelled." -ForegroundColor Yellow
            return $false
        }
        default {
            Write-Host "⚠️ Invalid input. Please enter 'y' or 'n'." -ForegroundColor Red
            return (Confirm-UserChoice -Message $Message -Action $Action -DefaultAnswer $DefaultAnswer)
        }
    }
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
#endregion


#region Finders
function Find-ConfigFileOnHost {
    # Looks for the existence of a Config file in the host's `.ssh` folder
    # True if it does, false if it doesn't.
    param (
        [string]$Path = "$env:USERPROFILE\.ssh\config"
    )

    if (-not (Test-Path $Path)) {
        Write-Host "⚠️ SSH config file not found at $Path." -ForegroundColor Yellow
        return $false
    }

    return $Path
}

function Find-SSHKeyInHostConfig {
    # Looks for a specific private key (IdentityFile) if it had been used in one of the code-blocks
    # True if it does, false if it doesn't.
    param (
        [string]$KeyName,
        [string]$RemoteHostName,
        [switch]$ReturnResult
    )

    $sshConfig = Find-ConfigFileOnHost

    # Read the entire config as text
    $config = Get-Content -Path $sshConfig -Raw -Encoding UTF8

    # Match the block for the specified Host
    $pattern = "(?ms)^Host\s+$RemoteHostName\b.*?(?=^Host\s|\z)"
    $match = [regex]::Match($config, $pattern)

    if (-not $match.Success) {
        if ($ReturnResult) { return $false }
        Write-Host "⚠️ No SSH config block found for host '$RemoteHostName'." -ForegroundColor Yellow
        return $false
    }

    $block = $match.Value

    # Check if any IdentityFile line includes the specified key name
    $escapedKey = [regex]::Escape($KeyName)
    $pattern = "IdentityFile\s+[^\r\n]*[\\/]" + $escapedKey + "(?:\r?\n|$)"

    if ([regex]::IsMatch($block, $pattern)) {
        Write-Host "✅ IdentityFile '$KeyName' is present in host '$RemoteHostName' config block." -ForegroundColor Green
        if ($ReturnResult) { return $true }
    } else {
        Write-Host "❌ IdentityFile '$KeyName' not found in host '$RemoteHostName' config block." -ForegroundColor Red
        if ($ReturnResult) { return $false }
    }
}

function Find-PrivateKeyInHost {
    # Attempts to find the private key of an SSH key-pair, true if it finds it, false, if it doesn't.
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
    # Finds a certain public key in this machine. This only returns boolean if it finds it
    # for the content of the public key see `Get-PublicKeyInHost` below.
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
    # Retrieves the IP Address of a remote machine that we SSH into
    # from the config block on this machine's the config file.
    param (
        [Parameter(Mandatory = $true)]
        [string]$RemoteHostName
    )

    $sshConfig = Find-ConfigFileOnHost

    # Read the entire config as text
    $config = Get-Content -Path $sshConfig -Raw -Encoding UTF8

    # Match the block for the given Host
    $pattern = "(?ms)^Host\s+$RemoteHostName\b.*?(?=^Host\s|\z)"
    $match = [regex]::Match($config, $pattern)

    if (-not $match.Success) {
        Write-Host "⚠️ No Host block found for '$RemoteHostName'" -ForegroundColor Yellow
        return $null
    }

    $block = $match.Value

    # Extract HostName line (IP or domain)
    if ($block -match 'HostName\s+([^\s]+)') {
        return $matches[1]
    } else {
        Write-Host "⚠️ No HostName defined in Host '$RemoteHostName'" -ForegroundColor Yellow
        return $null
    }
}

function Get-RemoteUserFromConfigEntry {
    # Returns the user that we use to log into a remote machine previously
    # defined in the config file.
    param (
        [Parameter(Mandatory = $true)]
        [string]$RemoteHostName
    )

    $sshConfig = Find-ConfigFileOnHost

    # Read the entire config as text
    $config = Get-Content -Path $sshConfig -Raw -Encoding UTF8

    # Match the block for the given Host
    $pattern = "(?ms)^Host\s+$RemoteHostName\b.*?(?=^Host\s|\z)"
    $match = [regex]::Match($config, $pattern)

    if (-not $match.Success) {
        Write-Host "⚠️ No Host block found for '$RemoteHostName'" -ForegroundColor Yellow
        return $null
    }

    $block = $match.Value

    # Extract User line (e.g., "User kraid")
    if ($block -match 'User\s+([^\s]+)') {
        return $matches[1]
    } else {
        Write-Host "⚠️ No User defined in Host '$RemoteHostName'" -ForegroundColor Yellow
        return $null
    }
}
#endregion

#region Testers
function Test-ValueIsNull {
    # This tests if the value entered by the user is null or not. If null, it will return `true`.
    param (
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $true
    } else {
        return $false
    }
}


function Get-PublicKeyInHost {
    # This looks for the public key on this local machine that's running windows.
    # If it finds it it returns the public key as raw text, else returns NULL.
    param (
        [string]$KeyName
    )

    $PublicKeyPath = "$env:USERPROFILE\.ssh\$KeyName.pub"

    if (-not (Test-Path $PublicKeyPath)) {
        Write-Host "❌ Public key '$KeyName.pub' not found at $PublicKeyPath." -ForegroundColor Red
        return $null
    }

    $PublicKey = Get-Content $PublicKeyPath -Raw
    Write-Host "✅ Public key loaded successfully:`n$PublicKey" -ForegroundColor Green
    return $PublicKey
}
#endregion


function Resolve-SSHTarget {
    # Given an IP/address and user, returns "user@alias" if a matching HostName
    # entry exists in ~/.ssh/config so that SSH applies the full config block
    # (IdentityFile, etc.). Falls back to "user@address" if nothing matches.
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
            if ($hb.Value -match "(?m)^\s*HostName\s+$([regex]::Escape($RemoteHostAddress))\s*$") {
                Write-Host "  ℹ  SSH config entry '$alias' found for $RemoteHostAddress — key from config will be used." -ForegroundColor DarkGray
                return "$RemoteUser@$alias"
            }
        }
    }
    return "$RemoteUser@$RemoteHostAddress"
}


function Remove-HostFromSSHConfig {
    $hostName = Read-ColoredInput -Prompt "Enter the Host alias to remove" -ForegroundColor "Cyan"
    if ([string]::IsNullOrWhiteSpace($hostName)) {
        Write-Host "❗ Host alias is required." -ForegroundColor Red
        return
    }

    $configPath = "$env:USERPROFILE\.ssh\config"
    if (-not (Test-Path $configPath)) {
        Write-Host "❌ SSH config not found at $configPath" -ForegroundColor Red
        return
    }

    $config  = Get-Content $configPath -Raw -Encoding UTF8
    $pattern = "(?ms)^Host\s+$([regex]::Escape($hostName))\b.*?(?=^Host\s|\z)"
    $match   = [regex]::Match($config, $pattern)

    if (-not $match.Success) {
        Write-Host "⚠️ No Host block found for '$hostName'" -ForegroundColor Yellow
        return
    }

    Write-Host "`n  Block that will be removed:" -ForegroundColor DarkGray
    Write-Host $match.Value -ForegroundColor Gray

    $confirm = Read-ColoredInput -Prompt "Remove this block? [y/N]" -ForegroundColor "Yellow"
    if ($confirm -notmatch '^(y|yes)$') {
        Write-Host "❌ Cancelled." -ForegroundColor Yellow
        return
    }

    $newConfig = ($config -replace [regex]::Escape($match.Value), "").TrimEnd() + "`n"
    [System.IO.File]::WriteAllText($configPath, $newConfig, [System.Text.Encoding]::UTF8)
    Write-Host "✅ Host '$hostName' removed from SSH config." -ForegroundColor Green
}


function Show-SSHConfigFile {
    $configPath = "$env:USERPROFILE\.ssh\config"
    if (-not (Test-Path $configPath)) {
        Write-Host "❌ SSH config not found at $configPath" -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "  $configPath" -ForegroundColor DarkGray
    Write-Host "  $('─' * $configPath.Length)" -ForegroundColor DarkGray
    Write-Host ""
    Show-Paged -Lines (Get-Content $configPath)
}


function Edit-SSHConfigFile {
    $configPath = "$env:USERPROFILE\.ssh\config"
    if (-not (Test-Path $configPath)) {
        Write-Host "❌ SSH config not found at $configPath" -ForegroundColor Red
        return
    }

    $editor = if ($env:EDITOR) { $env:EDITOR } else { "notepad.exe" }
    Write-Host "  Opening in $editor — return here when done." -ForegroundColor DarkGray
    try {
        & $editor $configPath
        Write-Host "✅ Done." -ForegroundColor Green
    } catch {
        Write-Host "❌ Could not open editor '$editor': $_" -ForegroundColor Red
    }
}


Show-MainMenu
