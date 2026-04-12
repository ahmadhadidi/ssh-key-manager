# lib/ps/menu-renderer.ps1 — TUI event loop and operation runner
# Dot-sourced by hddssh.ps1 — do not execute directly.
# Depends on menu.ps1 (Invoke-MenuChoice).
# EXPORTS: Show-MainMenu  _InvokeMenuAction

function Show-MainMenu {
    $menuDef = @(
        [pscustomobject]@{ Type = "header"; Label = "Remote" }
        [pscustomobject]@{ Type = "item";   Label = "🔑  Generate & Install SSH Key on A Remote Machine"; Choice = "1";  Hotkey = "G" }
        [pscustomobject]@{ Type = "item";   Label = "📤  Install SSH Key on A Remote Machine";            Choice = "15"; Hotkey = "I" }
        [pscustomobject]@{ Type = "item";   Label = "🔌  Test SSH Connection";                            Choice = "2";  Hotkey = "T" }
        [pscustomobject]@{ Type = "item";   Label = "🗑️  Delete SSH Key From A Remote Machine";           Choice = "3";  Hotkey = "D" }
        [pscustomobject]@{ Type = "item";   Label = "🔄  Promote Key on A Remote Machine";                Choice = "4";  Hotkey = "P" }
        [pscustomobject]@{ Type = "item";   Label = "📋  List Authorized Keys on Remote Host";            Choice = "16"; Hotkey = "Z" }
        [pscustomobject]@{ Type = "item";   Label = "🔗  Add Config Block for Existing Remote Key";       Choice = "17"; Hotkey = "N" }
        [pscustomobject]@{ Type = "header"; Label = "Local" }
        [pscustomobject]@{ Type = "item";   Label = "✨  Generate SSH Key (Without Installation)";        Choice = "5";  Hotkey = "W" }
        [pscustomobject]@{ Type = "item";   Label = "🗝️  List SSH Keys";                                  Choice = "6";  Hotkey = "L" }
        [pscustomobject]@{ Type = "item";   Label = "➕  Append SSH Key to Hostname in Host Config";      Choice = "7";  Hotkey = "A" }
        [pscustomobject]@{ Type = "item";   Label = "🗑️  Delete an SSH Key Locally";                      Choice = "8";  Hotkey = "X" }
        [pscustomobject]@{ Type = "item";   Label = "❌  Remove an SSH Key From Config";                  Choice = "9";  Hotkey = "R" }
        [pscustomobject]@{ Type = "item";   Label = "📥  Import SSH Key from Another Machine";            Choice = "18"; Hotkey = "M" }
        [pscustomobject]@{ Type = "header"; Label = "Config File" }
        [pscustomobject]@{ Type = "item";   Label = "🏚️  Remove Host from SSH Config";                    Choice = "12"; Hotkey = "H" }
        [pscustomobject]@{ Type = "item";   Label = "👁️  View SSH Config";                                Choice = "13"; Hotkey = "V" }
        [pscustomobject]@{ Type = "item";   Label = "✏️  Edit SSH Config";                                Choice = "14"; Hotkey = "E" }
        [pscustomobject]@{ Type = "item";   Label = "🚪  Exit";                                           Choice = "q";  Hotkey = "Q" }
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

                $menuRule     = ([char]0x2500).ToString() * [Math]::Max(0, $termWidth - 4)
                $menuTitle    = "🌊 HDD SSH Keys Manager"
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
                                $f += "`e[$row;1H`e[7m    $($fr.Label)`e[K`e[0m"
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
                    [Console]::Write("`e[${r};1H`e[7m    $($navItems[$sel].Label)`e[K`e[0m")
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
    $rule    = ([char]0x2500).ToString() * [Math]::Max(0, $TermWidth - 4)
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
