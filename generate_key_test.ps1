param(
  [string]$DefaultUserName     = "default_non_root_username",
  [string]$DefaultSubnetPrefix = "192.168.0",
  [string]$DefaultCommentSuffix = "-[my-machine]",
  [string]$DefaultPassword     = ""
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$P = "  "   # 2-space left-pad applied to all user-facing output

function Wait-UserAcknowledge {
    $h = $Host.UI.RawUI.WindowSize.Height
    $w = $Host.UI.RawUI.WindowSize.Width
    $msg = "  Press any key to return to menu  "
    [Console]::Write("`e[$h;1H`e[7m$msg$(" " * [Math]::Max(0, $w - $msg.Length))`e[0m")
    $modifierVKs = @(16, 17, 18, 20, 91, 92, 93, 144, 145)
    try {
        do {
            $k = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        } while ($modifierVKs -contains $k.VirtualKeyCode)
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


function Select-FromList {
    # Combo-box: ↑↓ navigates list, typing filters/creates new entry, Enter selects, Esc cancels.
    param(
        [string[]]$Items,
        [string]$Prompt = "Select"
    )
    if (-not $Items -or $Items.Count -eq 0) { return $null }

    $tw  = $Host.UI.RawUI.WindowSize.Width
    $th  = $Host.UI.RawUI.WindowSize.Height
    try { $startRow = [Console]::CursorTop + 3 } catch { $startRow = 8 }
    $maxVis  = [Math]::Max(1, $th - $startRow - 2)
    $sel     = -1    # -1 = cursor in text input, >=0 = list item highlighted
    $viewOff = 0
    $filter  = ""
    $filtered = $Items

    [Console]::Write("`e[?25l")

    while ($true) {
        # Re-filter list
        $filtered = if ($filter) { @($Items | Where-Object { $_ -like "*$filter*" }) } else { $Items }
        if ($sel -ge $filtered.Count) { $sel = $filtered.Count - 1 }
        if ($sel -lt $viewOff -and $sel -ge 0) { $viewOff = $sel }
        elseif ($sel -ge 0 -and $sel -ge $viewOff + $maxVis) { $viewOff = $sel - $maxVis + 1 }
        if ($viewOff -lt 0) { $viewOff = 0 }

        $promptRow = $startRow - 2
        $inputRow  = $startRow - 1
        $inputDisp = if ($filter) { "`e[37m$filter`e[90m▌`e[0m" } else { "`e[90m(type to filter or create new)`e[0m" }
        $f  = "`e[$promptRow;1H`e[K  `e[90m$Prompt`e[0m"
        $f += "`e[$inputRow;1H`e[K  `e[36m›`e[0m $inputDisp"
        for ($i = 0; $i -lt $maxVis; $i++) {
            $idx = $viewOff + $i
            $r   = $startRow + $i
            $f  += "`e[$r;1H`e[K"
            if ($idx -lt $filtered.Count) {
                if ($idx -eq $sel) { $f += "  `e[1;36m▶ $($filtered[$idx])`e[0m" }
                else               { $f += "  `e[37m  $($filtered[$idx])`e[0m" }
            }
        }
        $up   = if ($viewOff -gt 0)                           { "▲ " } else { "  " }
        $dn   = if ($viewOff + $maxVis -lt $filtered.Count)   { "▼ " } else { "  " }
        $hint = "  ↑↓  navigate     Enter  select     type  filter / new name     Esc  cancel    $up$dn"
        $f   += "`e[$th;1H`e[7m$hint$(" " * [Math]::Max(0, $tw - $hint.Length))`e[0m"
        [Console]::Write($f)

        try { $k = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") } catch { break }

        $clr = ""; for ($ci = $promptRow; $ci -lt [Math]::Min($startRow + $maxVis + 1, $th); $ci++) { $clr += "`e[$ci;1H`e[K" }

        switch ($k.VirtualKeyCode) {
            38 {  # Up
                if ($sel -gt 0) { $sel-- }
                elseif ($sel -eq 0) { $sel = -1 }
            }
            40 {  # Down
                if ($sel -eq -1 -and $filtered.Count -gt 0) { $sel = 0 }
                elseif ($sel -lt $filtered.Count - 1) { $sel++ }
            }
            8 {  # Backspace
                if ($filter.Length -gt 0) { $filter = $filter.Substring(0, $filter.Length - 1); $sel = -1 }
            }
            13 {  # Enter
                $chosen = if ($sel -ge 0 -and $sel -lt $filtered.Count) { $filtered[$sel] }
                          elseif ($filter) { $filter }
                          else { $null }
                [Console]::Write($clr + "`e[$th;1H`e[K")
                if ($chosen) { [Console]::Write("`e[$promptRow;1H  `e[90m$Prompt`e[0m  `e[36m$chosen`e[0m`n`e[?25h") }
                else         { [Console]::Write("`e[$promptRow;1H`e[?25h") }
                return $chosen
            }
            27 {  # Esc — cancel entire operation, unwind to menu
                [Console]::Write($clr + "`e[$th;1H`e[K`e[$promptRow;1H`e[?25h")
                throw [System.OperationCanceledException]::new("ESC")
            }
        }

        # Printable character → append to filter
        if ([int]$k.Character -ge 32) { $filter += $k.Character; $sel = -1 }
    }

    [Console]::Write("`e[?25h")
    return $null
}


function Show-MainMenu {
    $menuDef = @(
        [pscustomobject]@{ Type = "header"; Label = "Remote" }
        [pscustomobject]@{ Type = "item";   Label = "Generate & Install SSH Key on A Remote Machine"; Choice = "1" }
        [pscustomobject]@{ Type = "item";   Label = "Install SSH Key on A Remote Machine";            Choice = "15" }
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
        [pscustomobject]@{ Type = "item";   Label = "Exit";                                           Choice = "q" }
    )

    $navItems = @($menuDef | Where-Object { $_.Type -eq "item" })

    # Pre-flatten menuDef into a linear sequence of screen rows (blank / header / item).
    # This lets us implement viewport scrolling without complicated row math.
    $flatRows = [System.Collections.Generic.List[pscustomobject]]::new()
    $ni = 0
    foreach ($e in $menuDef) {
        if ($e.Type -eq "header") {
            $flatRows.Add([pscustomobject]@{ Type = "blank";  Label = "";       nIdx = -1 })
            $flatRows.Add([pscustomobject]@{ Type = "header"; Label = $e.Label; nIdx = -1 })
        } else {
            $flatRows.Add([pscustomobject]@{ Type = "item"; Label = $e.Label; nIdx = $ni })
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
    $viewOff    = 0   # first flatRows index rendered (scrolling viewport)

    [Console]::Write("`e[?1049h`e[?25l")

    try {
        while ($running) {

            # ── Full render ────────────────────────────────────────────────────────
            if ($needFull) {
                $termWidth  = $Host.UI.RawUI.WindowSize.Width
                $termHeight = $Host.UI.RawUI.WindowSize.Height

                $menuRule     = "─" * [Math]::Max(0, $termWidth - 4)
                $menuTitle    = "🌊  HDD SSH Keys"
                $menuTitlePad = " " * [Math]::Max(0, [int](($termWidth - 4 - ($menuTitle.Length + 1)) / 2))

                # Content rows: 5..(termHeight-1). Status bar: termHeight.
                $contentStart = 5
                $contentEnd   = $termHeight - 1
                $contentRows  = [Math]::Max(1, $contentEnd - $contentStart + 1)

                # Find the flat index of the selected item
                $selFlatIdx = -1
                for ($fi = 0; $fi -lt $flatCount; $fi++) {
                    if ($flatRows[$fi].Type -eq "item" -and $flatRows[$fi].nIdx -eq $sel) {
                        $selFlatIdx = $fi; break
                    }
                }

                # Scroll viewport so selected item is always visible
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
                        "header" { $f += "`e[$row;1H  `e[90m  ▸ `e[1m$($fr.Label)`e[0m`e[K" }
                        "item"   {
                            $itemRows[$fr.nIdx] = $row
                            if ($fr.nIdx -eq $sel) {
                                $f += "`e[$row;1H  `e[1;36m▶ $($fr.Label)`e[0m`e[K"
                            } else {
                                $f += "`e[$row;1H`e[0m`e[37m    $($fr.Label)`e[0m`e[K"
                            }
                        }
                    }
                    $row++
                }

                # Clear any leftover rows between content and status bar
                while ($row -le $contentEnd) { $f += "`e[$row;1H`e[K"; $row++ }

                # Scroll indicators at right edge
                if ($viewOff -gt 0) {
                    $f += "`e[$contentStart;$($termWidth - 1)H`e[90m▲`e[0m"
                }
                if ($viewOff + $contentRows -lt $flatCount) {
                    $f += "`e[$contentEnd;$($termWidth - 1)H`e[90m▼`e[0m"
                }

                # Status bar — padded to fill full terminal width
                $statusBar = "  ↑↓ / Home / End  navigate     Enter  select     Q  quit     F1  help     F10  conf  "
                $f += "`e[$termHeight;1H`e[7m$statusBar$(" " * [Math]::Max(0, $termWidth - $statusBar.Length))`e[0m"

                [Console]::Write($f)
                $prevSel  = $sel
                $needFull = $false

            # ── Differential update (only when both rows are in the viewport) ──────
            } elseif ($prevSel -ne $sel) {
                if ($itemRows.ContainsKey($sel) -and $itemRows.ContainsKey($prevSel)) {
                    $r = $itemRows[$prevSel]
                    [Console]::Write("`e[${r};1H`e[0m`e[37m    $($navItems[$prevSel].Label)`e[0m`e[K")
                    $r = $itemRows[$sel]
                    [Console]::Write("`e[${r};1H  `e[1;36m▶ $($navItems[$sel].Label)`e[0m`e[K")
                    $prevSel = $sel
                } else {
                    $needFull = $true   # selection scrolled out of viewport — full redraw
                }
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
                        $opLabel   = $navItems[$sel].Label
                        $rule      = "─" * [Math]::Max(0, $termWidth - 4)
                        $opPad     = " " * [Math]::Max(0, [int](($termWidth - 4 - $opLabel.Length) / 2))
                        $opTitle   = "  " + $opPad + $opLabel
                        $opFill    = " " * [Math]::Max(0, $termWidth - $opTitle.Length)
                        $f  = "`e[2J`e[H`e[?25h`n"
                        $f += "  `e[96m$rule`e[0m`n"
                        $f += "`e[48;5;23m`e[1;97m$opTitle$opFill`e[0m`n"
                        $f += "  `e[96m$rule`e[0m`n`n"
                        [Console]::Write($f)
                        try {
                            $skipWait = Invoke-MenuChoice -Choice $choice
                            if (-not $skipWait) { Wait-UserAcknowledge }
                        } catch [System.OperationCanceledException] { }
                        [Console]::Write("`e[?25l")
                        $needFull = $true
                    }
                }
            }

            if ($key.Character -eq 'q' -or $key.Character -eq 'Q') {
                $running = $false
            }

            # F1 / F10 — inline overlay for Help and Conf
            if ($key.VirtualKeyCode -eq 112 -or $key.VirtualKeyCode -eq 121) {
                $fChoice = if ($key.VirtualKeyCode -eq 112) { "10" } else { "11" }
                $fLabel  = if ($key.VirtualKeyCode -eq 112) { "Help: Best Practices" } else { "Conf: Global Defaults" }
                $rule    = "─" * [Math]::Max(0, $termWidth - 4)
                $fPad    = " " * [Math]::Max(0, [int](($termWidth - 4 - $fLabel.Length) / 2))
                $fTitle  = "  " + $fPad + $fLabel
                $fFill   = " " * [Math]::Max(0, $termWidth - $fTitle.Length)
                $f  = "`e[2J`e[H`e[?25h`n"
                $f += "  `e[96m$rule`e[0m`n"
                $f += "`e[48;5;23m`e[1;97m$fTitle$fFill`e[0m`n"
                $f += "  `e[96m$rule`e[0m`n`n"
                [Console]::Write($f)
                try { $null = Invoke-MenuChoice -Choice $fChoice } catch [System.OperationCanceledException] { }
                if ($fChoice -ne "11") { Wait-UserAcknowledge }   # Conf has its own Q-to-exit; Help needs ack
                [Console]::Write("`e[?25l")
                $needFull = $true
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
            $RemoteHost = Read-RemoteHostAddress -SubnetPrefix "$DefaultSubnetPrefix"
            $RemoteUser = Read-RemoteUser -DefaultUser "$DefaultUserName"
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

            # Verify the key is actually installed on the remote before writing to config
            $keyPath    = "$env:USERPROFILE\.ssh\$KeyName"
            $testOut    = & ssh -i $keyPath -o BatchMode=yes -o ConnectTimeout=6 -o StrictHostKeyChecking=accept-new "$RemoteUser@$RemoteHostAddress" "echo ok" 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  ✅ Key verified on $RemoteHostAddress." -ForegroundColor Green
            } else {
                Write-Host "  ⚠  Could not verify '$KeyName' on $RemoteHostAddress — it may not be installed yet." -ForegroundColor Yellow
                $proceed = Read-HostWithDefault -Prompt "Add to config anyway? (y/N):" -Default "N"
                if ($proceed -notmatch '^[Yy]') { return }
            }
            Add-SSHKeyToHostConfig -KeyName $KeyName -RemoteHostName $RemoteHostName -RemoteHostAddress $RemoteHostAddress -RemoteUser $RemoteUser
        }
        "8" {
            $KeyName = Read-SSHKeyName
            if (-not $KeyName) { return }

            # Find hosts in SSH config that reference this key
            $keyHosts = Get-HostsUsingKey -KeyName $KeyName

            if ($keyHosts.Count -gt 0) {
                # Build selector list: ALL option + individual hosts
                $allLabel = "── ALL  ($($keyHosts.Count) host$(if ($keyHosts.Count -ne 1){'s'}))"
                $hostLabels = @($allLabel) + @($keyHosts | ForEach-Object {
                    if ($_.HostName) { "$($_.Alias)  ($($_.HostName))" } else { $_.Alias }
                })
                $selectedHost = Select-FromList -Items $hostLabels -Prompt "Remove key from remote host(s)  (Esc = skip)"

                $targetsToRemove = if ($selectedHost -and $selectedHost.StartsWith("──")) {
                    $keyHosts
                } elseif ($selectedHost) {
                    $alias = ($selectedHost -split '\s+\(')[0].Trim()
                    @($keyHosts | Where-Object { $_.Alias -eq $alias })
                } else { @() }

                foreach ($h in $targetsToRemove) {
                    $rUser = if ($h.User) { $h.User } else { $DefaultUserName }
                    $rHost = if ($h.HostName) { $h.HostName } else { $h.Alias }
                    Write-Host "  🔒 Removing key from $($h.Alias)…" -ForegroundColor DarkGray
                    Remove-SSHKeyFromRemote -RemoteUser $rUser -RemoteHost $rHost -KeyName $KeyName
                }
            } else {
                Write-Host "  ℹ  No configured hosts reference this key." -ForegroundColor DarkGray
            }

            # Delete local key files
            $privPath = "$env:USERPROFILE\.ssh\$KeyName"
            $pubPath  = "$privPath.pub"
            $deleted  = @()
            if (Test-Path $privPath) { Remove-Item $privPath -Force; $deleted += $privPath }
            if (Test-Path $pubPath)  { Remove-Item $pubPath  -Force; $deleted += $pubPath  }
            if ($deleted.Count -gt 0) {
                $deleted | ForEach-Object { Write-Host "  🗑  Deleted: $_" -ForegroundColor Green }
                Write-Host "  ✅ Key '$KeyName' removed locally." -ForegroundColor Green
            } else {
                Write-Host "  ⚠  No local key files found for '$KeyName'." -ForegroundColor Yellow
            }
        }
        "9" {
            # Step 1: pick a host
            $allHosts = Get-ConfiguredSSHHosts
            if ($allHosts.Count -eq 0) {
                Write-Host "  ℹ  No configured hosts found in ~/.ssh/config." -ForegroundColor DarkGray
                return
            }
            $hostName = Select-FromList -Items @($allHosts | ForEach-Object { $_.Alias }) -Prompt "Select host:"
            if (-not $hostName) { return }

            # Step 2: find IdentityFile keys under that host and pick one
            $configRaw = Get-Content "$env:USERPROFILE\.ssh\config" -Raw -Encoding UTF8
            $hostEsc   = [regex]::Escape($hostName)
            $block     = [regex]::Match($configRaw, "(?ms)^Host\s+$hostEsc\b.*?(?=^Host\s|\z)").Value
            $keyNames  = @([regex]::Matches($block, '(?m)^\s*IdentityFile\s+(.+?)\s*$') |
                           ForEach-Object { [System.IO.Path]::GetFileName($_.Groups[1].Value.Trim().Trim('"')) })

            if ($keyNames.Count -eq 0) {
                Write-Host "  ℹ  No IdentityFile entries found under host '$hostName'." -ForegroundColor DarkGray
                return
            }
            $KeyName = Select-FromList -Items $keyNames -Prompt "Select key to remove from '$hostName':"
            if (-not $KeyName) { return }

            Remove-IdentityFileFromConfigEntry -KeyName $KeyName -RemoteHostName $hostName
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
                $rule  = "─" * [Math]::Max(0, $tw - 4)
                $title = "Conf: Global Defaults"
                $tpad  = " " * [Math]::Max(0, [int](($tw - 4 - $title.Length) / 2))
                $cf  = "`e[2J`e[H"
                $cf += "`e[2;1H  `e[96m$rule`e[0m`e[K"
                $cf += "`e[3;1H  `e[96m$tpad$title`e[0m`e[K"
                $cf += "`e[4;1H  `e[96m$rule`e[0m`e[K"
                for ($i = 0; $i -lt $fieldDefs.Count; $i++) {
                    $val = (Get-Variable -Name $fieldDefs[$i].Name -Scope Script -ErrorAction SilentlyContinue).Value
                    $disp = if ($fieldDefs[$i].Name -eq "DefaultPassword" -and $val) { "*" * $val.Length } else { $val }
                    $row = 6 + $i
                    $cf += "`e[$row;1H"
                    if ($i -eq $confSel) {
                        $cf += "  `e[1;36m▶ $($fieldDefs[$i].Label)  `e[0;36m$disp`e[0m`e[K"
                    } else {
                        $cf += "  `e[0;37m    $($fieldDefs[$i].Label)  `e[90m$disp`e[0m`e[K"
                    }
                }
                $hint = "  ↑↓  navigate     Enter  edit     Q  back  "
                $cf += "`e[$th;1H`e[7m$hint$(" " * [Math]::Max(0, $tw - $hint.Length))`e[0m"
                [Console]::Write($cf)

                try { $k = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") } catch { break }

                switch ($k.VirtualKeyCode) {
                    38 { $confSel = ($confSel - 1 + $fieldDefs.Count) % $fieldDefs.Count }
                    40 { $confSel = ($confSel + 1) % $fieldDefs.Count }
                    13 {
                        $row = 6 + $confSel
                        [Console]::Write("`e[$row;1H`e[K  `e[1;33m▶ $($fieldDefs[$confSel].Label)  `e[0;33m")
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
            Write-Host "  ✅ Defaults updated for this session." -ForegroundColor Green
            Write-Host "  ℹ  To persist: pass as script parameters (-DefaultUserName, etc.)" -ForegroundColor Yellow
        }
        "15" {
            $KeyName = Read-SSHKeyName
            if (-not (Find-PrivateKeyInHost -KeyName $KeyName -ReturnResult $true)) {
                Write-Host "  ❌ Key '$KeyName' not found locally. Use 'Generate & Install' to create it first." -ForegroundColor Red
                return
            }
            Install-SSHKeyOnRemote -KeyName $KeyName
        }
        "12" { Remove-HostFromSSHConfig }
        "13" { Show-SSHConfigFile }
        "14" { Edit-SSHConfigFile; return $true }  # returns directly to menu (no "press any key")
    }
}


#region Main Functions
function Install-SSHKeyOnRemote {
    # Installs an already-existing local key onto a remote machine and registers
    # the host in ~/.ssh/config. Called by both Deploy-SSHKeyToRemote (which may
    # generate the key first) and directly from the "Install only" menu item.
    param (
        [string]$KeyName
    )

    $PublicKey = Get-PublicKeyInHost -KeyName $KeyName
    if (-not $PublicKey) { return }

    $RemoteHostAddress = Read-RemoteHostAddress -SubnetPrefix "$DefaultSubnetPrefix"
    $selectedAlias     = $script:_LastSelectedAlias   # set by Read-RemoteHostAddress when config entry chosen
    $RemoteUser        = Read-RemoteUser -DefaultUser "$DefaultUserName"

    $target = Resolve-SSHTarget -RemoteHostAddress $RemoteHostAddress -RemoteUser $RemoteUser
    Write-Host "  🔃 Connecting to $target..."

    try {
        if (![string]::IsNullOrEmpty($DefaultPassword) -and (Get-Command sshpass -ErrorAction SilentlyContinue)) {
            Write-Host "  ℹ  Using sshpass with stored password." -ForegroundColor DarkGray
            $RemoteHostName = $PublicKey | sshpass -p $DefaultPassword ssh -o StrictHostKeyChecking=accept-new $target 'mkdir -p .ssh && cat >> .ssh/authorized_keys && hostname'
        } else {
            $RemoteHostName = $PublicKey | ssh $target 'mkdir -p .ssh && cat >> .ssh/authorized_keys && hostname'
        }
        Write-Host "  ✅ SSH Public Key installed successfully." -ForegroundColor Green

        # When connected via a config alias, default to that alias — not the remote hostname
        $defaultAlias = if ($selectedAlias) { $selectedAlias } else { $RemoteHostName }
        Write-Host "  🏷  Remote hostname: $RemoteHostName" -ForegroundColor DarkGray
        $hostAlias = Read-HostWithDefault -Prompt "Name this Host in ~/.ssh/config:" -Default $defaultAlias
        if ([string]::IsNullOrWhiteSpace($hostAlias)) { $hostAlias = $defaultAlias }

        Write-Host "  Registering key to SSH config as '$hostAlias'..."
        Add-SSHKeyToHostConfig -KeyName $KeyName -RemoteHostAddress $RemoteHostAddress -RemoteHostName $hostAlias -RemoteUser $RemoteUser
    } catch {
        Write-Host "  ❌ Failed to inject SSH key. Check network, credentials, or host status." -ForegroundColor Red
    }
}


function Deploy-SSHKeyToRemote {
    param (
        [string]$KeyName
    )

    if (-not (Find-PrivateKeyInHost -KeyName $KeyName -ReturnResult $true)) {
        Write-Host "`n${P}🔑 Key does not exist. Generating..." -ForegroundColor Yellow
        $Comment = Read-SSHKeyComment -DefaultComment "$KeyName$DefaultCommentSuffix"
        Add-SSHKeyInHost -KeyName $KeyName -Comment $Comment
    } else {
        Write-Host "`n${P}ℹ  Key already exists. Proceeding with installation...`n" -ForegroundColor Cyan
    }

    Install-SSHKeyOnRemote -KeyName $KeyName
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
            Write-Host "  ❌ Connection refused: $RemoteHost is not accepting SSH connections." -ForegroundColor Red
            if ($ReturnResult) { return $false } else { return }
        }
        elseif ($result -match "Name or service not known" -or $result -match "Could not resolve hostname") {
            Write-Host "  ❌ DNS error: Could not resolve $RemoteHost." -ForegroundColor Red
            if ($ReturnResult) { return $false } else { return }
        }
        elseif ($result -match "Permission denied") {
            Write-Host "  ⚠️ SSH reachable, but permission denied for user '$RemoteUser'." -ForegroundColor Yellow
            if ($ReturnResult) { return $true } else { return }  # SSH is reachable, credentials just need fixing
        }
        else {
            Write-Host "  ✅ SSH connection to $RemoteHost is successful." -ForegroundColor Green
            if ($ReturnResult) { return $true } else { return }
        }

    } catch {
        Write-Host "  ❌ Unexpected error during SSH test:" -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)"
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
        Write-Host "  ✅ SSH key removed from remote authorized_keys." -ForegroundColor Green

        $privPath = "$env:USERPROFILE\.ssh\$KeyName"
        $pubPath  = "$privPath.pub"
        Confirm-UserChoice -Message "  Remove local key '$KeyName' from THIS machine? ⚠" -Action {
            if (Test-Path $privPath) { Remove-Item $privPath -Force; Write-Host "  🗑  Deleted: $privPath" -ForegroundColor Green }
            if (Test-Path $pubPath)  { Remove-Item $pubPath  -Force; Write-Host "  🗑  Deleted: $pubPath"  -ForegroundColor Green }
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

    # Build custom ANSI table
    $wNum = ([string]$rows.Count).Length
    $wKey = [Math]::Max(3, ($rows | ForEach-Object { $_.Key.Length } | Measure-Object -Maximum).Maximum)
    $wUse = [Math]::Max(5, ($rows | ForEach-Object { $_.Usage.Length } | Measure-Object -Maximum).Maximum)

    $wPub  = 3
    $wPriv = 4
    $top = "  ┌$("─" * ($wNum + 2))┬$("─" * ($wKey + 2))┬$("─" * ($wPub + 2))┬$("─" * ($wPriv + 2))┬$("─" * ($wUse + 2))┐"
    $hdr = "  │ $(" " * [Math]::Max(0, $wNum - 1))# │ $("Key".PadRight($wKey)) │ Pub │ Priv │ $("Usage".PadRight($wUse)) │"
    $mid = "  ├$("─" * ($wNum + 2))┼$("─" * ($wKey + 2))┼$("─" * ($wPub + 2))┼$("─" * ($wPriv + 2))┼$("─" * ($wUse + 2))┤"
    $bot = "  └$("─" * ($wNum + 2))┴$("─" * ($wKey + 2))┴$("─" * ($wPub + 2))┴$("─" * ($wPriv + 2))┴$("─" * ($wUse + 2))┘"

    $tableLines = @()
    $tableLines += "`e[36m$top`e[0m"
    $tableLines += "`e[1;37m$hdr`e[0m"
    $tableLines += "`e[36m$mid`e[0m"
    foreach ($r in $rows) {
        $num   = [string]$r."#"
        $pubC  = if ($r.Public  -eq "✅") { "`e[32m ✓ `e[0m" } else { "`e[31m ✗ `e[0m" }
        $privC = if ($r.Private -eq "✅") { "`e[32m ✓  `e[0m" } else { "`e[31m ✗  `e[0m" }
        $tableLines += "  `e[36m│`e[0m $($num.PadLeft($wNum)) `e[36m│`e[0m `e[36m$($r.Key.PadRight($wKey))`e[0m `e[36m│`e[0m$pubC`e[36m│`e[0m$privC`e[36m│`e[0m `e[37m$($r.Usage.PadRight($wUse))`e[0m `e[36m│`e[0m"
    }
    $tableLines += "`e[36m$bot`e[0m"

    Show-Paged -Lines $tableLines
}
#endregion


#region Subfunctions
function Add-SSHKeyInHost {
    param (
        [string]$KeyName,
        [string]$Comment
    )

    # Collect passphrase with masked input
    Write-Host -NoNewline "  `e[36mPassphrase`e[0m `e[90m(empty = passwordless)`e[0m  " -ForegroundColor Cyan
    $securePass = Read-Host -AsSecureString
    $Password   = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                      [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass))

    # Themed summary — password shown as stars
    $stars = if ($Password) { "*" * $Password.Length } else { "`e[90m(none)`e[0m" }
    Write-Host ""
    Write-Host "  `e[90m  key      `e[0m`e[36m$KeyName`e[0m"
    Write-Host "  `e[90m  comment  `e[0m`e[36m$Comment`e[0m"
    Write-Host "  `e[90m  password `e[0m`e[90m$stars`e[0m"
    Write-Host ""

    # Clear any selector status bar remnant before ssh-keygen output scrolls
    $th = $Host.UI.RawUI.WindowSize.Height
    [Console]::Write("`e[s`e[$th;1H`e[K`e[u")

    Write-Host "  `e[90mGenerating SSH key…`e[0m"

    $sshKeygenCmd = "ssh-keygen -t ed25519 -f `"$env:USERPROFILE\.ssh\$KeyName`" -C `"$Comment`""
    $sshKeygenCmd += if ($Password) { " -N `"$Password`"" } else { " -N ''" }
    Invoke-Expression $sshKeygenCmd

    Write-Host "  `e[32m✓`e[0m  `e[36m$env:USERPROFILE\.ssh\$KeyName`e[0m  generated." -ForegroundColor Green
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
    return Read-HostWithDefault -Prompt "Remote username:" -Default $DefaultUser
}


function Read-RemoteHostName {
    param (
        [string]$SubnetPrefix = "$DefaultSubnetPrefix"
    )

    $hosts = Get-ConfiguredSSHHosts
    if ($hosts.Count -gt 0) {
        $labels   = @($hosts | ForEach-Object { $_.Alias })
        $selected = Select-FromList -Items $labels -Prompt "Select host alias"
        if ($selected) { return $selected }
    }

    $name = Read-ColoredInput -Prompt "  Enter the host alias / hostname" -ForegroundColor "Cyan"
    if ([string]::IsNullOrWhiteSpace($name)) {
        Write-Host "  ❗ Hostname is required." -ForegroundColor Red
        return $null
    }
    return $name
}


function Read-RemoteHostAddress {
    param (
        [string]$SubnetPrefix = "$DefaultSubnetPrefix"
    )

    $script:_LastSelectedAlias = $null   # reset; set below if a config entry is chosen

    $hosts = Get-ConfiguredSSHHosts
    if ($hosts.Count -gt 0) {
        $labels   = @($hosts | ForEach-Object {
            if ($_.HostName) { "$($_.Alias)  ($($_.HostName))" } else { $_.Alias }
        })
        $selected = Select-FromList -Items $labels -Prompt "Select remote host"
        if ($selected) {
            $alias = ($selected -split '\s+\(')[0].Trim()
            $h     = $hosts | Where-Object { $_.Alias -eq $alias } | Select-Object -First 1
            $addr  = if ($h -and $h.HostName) { $h.HostName } else { $alias }
            $script:_LastSelectedAlias = $alias
            return $addr
        }
    }

    $RemoteHost = Read-ColoredInput -Prompt "  Enter remote IP / hostname (or last 1–3 digits for $SubnetPrefix.xx)" -ForegroundColor "Cyan"
    if ($RemoteHost -match "^\d{1,3}$") {
        return "$SubnetPrefix.$RemoteHost"
    }
    return $RemoteHost
}


function Read-SSHKeyName {
    $keys = Get-AvailableSSHKeys
    if ($keys.Count -gt 0) {
        $selected = Select-FromList -Items $keys -Prompt "Select SSH key"
        if ($selected) { return $selected }
    }
    $KeyName = Read-ColoredInput -Prompt "  Enter SSH key name" -ForegroundColor "Cyan"
    return Resolve-NullToAction -Action { Read-SSHKeyName } -RequiredValue $KeyName -RequiredValueLabel "Key Name"
}


function Read-SSHKeyComment {
    param ([string]$DefaultComment)
    return Read-HostWithDefault -Prompt "Key comment:" -Default $DefaultComment
}


function Read-ColoredInput {
    param (
        [string]$Prompt,
        [ConsoleColor]$ForegroundColor = "Cyan"
    )

    Write-Host -NoNewline "$Prompt " -ForegroundColor $ForegroundColor
    return Read-Host
}


function Read-HostWithDefault {
    # Shows a prompt with the default value pre-filled and editable.
    param(
        [string]$Prompt,
        [string]$Default = ""
    )
    Write-Host -NoNewline "  `e[36m$Prompt`e[0m  " -ForegroundColor Cyan
    [Console]::Write($Default)
    [Console]::Write("`e[?25h")
    $buf = $Default
    while ($true) {
        $k = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        if ($k.VirtualKeyCode -eq 13) {        # Enter
            [Console]::WriteLine()
            return $buf
        } elseif ($k.VirtualKeyCode -eq 27) {  # Esc — cancel operation
            [Console]::Write("`e[?25h")
            throw [System.OperationCanceledException]::new("ESC")
        } elseif ($k.VirtualKeyCode -eq 8) {   # Backspace
            if ($buf.Length -gt 0) {
                $buf = $buf.Substring(0, $buf.Length - 1)
                [Console]::Write("`b `b")
            }
        } elseif ([int]$k.Character -ge 32) {  # Printable
            $buf += $k.Character
            [Console]::Write([string]$k.Character)
        }
    }
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
    $hosts    = Get-ConfiguredSSHHosts
    $hostName = $null
    if ($hosts.Count -gt 0) {
        $labels   = @($hosts | ForEach-Object { $_.Alias })
        $hostName = Select-FromList -Items $labels -Prompt "Select host to remove"
    }
    if (-not $hostName) {
        $hostName = Read-ColoredInput -Prompt "  Enter the Host alias to remove" -ForegroundColor "Cyan"
    }
    if ([string]::IsNullOrWhiteSpace($hostName)) {
        Write-Host "  ❗ Host alias is required." -ForegroundColor Red
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
        Write-Host "  ❌ SSH config not found at $configPath" -ForegroundColor Red
        return
    }

    $lines = Get-Content $configPath
    $out   = @()

    foreach ($line in $lines) {
        if ($line -match '^\s*$') {
            $out += ""
        } elseif ($line -match '^\s*#') {
            $out += "`e[90m  $line`e[0m"
        } elseif ($line -match '^(Host)\s+(.+)$') {
            $out += ""
            $out += "  `e[1;96mHost`e[0m `e[97m$($Matches[2])`e[0m"
        } elseif ($line -match '^\s*(IdentityFile)\s+(.+)$') {
            $out += "    `e[93m$($Matches[1])`e[0m `e[32m$($Matches[2])`e[0m"
        } elseif ($line -match '^\s*(HostName|User|Port|ForwardAgent|ServerAliveInterval|ServerAliveCountMax|IdentitiesOnly|AddKeysToAgent)\s+(.+)$') {
            $out += "    `e[93m$($Matches[1])`e[0m `e[37m$($Matches[2])`e[0m"
        } elseif ($line -match '^\s*(\w+)\s+(.+)$') {
            $out += "    `e[33m$($Matches[1])`e[0m `e[37m$($Matches[2])`e[0m"
        } else {
            $out += "  `e[37m$line`e[0m"
        }
    }

    Write-Host ""
    Write-Host "  `e[90m$configPath`e[0m"
    Write-Host "  `e[90m$('─' * $configPath.Length)`e[0m"
    $out | ForEach-Object { [Console]::WriteLine($_) }
}


function Edit-SSHConfigFile {
    $configPath = "$env:USERPROFILE\.ssh\config"
    if (-not (Test-Path $configPath)) {
        Write-Host "  ❌ SSH config not found at $configPath" -ForegroundColor Red
        return
    }

    $editor = $null
    if ($env:EDITOR -and (Get-Command $env:EDITOR -ErrorAction SilentlyContinue)) {
        $editor = $env:EDITOR
    } else {
        foreach ($e in @("code", "nvim", "vim", "nano", "notepad.exe")) {
            if (Get-Command $e -ErrorAction SilentlyContinue) { $editor = $e; break }
        }
    }
    if (-not $editor) { $editor = "notepad.exe" }

    Write-Host "  Opening in $editor..." -ForegroundColor DarkGray
    try {
        & $editor $configPath
        Write-Host "  ✅ Done." -ForegroundColor Green
    } catch {
        Write-Host "  ❌ Could not open editor '$editor': $_" -ForegroundColor Red
    }
}


Show-MainMenu
