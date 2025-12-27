param(
  [string]$DefaultUserName = "default_non_root_username",
  [string]$DefaultSubnetPrefix = "192.168.0",
  [string]$DefaultCommentSuffix = "-[my-machine]"
)

function Show-MainMenu {
    do {
        $RunAgain = $true
        $choice = Read-Host @"
`n
=====================================================
                 🌊 HDD SSH Keys
=====================================================

`e[1m  Remote`e[0m
  ------
  1. Generate & Install SSH Key on A Remote Machine
  2. Test SSH Connection
  3. Delete SSH Key From A Remote Machine
  4. Promote Key on A Remote Machine

`e[1m  Local`e[0m
  ------
  5. Generate SSH Key (Without installation)
  6. Append SSH Key to Hostname in Host Config
  7. Delete an SSH Key Locally
  8. Remove an SSH Key From Config

`e[1m  🌊`e[0m
  ------
  9. Help: Best Practices
  10. Conf: Global Defaults
  Q. Exit

Enter your choice (1–10)
"@

        switch ($choice) {
            "1" { # Install SSH Key on A Remote Machine

                Write-Host "`n"
                $KeyName = Read-SSHKeyName

                Deploy-SSHKeyToRemote -KeyName $KeyName
            }
            "2" { # Test SSH connection

                $RemoteUser = Read-RemoteUser -DefaultUser "$DefaultUserName"
                $RemoteHost = Read-RemoteHostAddress -SubnetPrefix "$DefaultSubnetPrefix"

                Test-SSHConnection -RemoteUser $RemoteUser -RemoteHost $RemoteHost
            }
            "3" { # Delete SSH Key From A Remote Machine

                $KeyName = Read-SSHKeyName
                $RemoteHost = Read-RemoteHostAddress -SubnetPrefix "$DefaultSubnetPrefix"
                $RemoteUser = Read-RemoteUser -DefaultUser "$DefaultUserName"

                Remove-SSHKeyFromRemote -RemoteUser $RemoteUser -RemoteHost $RemoteHost -KeyName $KeyName

            }
            "4" { # Promote Key
                Deploy-PromotedKey
            }
            "5" { # Generate SSH key (Without installation)

                $KeyName = Read-SSHKeyName
                $Comment = Read-SSHKeyComment -DefaultComment "$KeyName$DefaultCommentSuffix"

                Add-SSHKeyInHost -KeyName $KeyName -Comment $Comment

            }
            "6" { # Add SSH Key to Host Config

                $KeyName = Read-SSHKeyName
                
                # 🚧 TODO:
                # After taking the key we need to do the following:
                # ask about the Host of the target machine (sonarr / radarr)
                # If it exists, we just append the Identity file
                # If it does not exist, we need to ask about the IP Address of the CT and the user and then we can add the identity file.
                # Below is not correct

                $RemoteHostName = Read-RemoteHostName -SubnetPrefix "$DefaultSubnetPrefix"

                Add-SSHKeyToHostConfig -KeyName $KeyName -RemoteHostName $RemoteHostName -RemoteHostAddress $RemoteHostAddress -RemoteUser $RemoteUser

            }
            "7" { # Delete an SSH Key Locally

                Write-Host "❌  Not yet implemented!"
                $KeyName = Read-SSHKeyName
                $RemoteHostAddress = Read-RemoteHostAddress -SubnetPrefix "$DefaultSubnetPrefix"
                $RemoteUser = Read-RemoteUser -DefaultUser "$DefaultUserName"
                $RemoteHostName = Read-RemoteHostName -SubnetPrefix "$DefaultSubnetPrefix"

            }
            "8" { # Remove an SSH Key From Config

                $KeyName = Read-SSHKeyName
                $RemoteHostName = Read-RemoteHostName -SubnetPrefix "$DefaultSubnetPrefix"
                Remove-IdentityFileFromConfigEntry -KeyName $KeyName -RemoteHostName $RemoteHostName

            }
            "9" { # Help: Best practice

                Write-Host "The general practice behind this utility is to do the following:" -ForegroundColor Cyan
                Write-Host "1. CTs accessed through LAN that are being demo'ed shall have a common key -- e.g. demo-lan" -ForegroundColor Cyan
                Write-Host "2. CTs accessed through LAN that are for development shall have a common key -- e.g. dev-lan" -ForegroundColor Cyan
                Write-Host "3. CTs accessed through LAN that have been [promoted] and enacted into my stack shall have a common key -- e.g. prod-lan" -ForegroundColor Cyan
                Write-Host "4. CTs accessed through the Interwebs (regardless of status) shall have their own individual key -- e.g. sonarr-wan" -ForegroundColor Red

            }
            "10" { # Conf: Global Defaults
                Write-Host "`n`e[1mGlobal Defaults:`e[0m`n" -ForegroundColor Cyan
                Write-Host "1. `e[1m`$DefaultUserName`e[0m=$DefaultUserName⏹" -ForegroundColor Cyan
                Write-Host "2. `e[1m`$DefaultSubnetPrefix`e[0m=$DefaultSubnetPrefix⏹" -ForegroundColor Cyan
                Write-Host "3. `e[1m`$DefaultCommentSuffix`e[0m=$DefaultCommentSuffix⏹" -ForegroundColor Cyan
                Write-Host "`nℹ️  Variables can be changed by editing the variables when invoking the script" -ForegroundColor Yellow
            }
            "q" { # Exit

                Write-Host "🌊 Exiting..." -ForegroundColor Cyan
                $RunAgain = $false
                break

            }
            Default {

                Write-Host "Invalid option. Please choose a number between 1 and 9." -ForegroundColor Red

            }
        }

    } while ($RunAgain)
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

    Write-Host "🔃 Connecting to $RemoteUser@$RemoteHostAddress..."

    try {
        #$PublicKey | ssh "$RemoteUser@$RemoteHostAddress" "mkdir -p .ssh && cat >> .ssh/authorized_keys"
        $RemoteHostName = $PublicKey | ssh "$RemoteUser@$RemoteHostAddress" 'mkdir -p .ssh && cat >> .ssh/authorized_keys && hostname'
        # type "$PublicKeyPath" | ssh "$RemoteUser@$RemoteHost" "mkdir -p .ssh && cat >> .ssh/authorized_keys"
        Write-Host "✅ SSH Public Key installed successfully." -ForegroundColor Green

        # Register the key in the SSH config file
        Write-Host "Registering Public key to config file..."
        Write-Host "🏷  Hostname of the target machine is: $RemoteHostName"
        # Add-SSHKeyToHostConfig -KeyName $KeyName -RemoteHost $RemoteHost -RemoteUser $RemoteUser
        Add-SSHKeyToHostConfig -KeyName $KeyName -RemoteHostAddress $RemoteHostAddress -RemoteHostName $RemoteHostName -RemoteUser $RemoteUser
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

    $testCommand = {
        ssh "$RemoteUser@$RemoteHost" "echo SSH Connection Successful" 2>&1
    }

    try {
        $result = & $testCommand

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
    Write-Host "`n🔒 Will connect to remove the public key from $RemoteUser@$RemoteHost`:`n$PublicKey`n" -ForegroundColor Yellow

    try {
        ssh "$RemoteUser@$RemoteHost" $RemoteCommand
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


Show-MainMenu
