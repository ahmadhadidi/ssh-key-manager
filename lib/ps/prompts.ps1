# lib/ps/prompts.ps1 — Input prompts, resolvers, validators

function Read-RemoteUser {
    param ([string]$DefaultUser = "")
    if (-not $DefaultUser) { $DefaultUser = $DefaultUserName }
    return Read-HostWithDefault -Prompt "Remote username:" -Default $DefaultUser
}


function Read-RemoteHostName {
    param ([string]$SubnetPrefix = "")
    if (-not $SubnetPrefix) { $SubnetPrefix = $DefaultSubnetPrefix }
    $hosts = Get-ConfiguredSSHHosts
    if ($hosts.Count -gt 0) {
        $labels = @($hosts | ForEach-Object { $_.Alias })
        try {
            $selected = Select-FromList -Items $labels -Prompt "Select host alias  (Esc = enter manually)"
            if ($selected) { return $selected }
        } catch [System.OperationCanceledException] { }
    }
    $name = Read-ColoredInput -Prompt "  Enter the host alias / hostname" -ForegroundColor "Cyan"
    if ([string]::IsNullOrWhiteSpace($name)) {
        Write-Host "  Hostname is required." -ForegroundColor Red
        return $null
    }
    return $name
}


function Read-RemoteHostAddress {
    param ([string]$SubnetPrefix = "")
    if (-not $SubnetPrefix) { $SubnetPrefix = $DefaultSubnetPrefix }
    $script:_LastSelectedAlias = $null

    $hosts = Get-ConfiguredSSHHosts
    if ($hosts.Count -gt 0) {
        $labels = @($hosts | ForEach-Object {
            if ($_.HostName) { "$($_.Alias)  ($($_.HostName))" } else { $_.Alias }
        })
        try {
            $selected = Select-FromList -Items $labels -Prompt "Select remote host  (Esc = enter manually)"
            if ($selected) {
                $alias = ($selected -split '\s+\(')[0].Trim()
                $h     = $hosts | Where-Object { $_.Alias -eq $alias } | Select-Object -First 1
                $addr  = if ($h -and $h.HostName) { $h.HostName } else { $alias }
                $script:_LastSelectedAlias = $alias
                return $addr
            }
        } catch [System.OperationCanceledException] { }
    }

    $RemoteHost = Read-ColoredInput -Prompt "  Enter remote IP / hostname (or last 1-3 digits for $SubnetPrefix.xx)" -ForegroundColor "Cyan"
    if ([string]::IsNullOrWhiteSpace($RemoteHost)) {
        Write-Host "  No input provided." -ForegroundColor Red
        return $null
    }
    if ($RemoteHost -match '^\d{1,3}$') {
        $resolved = "$SubnetPrefix.$RemoteHost"
        Write-Host "  Interpreted as: $resolved" -ForegroundColor Green
        return $resolved
    }
    if ($RemoteHost -match '^\d{1,3}(\.\d{1,3}){3}$') {
        Write-Host "  Full IP address: $RemoteHost" -ForegroundColor Cyan
        return $RemoteHost
    }
    Write-Host "  Hostname: $RemoteHost" -ForegroundColor Cyan
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


function Resolve-NullToDefault {
    param (
        [string]$DefaultValue,
        [string]$Value
    )
    if (Test-ValueIsNull -Value $Value) { return $DefaultValue } else { return $Value }
}


function Resolve-NullToAction {
    param (
        [ScriptBlock]$Action,
        [string]$RequiredValue,
        [string]$RequiredValueLabel
    )
    if ([string]::IsNullOrWhiteSpace($RequiredValue)) {
        Write-Host "  $RequiredValueLabel is a required value." -ForegroundColor Red
        & $Action
        return
    }
    return $RequiredValue
}


function Confirm-UserChoice {
    param (
        [string]$Message,
        [ScriptBlock]$Action,
        [string]$DefaultAnswer
    )
    $NormalizedDefault = $DefaultAnswer.ToLower()
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
        '^(yes|y)$' { & $Action; return $true }
        '^(no|n)$'  { Write-Host "  Action cancelled." -ForegroundColor Yellow; return $false }
        default {
            Write-Host "  Invalid input. Please enter 'y' or 'n'." -ForegroundColor Red
            return (Confirm-UserChoice -Message $Message -Action $Action -DefaultAnswer $DefaultAnswer)
        }
    }
}


function Test-ValueIsNull {
    param ([string]$Value)
    return [string]::IsNullOrWhiteSpace($Value)
}


function Get-PublicKeyInHost {
    param ([string]$KeyName)
    $PublicKeyPath = "$env:USERPROFILE\.ssh\$KeyName.pub"
    if (-not (Test-Path $PublicKeyPath)) {
        Write-Host "  Public key '$KeyName.pub' not found at $PublicKeyPath." -ForegroundColor Red
        return $null
    }
    $PublicKey = Get-Content $PublicKeyPath -Raw
    Write-Host "  Public key loaded successfully:`n  $($PublicKey.Trim())" -ForegroundColor Green
    return $PublicKey
}


function Show-Comment {
    param (
        [string]$Prompt,
        [ConsoleColor]$Color = "Cyan"
    )
    Write-Host -NoNewline "$Prompt " -ForegroundColor $Color
}
