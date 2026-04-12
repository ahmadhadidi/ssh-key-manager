# lib/ps/ssh-helpers.ps1 — SSH utility helpers shared across ssh-ops and menu
# EXPORTS: Write-Out  Write-OutItem  Show-OpBanner
#          Write-SSHFence  Write-SSHFenceClose
#          Invoke-RemotePrompt  Write-IdentityFiles  Ensure-SSHDir  Write-KeyPair

# ─── Output helpers ───────────────────────────────────────────────────────────

function Write-Out {
    # Write-Out STYLE FORMAT [ARGS...]
    # Prints a 2-space indented, color-coded line.
    # Styles: ok (green)  warn (yellow)  error (red)  info (cyan)
    #         dim (gray)  heading (bright-cyan)  plain (bright-white)
    param(
        [string]$Style,
        [string]$Format,
        [object[]]$Args = @()
    )
    $code = switch ($Style) {
        'ok'      { 32 }
        'warn'    { 33 }
        'error'   { 31 }
        'info'    { 36 }
        'dim'     { 90 }
        'heading' { 96 }
        'plain'   { 97 }
        default   { 37 }
    }
    $text = if ($Args.Count -gt 0) { $Format -f $Args } else { $Format }
    [Console]::WriteLine("  `e[${code}m${text}`e[0m")
}


function Write-OutItem {
    # Write-OutItem FORMAT [ARGS...]
    # Prints "  + text" with a green plus sign.
    param(
        [string]$Format,
        [object[]]$Args = @()
    )
    $text = if ($Args.Count -gt 0) { $Format -f $Args } else { $Format }
    [Console]::WriteLine("  `e[32m+`e[0m  ${text}")
}


function Show-OpBanner {
    # Show-OpBanner -Pairs @("key","val",...) [-StartRow N]
    # Renders a styled context block with orange box-drawing borders.
    #
    # Stream mode (default, StartRow -lt 0): prints to stdout.
    # Buffer mode (StartRow >= 0): writes positioned ANSI into $script:_OpBannerBuf.
    #
    # Always sets $script:_OpBannerRows and $script:_OpBannerBuf.
    param(
        [string[]]$Pairs,
        [int]$StartRow = -1
    )

    $pairCount  = [Math]::Floor($Pairs.Count / 2)
    $script:_OpBannerRows = $pairCount + 4   # top-border + pad + content(s) + pad + bot-border
    $script:_OpBannerBuf  = ""

    $tw   = $Host.UI.RawUI.WindowSize.Width
    $mx   = 2                                # x-margin (spaces each side)
    $ow   = [Math]::Max(10, $tw - $mx * 2)  # outer box width (corners included)
    $iw   = $ow - 2                          # inner width (between │ chars)

    # Find longest key for alignment
    $maxKLen = 0
    for ($i = 0; $i -lt $Pairs.Count - 1; $i += 2) {
        if ($Pairs[$i].Length -gt $maxKLen) { $maxKLen = $Pairs[$i].Length }
    }

    # Box chars
    $TL  = [char]0x250C  # ┌
    $TR  = [char]0x2510  # ┐
    $BL  = [char]0x2514  # └
    $BR  = [char]0x2518  # ┘
    $VB  = [char]0x2502  # │
    $BUL = [char]0x2022  # •

    # Styles
    $OC  = "`e[38;2;217;119;87m"   # orange fg
    $FB  = "`e[48;2;48;26;19m"     # faint dark bg
    $FW  = "`e[97m"                 # bright white fg
    $BLD = "`e[1m"                  # bold on
    $NBD = "`e[22m"                 # bold off
    $RS  = "`e[0m"
    $MX  = " " * $mx

    # Horizontal rule: ow-2 connected ─ chars
    $hrule = ([char]0x2500).ToString() * ($ow - 2)

    # Inner blank padding row
    $ipad = " " * $iw

    # Pre-build content rows
    $crowList = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $Pairs.Count - 1; $i += 2) {
        $keyRaw = $Pairs[$i]
        $val    = $Pairs[$i + 1]
        $keyUp  = ($keyRaw.ToUpper() + ":").PadRight($maxKLen + 2)
        # display width: "  • " (4) + key (maxKLen+2) + "  " (2) + val
        $cdw    = 4 + ($maxKLen + 2) + 2 + $val.Length
        $padN   = [Math]::Max(0, $iw - $cdw)
        $pad    = " " * $padN
        $crowList.Add("  ${BUL} ${BLD}${keyUp}${NBD}  ${val}${pad}")
    }

    $top  = "${MX}${OC}${TL}${hrule}${TR}${RS}"
    $bot  = "${MX}${OC}${BL}${hrule}${BR}${RS}"
    $prow = "${MX}${OC}${VB}${RS}${FB}${ipad}${RS}${OC}${VB}${RS}"

    if ($StartRow -ge 0) {
        $r = $StartRow
        $script:_OpBannerBuf += "`e[${r};1H${top}`e[K"; $r++
        $script:_OpBannerBuf += "`e[${r};1H${prow}`e[K"; $r++
        foreach ($crow in $crowList) {
            $line = "${MX}${OC}${VB}${RS}${FB}${FW}${crow}${RS}${OC}${VB}${RS}"
            $script:_OpBannerBuf += "`e[${r};1H${line}`e[K"; $r++
        }
        $script:_OpBannerBuf += "`e[${r};1H${prow}`e[K"; $r++
        $script:_OpBannerBuf += "`e[${r};1H${bot}`e[K"
    } else {
        [Console]::WriteLine($top)
        [Console]::WriteLine($prow)
        foreach ($crow in $crowList) {
            [Console]::WriteLine("${MX}${OC}${VB}${RS}${FB}${FW}${crow}${RS}${OC}${VB}${RS}")
        }
        [Console]::WriteLine($prow)
        [Console]::WriteLine($bot)
    }
}


# ─── Connection helpers ───────────────────────────────────────────────────────

function Write-SSHFence {
    # Opening fence rule: "── SSH Session user@host ──"
    param([string]$Target = "")
    $w      = $Host.UI.RawUI.WindowSize.Width
    $innerW = [Math]::Max(10, $w - 4)
    $dash   = [char]0x2500  # ─
    if ($Target) {
        $label  = " SSH Session $Target "
        $dTotal = [Math]::Max(4, $innerW - $label.Length)
        $lw     = [Math]::Floor($dTotal / 2)
        $rw     = $dTotal - $lw
        $left   = $dash.ToString() * $lw
        $right  = $dash.ToString() * $rw
        [Console]::WriteLine("  `e[2m${left}`e[0m`e[90m${label}`e[0m`e[2m${right}`e[0m")
    } else {
        [Console]::WriteLine("  `e[2m$($dash.ToString() * $innerW)`e[0m")
    }
}


function Write-SSHFenceClose {
    # Closing fence rule: "── SSH session closed ──"
    $w      = $Host.UI.RawUI.WindowSize.Width
    $innerW = [Math]::Max(10, $w - 4)
    $dash   = [char]0x2500
    $label  = " SSH session closed "
    $dTotal = [Math]::Max(4, $innerW - $label.Length)
    $lw     = [Math]::Floor($dTotal / 2)
    $rw     = $dTotal - $lw
    $left   = $dash.ToString() * $lw
    $right  = $dash.ToString() * $rw
    [Console]::WriteLine("  `e[2m${left}`e[0m`e[90m${label}`e[0m`e[2m${right}`e[0m")
}


# ─── Remote prompt helper ─────────────────────────────────────────────────────

function Invoke-RemotePrompt {
    # Prompts for a remote host and user in one call.
    # Sets $script:_RemoteHost, $script:_RemoteUser, $script:_RemoteAlias.
    # Lets OperationCanceledException propagate (callers handle it in _InvokeMenuAction).
    $script:_RemoteHost  = Read-RemoteHostAddress -SubnetPrefix $DefaultSubnetPrefix
    $script:_RemoteAlias = if ($script:_LastSelectedAlias) { $script:_LastSelectedAlias } else {
        Get-AliasForHostIP $script:_RemoteHost
    }
    $script:_RemoteUser  = Read-RemoteUser -DefaultUser $DefaultUserName
}


# ─── Output helpers ───────────────────────────────────────────────────────────

function Write-IdentityFiles {
    # Print the IdentityFile entries configured for a host (informational only).
    param([string]$IdLookup)
    foreach ($k in (Get-IdentityFilesForHost $IdLookup)) {
        Write-Out 'dim' "Using key: $k"
    }
}


# ─── Local filesystem helpers ─────────────────────────────────────────────────

function Ensure-SSHDir {
    $sshDir = "$env:USERPROFILE\.ssh"
    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    }
}


function Write-KeyPair {
    # Write a key pair to ~/.ssh with overwrite confirmation.
    # CopyMode=$true  → Copy-Item from file paths PrivData/PubData.
    # CopyMode=$false → WriteAllText with literal string content.
    # Returns $true on success, $false if aborted.
    param(
        [string]$DestPriv,
        [string]$DestPub,
        [string]$PrivData,
        [string]$PubData,
        [bool]$CopyMode = $false
    )
    if (Test-Path $DestPriv) {
        $resp = Read-ColoredInput -Prompt "  '$(Split-Path $DestPriv -Leaf)' already exists. Overwrite? [y/N]" -ForegroundColor Yellow
        if ($resp -notmatch '^[Yy]') {
            Write-Out 'warn' 'Aborted.'
            return $false
        }
    }
    if ($CopyMode) {
        Copy-Item $PrivData $DestPriv -Force
        Copy-Item $PubData  $DestPub  -Force
    } else {
        [System.IO.File]::WriteAllText($DestPriv, $PrivData, [System.Text.Encoding]::UTF8)
        # Ensure public key ends with exactly one newline
        $pubContent = $PubData.TrimEnd("`n", "`r") + "`n"
        [System.IO.File]::WriteAllText($DestPub, $pubContent, [System.Text.Encoding]::UTF8)
    }
    Write-OutItem "$DestPriv  imported."
    Write-OutItem "$DestPub  imported."
    return $true
}
