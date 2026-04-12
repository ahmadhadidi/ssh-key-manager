param(
  [string]$DefaultUserName      = "default_non_root_username",
  [string]$DefaultSubnetPrefix  = "192.168.0",
  [string]$DefaultCommentSuffix = "-[my-machine]",
  [string]$DefaultPassword      = ""
)
# SSH Key Manager — PowerShell entry point
#
# Usage (local):
#   .\hddssh.ps1 [-DefaultUserName user] [-DefaultSubnetPrefix 192.168.0] ...
#
# Usage (remote — no params, uses defaults):
#   irm "https://raw.githubusercontent.com/ahmadhadidi/ssh-key-manager/refs/heads/main/hddssh.ps1" | iex
#
# Usage (remote — with params):
#   $u = "https://raw.githubusercontent.com/ahmadhadidi/ssh-key-manager/refs/heads/main/hddssh.ps1"
#   & ([scriptblock]::Create((irm $u))) -DefaultUserName "myuser" -DefaultSubnetPrefix "10.0.0"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$P = "  "
$script:_LastSelectedAlias = $null
$script:_RemoteHost        = $null
$script:_RemoteUser        = $null
$script:_RemoteAlias       = $null
$script:_OpBannerBuf       = ""
$script:_OpBannerRows      = 0

# ── Library loader ────────────────────────────────────────────────────────────
$_BASE_URL  = "https://raw.githubusercontent.com/ahmadhadidi/ssh-key-manager/refs/heads/main"
$_SCRIPT_DIR = ""
if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "lib\ps"))) {
    $_SCRIPT_DIR = $PSScriptRoot
}

$__libs = @("tui", "ssh-helpers", "ssh-config", "prompts", "ssh-ops", "config-display", "menu", "menu-renderer")
foreach ($__lib in $__libs) {
    $__local = if ($_SCRIPT_DIR) { Join-Path $_SCRIPT_DIR "lib\ps\$__lib.ps1" } else { "" }
    if ($__local -and (Test-Path $__local)) {
        . $__local
    } else {
        Invoke-Expression (Invoke-RestMethod "$_BASE_URL/lib/ps/$__lib.ps1")
    }
}
Remove-Variable __lib, __libs, __local, _SCRIPT_DIR, _BASE_URL -ErrorAction SilentlyContinue

# ── Entry point ───────────────────────────────────────────────────────────────
Show-MainMenu
