# lib/ps/config-display.ps1 — SSH config viewer, key inventory display, host removal
# EXPORTS: Remove-HostFromSSHConfig  Show-SSHConfigFile  Edit-SSHConfigFile
#          Show-SSHKeyInventory  _ViewSSHKey  _DisplayKeyFile


function Remove-HostFromSSHConfig {
    $configPath = "$env:USERPROFILE\.ssh\config"
    Show-OpBanner @("config", $configPath)

    $hosts    = Get-ConfiguredSSHHosts
    $hostName = $null
    if ($hosts.Count -gt 0) {
        $labels   = @($hosts | ForEach-Object { $_.Alias })
        try {
            $hostName = Select-FromList -Items $labels -Prompt "Select host to remove"
        } catch [System.OperationCanceledException] { return }
    }
    if (-not $hostName) {
        $hostName = Read-ColoredInput -Prompt "  Enter the Host alias to remove" -ForegroundColor "Cyan"
    }
    if ([string]::IsNullOrWhiteSpace($hostName)) {
        Write-Out 'error' "Host alias is required."
        return
    }

    if (-not (Test-Path $configPath)) {
        Write-Out 'error' "SSH config not found at $configPath"
        return
    }

    $config  = Get-Content $configPath -Raw -Encoding UTF8
    $pattern = "(?ms)^Host\s+$([regex]::Escape($hostName))\b.*?(?=^Host\s|\z)"
    $match   = [regex]::Match($config, $pattern)

    if (-not $match.Success) {
        Write-Out 'warn' "No Host block found for '$hostName'"
        return
    }

    Write-Host ""
    Write-Out 'dim' "Block that will be removed:"
    Write-Host $match.Value -ForegroundColor Gray

    $confirm = Read-ColoredInput -Prompt "Remove this block? [y/N]" -ForegroundColor "Yellow"
    if ($confirm -notmatch '^(y|yes)$') {
        Write-Out 'warn' "Cancelled."
        return
    }

    $newConfig = ($config -replace [regex]::Escape($match.Value), "").TrimEnd() + "`n"
    [System.IO.File]::WriteAllText($configPath, $newConfig, [System.Text.Encoding]::UTF8)
    Write-Out 'ok' "Host '$hostName' removed from SSH config."
}


function Show-SSHConfigFile {
    $configPath = "$env:USERPROFILE\.ssh\config"
    if (-not (Test-Path $configPath)) {
        Write-Out 'error' "SSH config not found at $configPath"
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

    # Buffer-mode op banner at row 5
    Show-OpBanner @("config", $configPath) -StartRow 5
    $bannerBuf  = $script:_OpBannerBuf
    $bannerRows = $script:_OpBannerRows

    $termH       = $Host.UI.RawUI.WindowSize.Height
    $termW       = $Host.UI.RawUI.WindowSize.Width
    $contentRows = [Math]::Max(1, $termH - 5 - $bannerRows - 1)
    $total       = $out.Count
    $off         = 0
    [Console]::Write("`e[?25l")

    while ($true) {
        $off = [Math]::Max(0, [Math]::Min($off, [Math]::Max(0, $total - $contentRows)))

        $rule  = "-" * [Math]::Max(0, $termW - 4)
        $label = "`u{1F441}`u{FE0F}  View SSH Config"
        $lpad  = " " * [Math]::Max(0, [int](($termW - 4 - $label.Length) / 2))
        $lFill = " " * [Math]::Max(0, $termW - (2 + $lpad.Length + $label.Length))

        $f  = "`e[2J`e[H"
        $f += "`e[2;1H  `e[96m$rule`e[0m`e[K"
        $f += "`e[3;1H`e[48;5;23m`e[1;97m  $lpad$label$lFill`e[0m"
        $f += "`e[4;1H  `e[96m$rule`e[0m`e[K"
        $f += $bannerBuf

        $row = 5 + $bannerRows
        for ($i = $off; $i -lt [Math]::Min($off + $contentRows, $total); $i++) {
            $f += "`e[$row;1H$($out[$i])`e[K"
            $row++
        }
        while ($row -le ($termH - 1)) { $f += "`e[$row;1H`e[K"; $row++ }

        $pct    = if ($total -le $contentRows) { "all" } else { "$([int](([Math]::Min($off + $contentRows, $total)) * 100 / $total))%" }
        $status = "  Up/Dn / PgUp / PgDn  scroll     Home  top     End  bottom     Q  close     $pct  "
        $f     += "`e[$termH;1H`e[7m$status$(" " * [Math]::Max(0, $termW - $status.Length))`e[0m"
        [Console]::Write($f)

        try { $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") } catch { break }

        switch ($key.VirtualKeyCode) {
            38 { $off-- }
            40 { $off++ }
            33 { $off -= $contentRows }
            34 { $off += $contentRows }
            36 { $off = 0 }
            35 { $off = $total - $contentRows }
        }
        if ($key.Character -eq 'q' -or $key.Character -eq 'Q') { break }

        $nW = $Host.UI.RawUI.WindowSize.Width; $nH = $Host.UI.RawUI.WindowSize.Height
        if ($nW -ne $termW -or $nH -ne $termH) {
            $termW = $nW; $termH = $nH
            $contentRows = [Math]::Max(1, $termH - 5 - $bannerRows - 1)
        }
    }
    [Console]::Write("`e[?25h")
}


function Edit-SSHConfigFile {
    $configPath = "$env:USERPROFILE\.ssh\config"
    if (-not (Test-Path $configPath)) {
        Write-Out 'error' "SSH config not found at $configPath"
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

    Write-Out 'dim' "Opening in $editor..."
    try {
        & $editor $configPath
        Write-Out 'ok' "Done."
    } catch {
        Write-Out 'error' "Could not open editor '$editor': $_"
    }
}


function Show-SSHKeyInventory {
    param(
        [string]$SshDir     = "$env:USERPROFILE\.ssh",
        [string]$ConfigPath = "$env:USERPROFILE\.ssh\config"
    )

    if (-not (Test-Path $SshDir)) {
        Write-Out 'error' ".ssh directory not found at $SshDir"
        return
    }

    $allFiles = Get-ChildItem -Path $SshDir -File -ErrorAction SilentlyContinue
    $pubFiles = $allFiles | Where-Object { $_.Extension -ieq ".pub" }
    $excludeNames = @("config","known_hosts","known_hosts.old","authorized_keys","authorized_keys2","environment","rc")
    $privateCandidates = $allFiles | Where-Object {
        $_.Extension -ine ".pub" -and ($excludeNames -notcontains $_.Name.ToLowerInvariant())
    }

    $pubKeyNames  = $pubFiles | ForEach-Object { $_.BaseName }
    $privKeyNames = $privateCandidates | ForEach-Object { $_.Name }
    $sortedKeys   = @($pubKeyNames + $privKeyNames) | Sort-Object -Unique

    $usageMap = @{}
    if (Test-Path $ConfigPath) {
        $config = Get-Content -Path $ConfigPath -Raw -Encoding UTF8
        foreach ($hb in [regex]::Matches($config, "(?ms)^Host\s+(.+?)\s*$.*?(?=^Host\s|\z)")) {
            $hosts = ($hb.Groups[1].Value.Trim()) -split '\s+' | Where-Object { $_ }
            foreach ($im in [regex]::Matches($hb.Value, '(?m)^\s*IdentityFile\s+(.+?)\s*$')) {
                $p = $im.Groups[1].Value.Trim().Trim('"')
                $p = $p -replace '^\~', $env:USERPROFILE
                $p = $p -replace '^\$HOME', $env:USERPROFILE
                $p = $p -replace '^\`$HOME', $env:USERPROFILE
                if (-not [System.IO.Path]::IsPathRooted($p)) { $p = Join-Path $SshDir $p }
                $keyName = [System.IO.Path]::GetFileName($p)
                if (-not $usageMap.ContainsKey($keyName)) {
                    $usageMap[$keyName] = New-Object System.Collections.Generic.HashSet[string]
                }
                foreach ($h in $hosts) { [void]$usageMap[$keyName].Add($h) }
            }
        }
    }

    if ($sortedKeys.Count -eq 0) {
        Write-Out 'warn' "No key files found in $SshDir"
        return
    }

    # Build row objects
    $rows = @()
    $idx  = 1
    foreach ($keyName in $sortedKeys) {
        $privatePath = Join-Path $SshDir $keyName
        $publicPath  = "$privatePath.pub"
        $privateOk   = Test-Path $privatePath -PathType Leaf
        $publicOk    = Test-Path $publicPath  -PathType Leaf
        $usage = if ($usageMap.ContainsKey($keyName)) {
            ($usageMap[$keyName] | Sort-Object) -join ", "
        } else { "" }
        $rows += [pscustomobject]@{
            Num     = $idx
            Key     = $keyName
            Public  = $publicOk
            Private = $privateOk
            Usage   = $usage
        }
        $idx++
    }

    $wNum  = ([string]$rows.Count).Length
    $wKey  = [Math]::Max(3, ($rows | ForEach-Object { $_.Key.Length } | Measure-Object -Maximum).Maximum)
    $wUse  = [Math]::Max(5, ($rows | ForEach-Object { $_.Usage.Length } | Measure-Object -Maximum).Maximum)
    $wPub  = 3
    $wPriv = 4

    $r1 = "-" * ($wNum  + 2)
    $r2 = "-" * ($wKey  + 2)
    $r3 = "-" * ($wPub  + 2)
    $r4 = "-" * ($wPriv + 1)
    $r5 = "-" * ($wUse  + 2)
    $tblTop = "  +${r1}+${r2}+${r3}+${r4}+${r5}+"
    $tblHdr = "  | $(" " * [Math]::Max(0, $wNum - 1))# | $("Key".PadRight($wKey)) | Pub | Prv | $("Usage".PadRight($wUse)) |"
    $CY = "`e[32m  Y  `e[0m"
    $CN = "`e[31m  N  `e[0m"
    $BAR = "`e[97m|`e[0m"

    # Buffer-mode op banner at row 5
    Show-OpBanner @("ssh dir", $SshDir) -StartRow 5
    $bannerBuf  = $script:_OpBannerBuf
    $bannerRows = $script:_OpBannerRows

    $sel        = 0
    $off        = 0
    $needRedraw = $true
    $keyCount   = $sortedKeys.Count

    [Console]::Write("`e[?25l")

    while ($true) {
        if ($needRedraw) {
            $termW = $Host.UI.RawUI.WindowSize.Width
            $termH = $Host.UI.RawUI.WindowSize.Height

            $hdrRows     = 7 + $bannerRows   # top-border + header + sep = 3 table rows
            $contentRows = [Math]::Max(1, $termH - $hdrRows - 2)

            if ($sel -lt $off) { $off = $sel }
            elseif ($sel -ge $off + $contentRows) { $off = $sel - $contentRows + 1 }
            if ($off -lt 0) { $off = 0 }

            $rule  = "-" * [Math]::Max(0, $termW - 4)
            $label = "`u{1F5DD}`u{FE0F}  List SSH Keys"
            $tpad  = " " * [Math]::Max(0, [int](($termW - 4 - $label.Length) / 2))
            $tFill = " " * [Math]::Max(0, $termW - (2 + $tpad.Length + $label.Length))

            $g  = "`e[2J`e[H"
            $g += "`e[2;1H  `e[96m$rule`e[0m`e[K"
            $g += "`e[3;1H`e[48;5;23m`e[1;97m  $tpad$label$tFill`e[0m"
            $g += "`e[4;1H  `e[96m$rule`e[0m`e[K"
            $g += $bannerBuf
            $g += "`e[$( 5 + $bannerRows);1H`e[97m$tblTop`e[0m`e[K"
            $g += "`e[$( 6 + $bannerRows);1H`e[1;37m$tblHdr`e[0m`e[K"
            $g += "`e[$( 7 + $bannerRows);1H`e[97m$tblTop`e[0m`e[K"

            $row = 8 + $bannerRows
            for ($i = $off; $i -lt [Math]::Min($off + $contentRows, $keyCount); $i++) {
                $r      = $rows[$i]
                $numStr = ([string]$r.Num).PadLeft($wNum)
                if ($i -eq $sel) {
                    $pubS = if ($r.Public)  { "  Y  " } else { "  N  " }
                    $prvS = if ($r.Private) { "  Y  " } else { "  N  " }
                    $g += "`e[$row;1H`e[48;5;6m`e[1;97m  | $numStr | $($r.Key.PadRight($wKey)) |$pubS|$prvS| $($r.Usage.PadRight($wUse)) |`e[K`e[0m"
                } else {
                    $pubC = if ($r.Public)  { $CY } else { $CN }
                    $prvC = if ($r.Private) { $CY } else { $CN }
                    $g += "`e[$row;1H  $BAR $numStr $BAR `e[36m$($r.Key.PadRight($wKey))`e[0m $BAR$pubC$BAR$prvC$BAR `e[37m$($r.Usage.PadRight($wUse))`e[0m $BAR`e[K"
                }
                $row++
            }

            # Bottom border
            $g += "`e[$row;1H`e[97m$tblTop`e[0m`e[K"; $row++
            while ($row -le ($termH - 1)) { $g += "`e[$row;1H`e[K"; $row++ }

            $hint = "  Up/Dn navigate   Enter view key   Q close"
            $g   += "`e[$termH;1H`e[7m$hint$(" " * [Math]::Max(0, $termW - $hint.Length))`e[0m"
            [Console]::Write($g)
            $needRedraw = $false
        }

        try { $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") } catch { break }

        $moved = $false
        switch ($key.VirtualKeyCode) {
            38 { if ($sel -gt 0)              { $sel--;           $moved = $true } }  # Up
            40 { if ($sel -lt $keyCount - 1)  { $sel++;           $moved = $true } }  # Down
            33 { $sel = [Math]::Max(0, $sel - 5);                 $moved = $true }    # PgUp
            34 { $sel = [Math]::Min($keyCount - 1, $sel + 5);     $moved = $true }    # PgDn
            36 { $sel = 0;                                         $moved = $true }    # Home
            35 { $sel = $keyCount - 1;                             $moved = $true }    # End
            13 {  # Enter — view key
                [Console]::Write("`e[2J`e[H")
                _ViewSSHKey $sortedKeys[$sel] $SshDir
                $needRedraw = $true
            }
        }
        if ($moved) { $needRedraw = $true }
        if ($key.Character -eq 'q' -or $key.Character -eq 'Q') { break }

        $nW = $Host.UI.RawUI.WindowSize.Width; $nH = $Host.UI.RawUI.WindowSize.Height
        if ($nW -ne $termW -or $nH -ne $termH) { $needRedraw = $true }
    }

    [Console]::Write("`e[?25h")
}


function _ViewSSHKey {
    # Show a key viewer submenu then display the selected key file in a pager.
    param([string]$KeyName, [string]$SshDir = "$env:USERPROFILE\.ssh")

    $termW = $Host.UI.RawUI.WindowSize.Width
    $termH = $Host.UI.RawUI.WindowSize.Height
    $rule  = "-" * [Math]::Max(0, $termW - 4)
    $label = "`u{1F5DD}`u{FE0F}  List SSH Keys"
    $tpad  = " " * [Math]::Max(0, [int](($termW - 4 - $label.Length) / 2))
    $tFill = " " * [Math]::Max(0, $termW - (2 + $tpad.Length + $label.Length))
    [Console]::Write("`e[2;1H  `e[96m$rule`e[0m`e[K")
    [Console]::Write("`e[3;1H`e[48;5;23m`e[1;97m  $tpad$label$tFill`e[0m")
    [Console]::Write("`e[4;1H  `e[96m$rule`e[0m`e[K")

    $options = [System.Collections.Generic.List[string]]::new()
    if (Test-Path "$SshDir\$KeyName.pub") { $options.Add("Public Key  (.pub)") }
    if (Test-Path "$SshDir\$KeyName")     { $options.Add("Private Key (handle with care)") }
    $options.Add("Back")

    $chosen = $null
    try {
        $chosen = Select-FromList -Items $options.ToArray() -Prompt "View — $KeyName" -StrictList
    } catch [System.OperationCanceledException] { return }
    if (-not $chosen -or $chosen -eq "Back") { return }

    if ($chosen -like "Public Key*") {
        _DisplayKeyFile "$SshDir\$KeyName.pub" "Public Key — $KeyName.pub"
    } elseif ($chosen -like "Private Key*") {
        # Confirm before showing private key
        $termH = $Host.UI.RawUI.WindowSize.Height
        $warn  = "  WARNING: You are about to display a private key on screen."
        $warnPad = " " * [Math]::Max(0, $termW - $warn.Length)
        [Console]::Write("`e[$($termH - 3);1H`e[41m`e[1;97m$warn$warnPad`e[0m")
        [Console]::Write("`e[$($termH - 2);1H  `e[97mShow private key contents? [y/N] `e[0m`e[?25h")
        try { $k = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") } catch { return }
        [Console]::Write("`e[?25l")
        if ($k.Character -ne 'y' -and $k.Character -ne 'Y') { return }
        _DisplayKeyFile "$SshDir\$KeyName" "Private Key — $KeyName"
    }
}


function _DisplayKeyFile {
    # Full-screen pager for a raw key file.
    param([string]$FilePath, [string]$Title)
    if (-not (Test-Path $FilePath)) {
        Write-Out 'error' "File not found: $FilePath"
        return
    }

    $fileLines = Get-Content $FilePath
    $out = @($fileLines | ForEach-Object { "  `e[37m$_`e[0m" })

    $termW       = $Host.UI.RawUI.WindowSize.Width
    $termH       = $Host.UI.RawUI.WindowSize.Height
    $total       = $out.Count
    $contentRows = [Math]::Max(1, $termH - 6)
    $off         = 0

    [Console]::Write("`e[?25l")
    while ($true) {
        $off = [Math]::Max(0, [Math]::Min($off, [Math]::Max(0, $total - $contentRows)))

        $rule  = "-" * [Math]::Max(0, $termW - 4)
        $tFill = " " * [Math]::Max(0, $termW - (2 + $Title.Length))
        $g  = "`e[2J`e[H"
        $g += "`e[2;1H  `e[96m$rule`e[0m`e[K"
        $g += "`e[3;1H`e[48;5;23m`e[1;97m  $Title$tFill`e[0m"
        $g += "`e[4;1H  `e[96m$rule`e[0m`e[K"

        $row = 5
        for ($i = $off; $i -lt [Math]::Min($off + $contentRows, $total); $i++) {
            $g += "`e[$row;1H$($out[$i])`e[K"; $row++
        }
        while ($row -le ($termH - 1)) { $g += "`e[$row;1H`e[K"; $row++ }

        $pct    = if ($total -le $contentRows) { "all" } else { "$([int](($off + $contentRows) * 100 / $total))%" }
        $status = "  Up/Dn/PgUp/PgDn scroll   Home top   End bottom   Q/Esc close   $pct  "
        $g     += "`e[$termH;1H`e[7m$status$(" " * [Math]::Max(0, $termW - $status.Length))`e[0m"
        [Console]::Write($g)

        try { $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") } catch { break }

        switch ($key.VirtualKeyCode) {
            38 { $off-- }
            40 { $off++ }
            33 { $off -= $contentRows }
            34 { $off += $contentRows }
            36 { $off = 0 }
            35 { $off = $total - $contentRows }
        }
        if ($key.Character -eq 'q' -or $key.Character -eq 'Q') { break }
        if ($key.VirtualKeyCode -eq 27) { break }

        $nW = $Host.UI.RawUI.WindowSize.Width; $nH = $Host.UI.RawUI.WindowSize.Height
        if ($nW -ne $termW -or $nH -ne $termH) {
            $termW = $nW; $termH = $nH
            $contentRows = [Math]::Max(1, $termH - 6)
        }
    }
    [Console]::Write("`e[?25h")
}
