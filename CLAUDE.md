# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A terminal-based SSH key manager with an interactive TUI (Text User Interface). It automates ED25519 key generation, deployment to remote machines, SSH config management, connection testing, and key rotation/cleanup.

Two parallel implementations exist:
- `ssh-key-manager.sh` — Linux/macOS (Bash 4+), entry point (~90 lines); logic lives in `lib/bash/`
- `generate_key_test.ps1` — Windows (PowerShell 5+), ~2,291 lines (single file, not yet split)

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

## Architecture (Bash)

`ssh-key-manager.sh` parses CLI args, sets globals, then sources the lib modules in order and calls `show_main_menu()`. The lib modules are loaded locally from `lib/bash/` when the directory exists, or fetched via `curl` from the GitHub raw URL when run remotely.

### Library load order

```
tui → ssh-config → ssh-helpers → prompts → ssh-ops → config-display → menu
```

Each module has a guard variable (`_<MODULE>_SH_LOADED`) to prevent double-sourcing.

### Module breakdown

| File | Lines | Responsibility |
|------|-------|----------------|
| `tui.sh` | ~476 | Terminal primitives, TUI widgets |
| `ssh-config.sh` | ~146 | `~/.ssh/config` parsing |
| `ssh-helpers.sh` | ~151 | Shared SSH utility helpers and output helpers |
| `prompts.sh` | ~341 | Input prompts and host/key finders |
| `ssh-ops.sh` | ~526 | SSH key operations |
| `config-display.sh` | ~431 | Read-only config/inventory display |
| `menu.sh` | ~888 | Main menu, dispatcher, all 17 menu cases |

### Control flow

1. Parse CLI args → set defaults
2. `show_main_menu()` enters the event loop (raw terminal, non-blocking key reads with ~50ms timeout for resize detection)
3. User selects one of 17 menu options → `invoke_menu_choice()` dispatches to the appropriate function
4. Operation completes → `wait_user_acknowledge()` → return to menu

### tui.sh

- `_read_key` / `_read_key_nb`: Raw terminal key capture, handles multi-byte escape sequences (arrow keys). Uses `stty` raw mode; avoid adding subprocess forks inside the render loop.
- `select_from_list()`: Core combo-box widget with incremental filtering — used for picking hosts, keys, and users throughout. Render loop uses `printf -v` (zero-fork) instead of `$(printf ...)`.
- `select_multi_from_list()`: Checkbox list with Space toggle, Enter confirm, ESC cancel.
- `show_paged()`: Paginator for long output.
- `format_menu_label()`: Hotkey character highlighting.
- ANSI escape sequences used directly (cursor positioning, colors, bold, hide/show cursor).
- Terminal resize detected by comparing `tput cols/lines` between key-read cycles.

### ssh-config.sh

Reads `~/.ssh/config` using `perl`, `awk`, `grep`:
- `get_configured_ssh_hosts()` — emits `alias|hostname|user` tuples
- `get_available_ssh_keys()` — lists private keys in `~/.ssh`
- `_get_host_block()` / `_replace_host_block()` — multiline Host block read/write
- `_block_field()` — extract a single field from a Host block
- `get_identity_files_for_host()` / `get_hosts_using_key()` — cross-reference keys and hosts
- `get_alias_for_host_ip()` — reverse-lookup Host alias from a HostName IP

### ssh-helpers.sh

Shared helpers sourced by both `ssh-ops.sh` and `menu.sh`. Must be loaded after `tui` and `ssh-config` (depends on `_repeat` and `get_alias_for_host_ip`).

**Output helpers:**
- `_out STYLE FORMAT [ARGS...]` — 2-space indented, color-coded line to stdout.
  Styles: `ok` (green), `warn` (yellow), `error` (red), `info` (cyan), `dim` (gray), `heading` (bright-cyan), `plain` (bright-white).
- `_out_item FORMAT [ARGS...]` — green `+` prefix, plain text.

**SSH/filesystem helpers:**
- `_tcp_check HOST` — TCP port-22 reachability check
- `_ssh_fence TARGET` / `_ssh_fence_close` — decorative rule printed around SSH sessions
- `_setup_askpass` / `_destroy_askpass` — temporary `SSH_ASKPASS` script for padded prompts
- `_ensure_ssh_dir` — `mkdir -p ~/.ssh && chmod 700`
- `_write_key_pair DEST_PRIV DEST_PUB DATA DATA [copy_mode]` — write or copy a key pair with permission enforcement
- `_print_identity_files ID_LOOKUP` — prints IdentityFile entries for a host (dim style)
- `_prompt_remote` — prompts for host + user, sets `_REMOTE_HOST`, `_REMOTE_USER`, `_REMOTE_ALIAS`

### prompts.sh

- `read_colored_input PROMPT COLOR` — single-line text input with ESC cancel, Ctrl+W word-delete
- `read_host_with_default PROMPT DEFAULT` — pre-filled editable input
- `read_remote_host_address` — shows host selector or accepts manual IP/subnet shorthand (e.g. `"10"` → `"192.168.0.10"`)
- `read_remote_user` / `read_remote_host_name` / `read_ssh_key_name` / `read_ssh_key_comment`
- `confirm_user_choice MESSAGE DEFAULT ACTION_FN` — y/N confirmation that calls a callback

### ssh-ops.sh

All status/feedback output uses `_out`/`_out_item` — no raw `\e[` escape codes.

- `test_ssh_connection USER HOST [IDENTITY]` — uses `-F /dev/null -o IdentitiesOnly=yes -o PreferredAuthentications=publickey` when an identity is given, bypassing the config block entirely to avoid false-positive fallbacks
- `add_ssh_key_in_host KEYNAME COMMENT` — generates an ED25519 key pair
- `add_ssh_key_to_host_config KEYNAME HOST_NAME HOST_ADDR USER` — creates or updates a Host block
- `remove_identity_file_from_config_block KEYNAME HOST_ALIAS`
- `install_ssh_key_on_remote KEYNAME` — copies public key to remote `authorized_keys`, then registers config
- `deploy_ssh_key_to_remote KEYNAME` — generates if missing, then installs
- `remove_ssh_key_from_remote USER HOST KEYNAME`
- `register_remote_host_config` — connects and matches remote `authorized_keys` against local keys
- `_add_key_to_hosts KEYNAME` — multi-select host checklist, appends `IdentityFile` to chosen blocks
- `import_external_ssh_key` — import from local path, SCP, or paste
- `deploy_promoted_key` — key rotation (deploy new, remove old)

### config-display.sh

Read-only views:
- `show_ssh_config_file` — paginated SSH config viewer with inline editor launch
- `show_ssh_key_inventory` — lists local keys, their fingerprints, and which hosts reference them
- `remove_host_from_ssh_config` — removes a Host block after confirmation

### menu.sh

- `show_main_menu()` — scrolling viewport, differential rendering, hotkey support, resize detection. Alternate screen buffer (`\e[?1049h/l`).
- `invoke_menu_choice()` — dispatches all 17 menu cases
- `_menu_cleanup` — restores terminal state; guarded by `_MENU_CLEANED_UP` flag to prevent double-execution on Ctrl+C (INT trap → `exit` → EXIT trap)
- `wait_user_acknowledge` — "Press any key" gate between operations and menu

## Key implementation notes

- **No subprocess forks in render loops.** `$(printf ...)` costs ~1ms per call. Use `printf -v varname` instead.
- **SSH test isolation.** `-F /dev/null` bypasses `~/.ssh/config` entirely; `-o IdentitiesOnly=yes` alone is insufficient because it still allows keys from the matching config block.
- **Passphrase-protected keys.** Never use `-o BatchMode=yes` when testing keys — it blocks passphrase prompts. Use `-o PreferredAuthentications=publickey` to restrict to key auth without silencing prompts.
- **`_LAST_SELECTED_ALIAS` subshell loss.** Any global set inside `$()` is discarded. Use `get_alias_for_host_ip` as a reverse-lookup after the subshell returns, or use `_prompt_remote` which handles this correctly.
- **Ctrl+C guard.** The INT/TERM/TSTP traps only set the exit code; cleanup lives exclusively in the EXIT trap. The `_MENU_CLEANED_UP=1` flag prevents a second cleanup run.
- **`authorized_keys` newline.** `printf '%s'` (not `printf '%s\n'`) when writing the public key — the `.pub` file already ends with `\n`.

## Bash vs PowerShell parity

When modifying behavior, changes typically need to be mirrored in `generate_key_test.ps1`. Bash uses `stty`/`read` for terminal I/O; PowerShell uses `Host.UI.RawUI.ReadKey()` and `[Console]::Write()`. Config parsing in Bash uses `perl`/`awk`/`sed`; PowerShell uses `[regex]` class methods.
