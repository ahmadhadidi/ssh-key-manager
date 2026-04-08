# lib/ps/tui.ps1 — TUI helpers: Wait-UserAcknowledge, Show-Paged, Select-FromList, Format-MenuLabel

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


function Select-FromList {
    # Combo-box: Up/Dn navigates list, typing filters/creates new entry, Enter selects, Esc cancels.
    # -StrictList: Enter only accepts a highlighted list item (or sole match); disallows free text.
    param(
        [string[]]$Items,
        [string]$Prompt = "Select",
        [switch]$StrictList
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
        $inputDisp = if ($filter) { "`e[37m$filter`e[90m|`e[0m" } else { "`e[90m(type to filter or create new)`e[0m" }
        $f  = "`e[$promptRow;1H`e[K  `e[90m$Prompt`e[0m"
        $f += "`e[$inputRow;1H`e[K  `e[36m>`e[0m $inputDisp"
        for ($i = 0; $i -lt $maxVis; $i++) {
            $idx = $viewOff + $i
            $r   = $startRow + $i
            $f  += "`e[$r;1H`e[K"
            if ($idx -lt $filtered.Count) {
                if ($idx -eq $sel) { $f += "`e[7m  > $($filtered[$idx])`e[K`e[0m" }
                else               { $f += "  `e[37m  $($filtered[$idx])`e[0m" }
            }
        }
        $up   = if ($viewOff -gt 0)                           { "^ " } else { "  " }
        $dn   = if ($viewOff + $maxVis -lt $filtered.Count)   { "v " } else { "  " }
        $hint = "  Up/Dn  navigate     Enter  select     type  filter / new name     Esc  cancel    $up$dn"
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
                $chosen = if ($sel -ge 0 -and $sel -lt $filtered.Count) {
                              $filtered[$sel]
                          } elseif ($StrictList) {
                              if ($filtered.Count -eq 1) { $filtered[0] } else { $null }
                          } elseif ($filter) {
                              $filter
                          } else { $null }
                if ($chosen -eq $null -and $StrictList) { break }
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


function Format-MenuLabel {
    param([string]$Label, [string]$Hotkey)
    if (-not $Hotkey) { return $Label }
    [regex]::Replace($Label, "(?i)($([regex]::Escape($Hotkey)))", "`e[1;4m`$1`e[0;37m", 1)
}
