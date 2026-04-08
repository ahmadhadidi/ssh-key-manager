# lib/ps/config-display.ps1 — Show/edit/remove config, key inventory, key generation

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

    Write-Host "  `e[90mGenerating SSH key...`e[0m"

    $sshKeygenCmd = "ssh-keygen -t ed25519 -f `"$env:USERPROFILE\.ssh\$KeyName`" -C `"$Comment`""
    $sshKeygenCmd += if ($Password) { " -N `"$Password`"" } else { " -N ''" }
    Invoke-Expression $sshKeygenCmd

    Write-Host "  `e[32m+`e[0m  `e[36m$env:USERPROFILE\.ssh\$KeyName`e[0m  generated." -ForegroundColor Green
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
                Write-Host "  IdentityFile added to existing Host $RemoteHostName." -ForegroundColor Green
            } else {
                Write-Host "  IdentityFile already exists under Host $RemoteHostName." -ForegroundColor Yellow
            }
        } else {
            $hostEntry = "Host $RemoteHostName`n    HostName $RemoteHostAddress`n    User $RemoteUser`n    IdentityFile $keyPath"
            $existing  = (Get-Content $sshConfig -Raw -Encoding UTF8).TrimEnd()
            Set-Content $sshConfig -Value ($existing + "`n`n" + $hostEntry + "`n") -Encoding UTF8 -NoNewline
            Write-Host "  SSH config block created for $RemoteHostName." -ForegroundColor Green
            Write-Host "  Connect with: ssh $RemoteHostName" -ForegroundColor Cyan
        }
    } else {
        Write-Host "  Could not find private SSH Key at $keyPath" -ForegroundColor Red
    }
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
        Write-Host "  Host alias is required." -ForegroundColor Red
        return
    }

    $configPath = "$env:USERPROFILE\.ssh\config"
    if (-not (Test-Path $configPath)) {
        Write-Host "  SSH config not found at $configPath" -ForegroundColor Red
        return
    }

    $config  = Get-Content $configPath -Raw -Encoding UTF8
    $pattern = "(?ms)^Host\s+$([regex]::Escape($hostName))\b.*?(?=^Host\s|\z)"
    $match   = [regex]::Match($config, $pattern)

    if (-not $match.Success) {
        Write-Host "  No Host block found for '$hostName'" -ForegroundColor Yellow
        return
    }

    Write-Host "`n  Block that will be removed:" -ForegroundColor DarkGray
    Write-Host $match.Value -ForegroundColor Gray

    $confirm = Read-ColoredInput -Prompt "Remove this block? [y/N]" -ForegroundColor "Yellow"
    if ($confirm -notmatch '^(y|yes)$') {
        Write-Host "  Cancelled." -ForegroundColor Yellow
        return
    }

    $newConfig = ($config -replace [regex]::Escape($match.Value), "").TrimEnd() + "`n"
    [System.IO.File]::WriteAllText($configPath, $newConfig, [System.Text.Encoding]::UTF8)
    Write-Host "  Host '$hostName' removed from SSH config." -ForegroundColor Green
}


function Show-SSHConfigFile {
    $configPath = "$env:USERPROFILE\.ssh\config"
    if (-not (Test-Path $configPath)) {
        Write-Host "  SSH config not found at $configPath" -ForegroundColor Red
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

    # Interactive pager
    $termH       = $Host.UI.RawUI.WindowSize.Height
    $termW       = $Host.UI.RawUI.WindowSize.Width
    $contentRows = [Math]::Max(1, $termH - 5)
    $total       = $out.Count
    $off         = 0
    [Console]::Write("`e[?25l")

    while ($true) {
        $off   = [Math]::Max(0, [Math]::Min($off, [Math]::Max(0, $total - $contentRows)))
        $rule  = "-" * [Math]::Max(0, $termW - 4)
        $hdr   = "  $configPath"
        $hFill = " " * [Math]::Max(0, $termW - $hdr.Length)
        $f     = "`e[2J`e[H"
        $f    += "`e[2;1H  `e[96m$rule`e[0m`e[K"
        $f    += "`e[3;1H`e[48;5;23m`e[1;97m$hdr$hFill`e[0m"
        $f    += "`e[4;1H  `e[96m$rule`e[0m`e[K"
        $row   = 5
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
            $contentRows = [Math]::Max(1, $termH - 5)
        }
    }
    [Console]::Write("`e[?25h")
}


function Edit-SSHConfigFile {
    $configPath = "$env:USERPROFILE\.ssh\config"
    if (-not (Test-Path $configPath)) {
        Write-Host "  SSH config not found at $configPath" -ForegroundColor Red
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
        Write-Host "  Done." -ForegroundColor Green
    } catch {
        Write-Host "  Could not open editor '$editor': $_" -ForegroundColor Red
    }
}


function Show-SSHKeyInventory {
    param(
        [string]$SshDir     = "$env:USERPROFILE\.ssh",
        [string]$ConfigPath = "$env:USERPROFILE\.ssh\config"
    )

    if (-not (Test-Path $SshDir)) {
        Write-Host "  .ssh directory not found at $SshDir" -ForegroundColor Red
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
    $allKeyNames  = @($pubKeyNames + $privKeyNames) | Sort-Object -Unique

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

    $rows = @()
    $i    = 1
    foreach ($keyName in $allKeyNames) {
        $privatePath = Join-Path $SshDir $keyName
        $publicPath  = "$privatePath.pub"
        $privateOk   = Test-Path $privatePath -PathType Leaf
        $publicOk    = Test-Path $publicPath  -PathType Leaf
        $usage = if ($usageMap.ContainsKey($keyName)) {
            ($usageMap[$keyName] | Sort-Object) -join ", "
        } else { "" }
        $rows += [pscustomobject]@{
            "#"       = $i
            "Key"     = $keyName
            "Public"  = $(if ($publicOk)  { "Y" } else { "N" })
            "Private" = $(if ($privateOk) { "Y" } else { "N" })
            "Usage"   = $usage
        }
        $i++
    }

    if ($rows.Count -eq 0) {
        Write-Host "  No key files found in $SshDir" -ForegroundColor Yellow
        return
    }

    $wNum  = ([string]$rows.Count).Length
    $wKey  = [Math]::Max(3, ($rows | ForEach-Object { $_.Key.Length } | Measure-Object -Maximum).Maximum)
    $wUse  = [Math]::Max(5, ($rows | ForEach-Object { $_.Usage.Length } | Measure-Object -Maximum).Maximum)
    $wPub  = 3
    $wPriv = 4
    $sep   = "+"
    $top = "  $sep$("-" * ($wNum + 2))$sep$("-" * ($wKey + 2))$sep$("-" * ($wPub + 2))$sep$("-" * ($wPriv + 1))$sep$("-" * ($wUse + 2))$sep"
    $hdr = "  | $(" " * [Math]::Max(0, $wNum - 1))# | $("Key".PadRight($wKey)) | Pub | Prv | $("Usage".PadRight($wUse)) |"
    $mid = $top

    $tableLines = @()
    $tableLines += "`e[97m$top`e[0m"
    $tableLines += "`e[1;37m$hdr`e[0m"
    $tableLines += "`e[97m$mid`e[0m"
    foreach ($r in $rows) {
        $num   = [string]$r."#"
        $pubC  = if ($r.Public  -eq "Y") { "`e[32m  Y  `e[0m" } else { "`e[31m  N  `e[0m" }
        $privC = if ($r.Private -eq "Y") { "`e[32m  Y  `e[0m" } else { "`e[31m  N  `e[0m" }
        $tableLines += "  `e[97m|`e[0m $($num.PadLeft($wNum)) `e[97m|`e[0m `e[36m$($r.Key.PadRight($wKey))`e[0m `e[97m|`e[0m$pubC`e[97m|`e[0m$privC`e[97m|`e[0m `e[37m$($r.Usage.PadRight($wUse))`e[0m `e[97m|`e[0m"
    }
    $tableLines += "`e[97m$top`e[0m"

    Show-Paged -Lines $tableLines
}
