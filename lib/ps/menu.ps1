# lib/ps/menu.ps1 — Show-MainMenu and Invoke-MenuChoice

function Show-MainMenu {
    $menuDef = @(
        [pscustomobject]@{ Type = "header"; Label = "Remote" }
        [pscustomobject]@{ Type = "item";   Label = "Generate & Install SSH Key on A Remote Machine"; Choice = "1";  Hotkey = "G" }
        [pscustomobject]@{ Type = "item";   Label = "Install SSH Key on A Remote Machine";            Choice = "15"; Hotkey = "I" }
        [pscustomobject]@{ Type = "item";   Label = "Test SSH Connection";                            Choice = "2";  Hotkey = "T" }
        [pscustomobject]@{ Type = "item";   Label = "Delete SSH Key From A Remote Machine";           Choice = "3";  Hotkey = "D" }
        [pscustomobject]@{ Type = "item";   Label = "Promote Key on A Remote Machine";                Choice = "4";  Hotkey = "P" }
        [pscustomobject]@{ Type = "item";   Label = "List Authorized Keys on Remote Host";            Choice = "16"; Hotkey = "Z" }
        [pscustomobject]@{ Type = "item";   Label = "Add Config Block for Existing Remote Key";       Choice = "17"; Hotkey = "N" }
        [pscustomobject]@{ Type = "header"; Label = "Local" }
        [pscustomobject]@{ Type = "item";   Label = "Generate SSH Key (Without Installation)";        Choice = "5";  Hotkey = "W" }
        [pscustomobject]@{ Type = "item";   Label = "List SSH Keys";                                  Choice = "6";  Hotkey = "L" }
        [pscustomobject]@{ Type = "item";   Label = "Append SSH Key to Hostname in Host Config";      Choice = "7";  Hotkey = "A" }
        [pscustomobject]@{ Type = "item";   Label = "Delete an SSH Key Locally";                      Choice = "8";  Hotkey = "X" }
        [pscustomobject]@{ Type = "item";   Label = "Remove an SSH Key From Config";                  Choice = "9";  Hotkey = "R" }
        [pscustomobject]@{ Type = "header"; Label = "Config File" }
        [pscustomobject]@{ Type = "item";   Label = "Remove Host from SSH Config";                    Choice = "12"; Hotkey = "H" }
        [pscustomobject]@{ Type = "item";   Label = "View SSH Config";                                Choice = "13"; Hotkey = "V" }
        [pscustomobject]@{ Type = "item";   Label = "Edit SSH Config";                                Choice = "14"; Hotkey = "E" }
        [pscustomobject]@{ Type = "item";   Label = "Exit";                                           Choice = "q";  Hotkey = "Q" }
    )

    $navItems = @($menuDef | Where-Object { $_.Type -eq "item" })

    $flatRows = [System.Collections.Generic.List[pscustomobject]]::new()
    $ni = 0
    foreach ($e in $menuDef) {
        if ($e.Type -eq "header") {
            $flatRows.Add([pscustomobject]@{ Type = "blank";  Label = "";       nIdx = -1 })
            $flatRows.Add([pscustomobject]@{ Type = "header"; Label = $e.Label; nIdx = -1 })
        } else {
            $flatRows.Add([pscustomobject]@{ Type = "item"; Label = $e.Label; nIdx = $ni; Hotkey = $e.Hotkey })
            $ni++
        }
    }
    $flatCount = $flatRows.Count

    $sel        = 0
    $prevSel    = -1
    $itemRows   = @{}
    $needFull   = $true
    $running    = $true
    $termWidth  = 0
    $termHeight = 0
    $viewOff    = 0

    [Console]::Write("`e[?1049h`e[?25l")

    try {
        while ($running) {

            # ── Full render ────────────────────────────────────────────────────────
            if ($needFull) {
                $termWidth  = $Host.UI.RawUI.WindowSize.Width
                $termHeight = $Host.UI.RawUI.WindowSize.Height

                $menuRule     = "-" * [Math]::Max(0, $termWidth - 4)
                $menuTitle    = "SSH Key Manager"
                $menuTitlePad = " " * [Math]::Max(0, [int](($termWidth - 4 - ($menuTitle.Length + 1)) / 2))

                # Content rows: 5..(termHeight-2). Two-row hint bar: termHeight-1 and termHeight.
                $contentStart = 5
                $contentEnd   = $termHeight - 2
                $contentRows  = [Math]::Max(1, $contentEnd - $contentStart + 1)

                $selFlatIdx = -1
                for ($fi = 0; $fi -lt $flatCount; $fi++) {
                    if ($flatRows[$fi].Type -eq "item" -and $flatRows[$fi].nIdx -eq $sel) {
                        $selFlatIdx = $fi; break
                    }
                }

                if ($selFlatIdx -ge 0) {
                    if ($selFlatIdx -lt $viewOff) {
                        $viewOff = $selFlatIdx
                    } elseif ($selFlatIdx -ge $viewOff + $contentRows) {
                        $viewOff = $selFlatIdx - $contentRows + 1
                    }
                }
                $viewOff = [Math]::Max(0, $viewOff)

                $titleContent = "  " + $menuTitlePad + $menuTitle
                $titleFill    = " " * [Math]::Max(0, $termWidth - $titleContent.Length)
                $f  = "`e[2J`e[H"
                $f += "`e[2;1H  `e[96m$menuRule`e[0m`e[K"
                $f += "`e[3;1H`e[48;5;23m`e[1;97m$titleContent$titleFill`e[0m"
                $f += "`e[4;1H  `e[96m$menuRule`e[0m`e[K"

                $itemRows = @{}
                $row      = $contentStart
                $endFi    = [Math]::Min($viewOff + $contentRows, $flatCount)

                for ($fi = $viewOff; $fi -lt $endFi; $fi++) {
                    $fr = $flatRows[$fi]
                    switch ($fr.Type) {
                        "blank"  { $f += "`e[$row;1H`e[K" }
                        "header" { $f += "`e[$row;1H  `e[90m  > `e[1m$($fr.Label)`e[0m`e[K" }
                        "item"   {
                            $itemRows[$fr.nIdx] = $row
                            if ($fr.nIdx -eq $sel) {
                                $f += "`e[$row;1H`e[7m  $($fr.Label)`e[K`e[0m"
                            } else {
                                $f += "`e[$row;1H`e[0m`e[37m    $(Format-MenuLabel $fr.Label $fr.Hotkey)`e[0m`e[K"
                            }
                        }
                    }
                    $row++
                }

                while ($row -le $contentEnd) { $f += "`e[$row;1H`e[K"; $row++ }

                if ($viewOff -gt 0) {
                    $f += "`e[$contentStart;$($termWidth - 1)H`e[90m^`e[0m"
                }
                if ($viewOff + $contentRows -lt $flatCount) {
                    $f += "`e[$contentEnd;$($termWidth - 1)H`e[90mv`e[0m"
                }

                # Two-row Nano-style hint bar
                $hn_plain = "  Up/Dn Navigate   Home/End Jump   Enter Select   F1 Help   F10 Conf"
                $hk_plain = "  G Generate   T Test SSH   D Delete   L List   V View   E Edit   Q Quit"
                $hn = "  `e[1mUp/Dn`e[0;7m Navigate   `e[1mHome/End`e[0;7m Jump   `e[1mEnter`e[0;7m Select   `e[1mF1`e[0;7m Help   `e[1mF10`e[0;7m Conf"
                $hk = "  `e[1mG`e[0;7m Generate   `e[1mT`e[0;7m Test SSH   `e[1mD`e[0;7m Delete   `e[1mL`e[0;7m List   `e[1mV`e[0;7m View   `e[1mE`e[0;7m Edit   `e[1mQ`e[0;7m Quit"
                $hnPad = " " * [Math]::Max(0, $termWidth - $hn_plain.Length)
                $hkPad = " " * [Math]::Max(0, $termWidth - $hk_plain.Length)
                $f += "`e[$($termHeight - 1);1H`e[7m$hn$hnPad`e[0m"
                $f += "`e[$termHeight;1H`e[7m$hk$hkPad`e[0m"

                [Console]::Write($f)
                $prevSel  = $sel
                $needFull = $false

            # ── Differential update ────────────────────────────────────────────────
            } elseif ($prevSel -ne $sel) {
                if ($itemRows.ContainsKey($sel) -and $itemRows.ContainsKey($prevSel)) {
                    $r = $itemRows[$prevSel]
                    [Console]::Write("`e[${r};1H`e[0m`e[37m    $(Format-MenuLabel $navItems[$prevSel].Label $navItems[$prevSel].Hotkey)`e[0m`e[K")
                    $r = $itemRows[$sel]
                    [Console]::Write("`e[${r};1H`e[7m  $($navItems[$sel].Label)`e[K`e[0m")
                    $prevSel = $sel
                } else {
                    $needFull = $true
                }
            }

            # ── Poll for input ─────────────────────────────────────────────────────
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

            if ($null -eq $key) { continue }

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
                        _InvokeMenuAction -Choice $choice -Label $navItems[$sel].Label -TermWidth $termWidth
                        $needFull = $true
                    }
                }
            }

            if ($key.Character -eq 'q' -or $key.Character -eq 'Q') { $running = $false }

            # F1 / F10
            if ($key.VirtualKeyCode -eq 112 -or $key.VirtualKeyCode -eq 121) {
                $fChoice = if ($key.VirtualKeyCode -eq 112) { "10" } else { "11" }
                $fLabel  = if ($key.VirtualKeyCode -eq 112) { "Help: Best Practices" } else { "Conf: Global Defaults" }
                _InvokeMenuAction -Choice $fChoice -Label $fLabel -TermWidth $termWidth -IsF $true
                $needFull = $true
            }

            # Hotkey shortcut
            if ($key.Character) {
                $hkMatch = $navItems | Where-Object { $_.Hotkey -and ($_.Hotkey -ieq [string]$key.Character) } | Select-Object -First 1
                if ($hkMatch) {
                    $hkChoice = $hkMatch.Choice
                    if ($hkChoice -eq 'q') {
                        $running = $false
                    } else {
                        _InvokeMenuAction -Choice $hkChoice -Label $hkMatch.Label -TermWidth $termWidth
                        $needFull = $true
                    }
                }
            }
        }
    } finally {
        [Console]::Write("`e[?25h`e[?1049l")
    }
}


function _InvokeMenuAction {
    # Draws the operation header, calls Invoke-MenuChoice, handles Wait-UserAcknowledge.
    param(
        [string]$Choice,
        [string]$Label,
        [int]$TermWidth,
        [switch]$IsF
    )
    $rule    = "-" * [Math]::Max(0, $TermWidth - 4)
    $opPad   = " " * [Math]::Max(0, [int](($TermWidth - 4 - $Label.Length) / 2))
    $opTitle = "  " + $opPad + $Label
    $opFill  = " " * [Math]::Max(0, $TermWidth - $opTitle.Length)
    $f  = "`e[2J`e[H`e[?25h`n"
    $f += "  `e[96m$rule`e[0m`n"
    $f += "`e[48;5;23m`e[1;97m$opTitle$opFill`e[0m`n"
    $f += "  `e[96m$rule`e[0m`n`n"
    [Console]::Write($f)
    try {
        $skipWait = Invoke-MenuChoice -Choice $Choice
        # Conf (11) has its own Q-to-exit; Help (10) and all ops need ack
        if (-not $skipWait -and (-not $IsF -or $Choice -ne "11")) {
            Wait-UserAcknowledge
        }
    } catch [System.OperationCanceledException] { }
    [Console]::Write("`e[?25l")
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
            $RemoteHost = Read-RemoteHostAddress -SubnetPrefix "$DefaultSubnetPrefix"
            $RemoteUser = Read-RemoteUser -DefaultUser "$DefaultUserName"

            $cfgKeys   = @()
            $selAlias  = $script:_LastSelectedAlias
            if ($selAlias) {
                $cfgPath = "$env:USERPROFILE\.ssh\config"
                if (-not (Test-Path $cfgPath)) { $cfgPath = "$env:HOME/.ssh/config" }
                if (Test-Path $cfgPath) {
                    $cfgRaw  = Get-Content $cfgPath -Raw -Encoding UTF8
                    $aliasE  = [regex]::Escape($selAlias)
                    $block   = [regex]::Match($cfgRaw, "(?ms)^Host\s+$aliasE\b.*?(?=^Host\s|\z)").Value
                    $cfgKeys = @([regex]::Matches($block, '(?m)^\s*IdentityFile\s+(.+?)\s*$') |
                                 ForEach-Object { $_.Groups[1].Value.Trim().Trim('"') })
                }
            }

            if ($cfgKeys.Count -gt 1) {
                $allLabel  = "-- Test ALL ($($cfgKeys.Count) keys)"
                $keyLabels = @($allLabel) + $cfgKeys
                $selected  = Select-FromList -Items $keyLabels -Prompt "Select key to test:"
                if ($selected -and $selected.StartsWith("--")) {
                    $isFirst = $true
                    $cfgKeys | ForEach-Object {
                        if (-not $isFirst) { Write-Host "" }
                        $isFirst = $false
                        Write-Host "  Testing with key: $_" -ForegroundColor DarkGray
                        Test-SSHConnection -RemoteUser $RemoteUser -RemoteHost $RemoteHost -IdentityFile $_
                    }
                } elseif ($selected) {
                    Write-Host "  Using key: $selected" -ForegroundColor DarkGray
                    Test-SSHConnection -RemoteUser $RemoteUser -RemoteHost $RemoteHost -IdentityFile $selected
                }
            } else {
                if ($cfgKeys.Count -eq 1) { Write-Host "  Using key: $($cfgKeys[0])" -ForegroundColor DarkGray }
                Test-SSHConnection -RemoteUser $RemoteUser -RemoteHost $RemoteHost
            }
        }
        "3" {
            $RemoteHostAddress = Read-RemoteHostAddress -SubnetPrefix "$DefaultSubnetPrefix"
            $RemoteUser        = Read-RemoteUser -DefaultUser "$DefaultUserName"
            $selectedAlias     = $script:_LastSelectedAlias
            $target            = Resolve-SSHTarget -RemoteHostAddress $RemoteHostAddress -RemoteUser $RemoteUser
            $_idLookup = if ($selectedAlias) { $selectedAlias } else { $RemoteHostAddress }
            foreach ($k in (Get-IdentityFilesForHost $_idLookup)) {
                Write-Host "  Using key: $k" -ForegroundColor DarkGray
            }

            Write-Host "  Fetching authorized keys from $target..." -ForegroundColor DarkGray
            try {
                $rawKeys = ssh $target "cat ~/.ssh/authorized_keys 2>/dev/null"
            } catch {
                Write-Host "  Could not connect to ${target}: $($_.Exception.Message)" -ForegroundColor Red
                return
            }
            $remoteLines = @($rawKeys -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            if ($remoteLines.Count -eq 0) {
                Write-Host "  No authorized_keys found on $target." -ForegroundColor DarkGray
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
                Write-Host "  No local public keys found in $target authorized_keys." -ForegroundColor Yellow
                return
            }

            $labels   = @($matchedKeys | ForEach-Object { "$($_.KeyName)  ($($_.PubPath))" })
            $selected = Select-FromList -Items $labels -Prompt "Select key to remove from remote:" -StrictList
            if (-not $selected) { return }
            $pick     = $matchedKeys[$labels.IndexOf($selected)]

            $pubContent    = $pick.PubContent
            $RemoteCommand = "TMP_FILE=`$(mktemp) && printf '%s`\n' '$pubContent' > `$TMP_FILE && awk 'NR==FNR { keys[`$0]; next } !(`$0 in keys)' `$TMP_FILE ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.tmp && mv ~/.ssh/authorized_keys.tmp ~/.ssh/authorized_keys && rm -f `$TMP_FILE"
            Write-Host "  Removing key '$($pick.KeyName)' from $target..." -ForegroundColor Yellow
            try {
                ssh $target $RemoteCommand
                Write-Host "  Key removed from remote authorized_keys." -ForegroundColor Green
            } catch {
                Write-Host "  Failed to remove key from remote." -ForegroundColor Red
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
                if (Test-Path $privPath) { Remove-Item $privPath -Force; Write-Host "  Deleted: $privPath" -ForegroundColor Green }
                if (Test-Path $pubPath)  { Remove-Item $pubPath  -Force; Write-Host "  Deleted: $pubPath"  -ForegroundColor Green }
            } -DefaultAnswer "n"
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

            $keyPath = "$env:USERPROFILE\.ssh\$KeyName"
            $testOut = & ssh -i $keyPath -o BatchMode=yes -o ConnectTimeout=6 -o StrictHostKeyChecking=accept-new "$RemoteUser@$RemoteHostAddress" "echo ok" 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  Key verified on $RemoteHostAddress." -ForegroundColor Green
            } else {
                Write-Host "  Could not verify '$KeyName' on $RemoteHostAddress -- it may not be installed yet." -ForegroundColor Yellow
                $proceed = Read-HostWithDefault -Prompt "Add to config anyway? (y/N):" -Default "N"
                if ($proceed -notmatch '^[Yy]') { return }
            }
            Add-SSHKeyToHostConfig -KeyName $KeyName -RemoteHostName $RemoteHostName -RemoteHostAddress $RemoteHostAddress -RemoteUser $RemoteUser
        }
        "8" {
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
                    Write-Host "  Removing key from $($h.Alias)..." -ForegroundColor DarkGray
                    Remove-SSHKeyFromRemote -RemoteUser $rUser -RemoteHost $rHost -KeyName $KeyName
                }
            } else {
                Write-Host "  No configured hosts reference this key." -ForegroundColor DarkGray
            }

            $privPath = "$env:USERPROFILE\.ssh\$KeyName"
            $pubPath  = "$privPath.pub"
            $deleted  = @()
            if (Test-Path $privPath) { Remove-Item $privPath -Force; $deleted += $privPath }
            if (Test-Path $pubPath)  { Remove-Item $pubPath  -Force; $deleted += $pubPath  }
            if ($deleted.Count -gt 0) {
                $deleted | ForEach-Object { Write-Host "  Deleted: $_" -ForegroundColor Green }
                Write-Host "  Key '$KeyName' removed locally." -ForegroundColor Green
            } else {
                Write-Host "  No local key files found for '$KeyName'." -ForegroundColor Yellow
            }
        }
        "9" {
            $allHosts = Get-ConfiguredSSHHosts
            if ($allHosts.Count -eq 0) {
                Write-Host "  No configured hosts found in ~/.ssh/config." -ForegroundColor DarkGray
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
                Write-Host "  No IdentityFile entries found under host '$hostName'." -ForegroundColor DarkGray
                return
            }
            $KeyName = Select-FromList -Items $keyNames -Prompt "Select key to remove from '$hostName':"
            if (-not $KeyName) { return }

            Remove-IdentityFileFromConfigEntry -KeyName $KeyName -RemoteHostName $hostName
        }
        "10" {
            Write-Host ""
            Write-Host "  Best Practices" -ForegroundColor Cyan
            Write-Host "  --------------" -ForegroundColor DarkGray
            Write-Host "  1. CTs demo'd over LAN         -> shared key (e.g. demo-lan)" -ForegroundColor Cyan
            Write-Host "  2. CTs in development over LAN -> shared key (e.g. dev-lan)" -ForegroundColor Cyan
            Write-Host "  3. CTs promoted into the stack -> shared key (e.g. prod-lan)" -ForegroundColor Cyan
            Write-Host "  4. CTs accessed over the WAN   -> individual key (e.g. sonarr-wan)" -ForegroundColor Red
        }
        "11" {
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
                $rule  = "-" * [Math]::Max(0, $tw - 4)
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
            Write-Host "  Defaults updated for this session." -ForegroundColor Green
            Write-Host "  To persist: pass as script parameters (-DefaultUserName, etc.)" -ForegroundColor Yellow
        }
        "15" {
            $KeyName = Read-SSHKeyName
            if (-not (Find-PrivateKeyInHost -KeyName $KeyName -ReturnResult $true)) {
                Write-Host "  Key '$KeyName' not found locally. Use 'Generate & Install' to create it first." -ForegroundColor Red
                return
            }
            Install-SSHKeyOnRemote -KeyName $KeyName
        }
        "16" {
            $RemoteHostAddress = Read-RemoteHostAddress -SubnetPrefix "$DefaultSubnetPrefix"
            $RemoteUser        = Read-RemoteUser -DefaultUser "$DefaultUserName"
            $target = Resolve-SSHTarget -RemoteHostAddress $RemoteHostAddress -RemoteUser $RemoteUser
            Write-Host "  Fetching authorized_keys from $target..." -ForegroundColor DarkGray
            try {
                $keys = ssh $target "cat ~/.ssh/authorized_keys 2>/dev/null"
                if (-not $keys) {
                    Write-Host "  No authorized_keys found on $target." -ForegroundColor DarkGray
                } else {
                    Write-Host "  `e[1;37mAuthorized keys on ${target}:`e[0m"
                    $i = 1
                    $keys -split "`n" | Where-Object { $_.Trim() } | ForEach-Object {
                        Write-Host "  `e[90m$($i.ToString().PadLeft(3))`e[0m  `e[36m$_`e[0m"
                        $i++
                    }
                }
            } catch {
                Write-Host "  Failed to fetch authorized_keys: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        "17" { Register-RemoteHostConfig }
        "12" { Remove-HostFromSSHConfig }
        "13" { Show-SSHConfigFile; return $true }
        "14" { Edit-SSHConfigFile; return $true }
    }
}
