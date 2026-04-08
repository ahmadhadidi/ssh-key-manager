# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A terminal-based SSH key manager with an interactive TUI (Text User Interface). It automates ED25519 key generation, deployment to remote machines, SSH config management, connection testing, and key rotation/cleanup.

Two parallel implementations exist:
- `ssh-key-manager.sh` — Linux/macOS (Bash 4+), ~2,035 lines
- `generate_key_test.ps1` — Windows (PowerShell 5+), ~2,291 lines

## Running

**Bash:**
```bash
bash ssh-key-manager.sh
bash ssh-key-manager.sh --user myuser --subnet 192.168.0 --comment-suffix "-[prod]" --password "mypass"
```

**PowerShell:**
```powershell
. .\generate_key_test.ps1
& ./generate_key_test.ps1 -DefaultUserName "root" -DefaultSubnetPrefix "192.168.0"
```

There is no build step, test framework, or linter. Both scripts run directly with no dependencies beyond Bash/PowerShell and OpenSSH (`ssh`, `ssh-keygen`). `sshpass` is optional for password-based remote auth.

## Architecture

Both scripts are single-file, procedural implementations with identical logical structure. Sections are delimited by `# ─── Section Name ───` comments. The control flow is:

1. Parse CLI args → set defaults
2. `show_main_menu()` enters the event loop (raw terminal, non-blocking key reads with ~50ms timeout for resize detection)
3. User selects one of 17 menu options → `invoke_menu_choice()` dispatches to the appropriate function
4. Operation completes → `wait_user_acknowledge()` → return to menu

**Structural sections (approximate line ranges in the Bash script):**
- **~1–150**: Globals, CLI parsing, terminal primitives (raw stty, ANSI escape sequences, non-blocking `_read_key`)
- **~150–350**: TUI components: `select_from_list()` (combo-box with filtering), `show_paged()` (paginator), `format_menu_label()` (hotkey rendering)
- **~350–500**: SSH config parsing: `get_configured_ssh_hosts()`, `get_available_ssh_keys()`, `_get_host_block()`, `_block_field()`
- **~500–750**: Input/prompt functions: `read_remote_host_address()` (subnet shorthand, e.g. "10" → "192.168.0.10"), `read_ssh_key_name()`, `confirm_user_choice()`
- **~750–1200**: SSH key operations: `add_ssh_key_in_host()`, `install_ssh_key_on_remote()`, `deploy_ssh_key_to_remote()`, `test_ssh_connection()`, `remove_ssh_key_from_remote()`
- **~1200–1400**: Config display/edit: `show_ssh_config_file()`, `show_ssh_key_inventory()`, `remove_host_from_ssh_config()`
- **~1400–1800**: Menu dispatcher `invoke_menu_choice()` with all 17 choices
- **~1800+**: `show_main_menu()` with scrolling viewport, differential rendering, hotkey support, resize detection

**TUI Key Details:**
- `_read_key` / `_read_key_nb`: Raw terminal key capture, handles multi-byte escape sequences (arrow keys)
- `select_from_list()`: The core combo-box widget — used for picking hosts, keys, users throughout
- ANSI escape sequences are used directly (cursor positioning, colors, bold, hide/show cursor)
- Terminal resize is detected by comparing `tput cols/lines` output between key-read cycles

**SSH Config Interaction:**
- Reads/writes `~/.ssh/config` directly using `perl` (multiline regex for Host blocks), `awk`, `sed`, `grep`
- `get_identity_files_for_host()` / `get_hosts_using_key()` are used to cross-reference keys and hosts

**Bash vs PowerShell parity:**
When modifying behavior, changes typically need to be mirrored in both files. Bash uses `stty`/`read` for terminal I/O; PowerShell uses `Host.UI.RawUI.ReadKey()` and `[Console]::Write()`. Config parsing in Bash uses `perl`/`awk`/`sed`; PowerShell uses `[regex]` class methods.
