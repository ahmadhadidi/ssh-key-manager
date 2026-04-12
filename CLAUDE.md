# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A terminal-based SSH key manager with an interactive TUI (Text User Interface). It automates ED25519 key generation, deployment to remote machines, SSH config management, connection testing, and key rotation/cleanup.

Two parallel implementations exist:
- `hddssh.sh` — Linux/macOS (Bash 4+), entry point (~47 lines); logic lives in `lib/bash/`
- `hddssh.ps1` — Windows (PowerShell 5+), entry point (~47 lines); logic lives in `lib/ps/`

## Running

**Bash:**
```bash
bash hddssh.sh
bash hddssh.sh --user myuser --subnet 192.168.0 --comment-suffix "-[prod]" --password "mypass"
```

**PowerShell:**
```powershell
. .\hddssh.ps1
& ./hddssh.ps1 -DefaultUserName "root" -DefaultSubnetPrefix "192.168.0"
```

There is no build step, test framework, or linter. Both scripts run directly with no dependencies beyond Bash/PowerShell and OpenSSH (`ssh`, `ssh-keygen`). `sshpass` is optional for password-based remote auth.

## Architecture (Bash)

`hddssh.sh` parses CLI args, sets globals, then sources the lib modules in order and calls `show_main_menu()`. The lib modules are loaded locally from `lib/bash/` when the directory exists, or fetched via `curl` from the GitHub raw URL when run remotely.

### Library load order

```
tui → ssh-config → ssh-helpers → prompts → ssh-ops → config-display → menu → menu-renderer
```

Each module has a guard variable (`_<MODULE>_SH_LOADED`) to prevent double-sourcing.

### Cross-file dependencies

When modifying a module, these are the other files that call its functions:

| Modified module | Must also check | Key cross-module calls |
|---|---|---|
| `tui.sh` | all 5 others | `_repeat`, `_term_size`, `_regex_escape`, `_dbg` used everywhere; `select_from_list` called from prompts/ssh-ops/config-display/menu; `_read_key`/`_read_key_nb` used by prompts/config-display/menu |
| `ssh-config.sh` | ssh-helpers, prompts, ssh-ops, config-display, menu | `get_configured_ssh_hosts` (prompts×2, ssh-ops×2, config-display, menu×2); `_get_host_block`/`_replace_host_block` (ssh-ops×3, config-display, menu); `get_alias_for_host_ip` (ssh-helpers); `get_identity_files_for_host` (ssh-helpers, menu) |
| `ssh-helpers.sh` | ssh-ops, config-display, menu | `_out`/`_out_item` called throughout ssh-ops and menu; `show_op_banner` (config-display×3, menu×9); `_prompt_remote` (ssh-ops×2, menu×3); `_ssh_fence`/`_ssh_fence_close` (ssh-ops×4, menu×4); `_setup_askpass`/`_destroy_askpass` (menu only) |
| `prompts.sh` | ssh-ops, config-display, menu | `read_ssh_key_name` (ssh-ops×2, menu×3); `find_private_key` (ssh-ops, menu×2); `resolve_ssh_target` (ssh-ops×2, menu×2); `confirm_user_choice` (ssh-ops×2, config-display, menu×2); `read_colored_input` (ssh-ops×3, config-display×2, menu×2) |
| `ssh-ops.sh` | menu only | All 11 public functions called exclusively from `_menu_*` handlers in menu.sh |
| `config-display.sh` | menu only | `show_ssh_config_file`, `edit_ssh_config_file`, `show_ssh_key_inventory`, `remove_host_from_ssh_config` called from `_menu_*` handlers in menu.sh |
| `menu.sh` | menu-renderer only | `invoke_menu_choice` called from `_invoke_choice` in menu-renderer.sh; `_check_config_at_start`, `_do_create_config`, `_show_menu_help` called from `show_main_menu` in menu-renderer.sh |

### Module breakdown

| File | Lines | Responsibility | Key functions |
|------|-------|----------------|---------------|
| `tui.sh` | ~482 | Terminal primitives, TUI widgets | `_read_key`:41, `_read_key_raw`:108, `select_from_list`:313, `select_multi_from_list`:199, `show_paged`:160 |
| `ssh-config.sh` | ~151 | `~/.ssh/config` parsing | `get_configured_ssh_hosts`:14, `_get_host_block`:44, `_replace_host_block`:138, `get_alias_for_host_ip`:104 |
| `ssh-helpers.sh` | ~250 | Shared SSH utility helpers and output helpers | `_out`:16, `show_op_banner`:52, `_prompt_remote`:246, `_setup_askpass`:179 |
| `prompts.sh` | ~346 | Input prompts and host/key finders | `read_colored_input`:14, `read_remote_host_address`:149, `confirm_user_choice`:264 |
| `ssh-ops.sh` | ~511 | SSH key operations | `deploy_ssh_key_to_remote`:15, `test_ssh_connection`:85, `add_ssh_key_in_host`:253, `import_external_ssh_key`:398 |
| `config-display.sh` | ~480 | Read-only config/inventory display | `show_ssh_config_file`:12, `show_ssh_key_inventory`:193, `remove_host_from_ssh_config`:146 |
| `menu.sh` | ~620 | Menu dispatcher and all 18 `_menu_*` handlers | `invoke_menu_choice`:17, `_menu_generate_and_install`:45, `_show_menu_help`:539 |
| `menu-renderer.sh` | ~340 | TUI event loop, operation runner | `_invoke_choice`:13, `show_main_menu`:53 |

### Control flow

1. Parse CLI args → set defaults
2. `show_main_menu()` enters the event loop (raw terminal, non-blocking key reads with ~50ms timeout for resize detection)
3. User selects one of 17 menu options → `invoke_menu_choice()` dispatches to the appropriate function
4. Operation completes → `wait_user_acknowledge()` → return to menu

### tui.sh

- `_dbg`:12, `_term_size`:19, `_regex_escape`:24, `_repeat`:29, `_max`:35, `_min`:36
- `_read_key`:41 / `_read_key_nb`:73 / `_read_key_raw`:108 — Raw terminal key capture, handles multi-byte escape sequences (arrow keys). Uses `stty` raw mode; avoid adding subprocess forks inside the render loop.
- `wait_user_acknowledge`:150 — "Press any key" gate (also in menu.sh dispatcher)
- `show_paged`:160 — Paginator for long output.
- `format_menu_label`:185 — Hotkey character highlighting.
- `select_multi_from_list`:199 — Checkbox list with Space toggle, Enter confirm, ESC cancel.
- `select_from_list`:313 — Core combo-box widget with incremental filtering — used for picking hosts, keys, and users throughout. Render loop uses `printf -v` (zero-fork) instead of `$(printf ...)`.
- ANSI escape sequences used directly (cursor positioning, colors, bold, hide/show cursor).
- Terminal resize detected by comparing `tput cols/lines` between key-read cycles.

### ssh-config.sh

Reads `~/.ssh/config` using `perl`, `awk`, `grep`:
- `get_configured_ssh_hosts`:14 — emits `alias|hostname|user` tuples
- `get_available_ssh_keys`:28 — lists private keys in `~/.ssh`
- `_get_host_block`:44 / `_replace_host_block`:138 — multiline Host block read/write
- `_block_field`:96 — extract a single field from a Host block
- `get_identity_files_for_host`:55 / `get_hosts_using_key`:82 — cross-reference keys and hosts
- `get_alias_for_host_ip`:104 — reverse-lookup Host alias from a HostName IP
- `get_ip_from_host_config`:113, `get_user_from_host_config`:119, `get_identity_file_from_host_config`:125

### ssh-helpers.sh

Shared helpers sourced by both `ssh-ops.sh` and `menu.sh`. Must be loaded after `tui` and `ssh-config` (depends on `_repeat` and `get_alias_for_host_ip`).

**Output helpers:**
- `_out`:16 `STYLE FORMAT [ARGS...]` — 2-space indented, color-coded line to stdout.
  Styles: `ok` (green), `warn` (yellow), `error` (red), `info` (cyan), `dim` (gray), `heading` (bright-cyan), `plain` (bright-white).
- `_out_item`:35 `FORMAT [ARGS...]` — green `+` prefix, plain text.
- `show_op_banner`:52

**SSH/filesystem helpers:**
- `_tcp_check`:139 `HOST` — TCP port-22 reachability check
- `_ssh_fence`:145 `TARGET` / `_ssh_fence_close`:164 — decorative rule printed around SSH sessions
- `_setup_askpass`:179 / `_destroy_askpass`:195 — temporary `SSH_ASKPASS` script for padded prompts
- `_ensure_ssh_dir`:203 — `mkdir -p ~/.ssh && chmod 700`
- `_write_key_pair`:214 `DEST_PRIV DEST_PUB DATA DATA [copy_mode]` — write or copy a key pair with permission enforcement
- `_print_identity_files`:235 `ID_LOOKUP` — prints IdentityFile entries for a host (dim style)
- `_prompt_remote`:246 — prompts for host + user, sets `_REMOTE_HOST`, `_REMOTE_USER`, `_REMOTE_ALIAS`

### prompts.sh

- `read_colored_input`:14 `PROMPT COLOR` — single-line text input with ESC cancel, Ctrl+W word-delete
- `read_host_with_default`:96 `PROMPT DEFAULT` — pre-filled editable input
- `read_remote_host_address`:149 — shows host selector or accepts manual IP/subnet shorthand (e.g. `"10"` → `"192.168.0.10"`)
- `read_remote_user`:144 / `read_remote_host_name`:210 / `read_ssh_key_name`:235 / `read_ssh_key_comment`:258
- `confirm_user_choice`:264 `MESSAGE DEFAULT ACTION_FN` — y/N confirmation that calls a callback
- `find_config_file`:295 / `find_private_key`:304 / `find_public_key`:309 / `get_public_key`:314
- `resolve_ssh_target`:329

### ssh-ops.sh

All status/feedback output uses `_out`/`_out_item` — no raw `\e[` escape codes.

- `deploy_ssh_key_to_remote`:15 `KEYNAME` — generates if missing, then installs
- `install_ssh_key_on_remote`:33 `KEYNAME` — copies public key to remote `authorized_keys`, then registers config
- `test_ssh_connection`:85 `USER HOST [IDENTITY]` — uses `-F /dev/null -o IdentitiesOnly=yes -o PreferredAuthentications=publickey` when an identity is given, bypassing the config block entirely to avoid false-positive fallbacks
- `remove_ssh_key_from_remote`:135 `USER HOST KEYNAME`
- `deploy_promoted_key`:168 — key rotation (deploy new, remove old)
- `register_remote_host_config`:193 — connects and matches remote `authorized_keys` against local keys
- `add_ssh_key_in_host`:253 `KEYNAME COMMENT` — generates an ED25519 key pair
- `add_ssh_key_to_host_config`:284 `KEYNAME HOST_NAME HOST_ADDR USER` — creates or updates a Host block
- `remove_identity_file_from_config_block`:335 `KEYNAME HOST_ALIAS`
- `_add_key_to_hosts`:360 `KEYNAME` — multi-select host checklist, appends `IdentityFile` to chosen blocks
- `import_external_ssh_key`:398 — import from local path, SCP, or paste

### config-display.sh

Read-only views:
- `show_ssh_config_file`:12 — paginated SSH config viewer with inline editor launch
- `edit_ssh_config_file`:122
- `remove_host_from_ssh_config`:146 — removes a Host block after confirmation
- `show_ssh_key_inventory`:193 — lists local keys, their fingerprints, and which hosts reference them
- `_view_ssh_key`:376 / `_display_key_file`:416

### menu.sh

- `invoke_menu_choice`:17 — 22-line pure dispatcher; each case calls a `_menu_*` handler
- `_menu_generate_and_install`:45 / `_menu_install_key`:51 / `_menu_test_connection`:61
- `_menu_delete_remote_key`:118 / `_menu_promote_key`:201 / `_menu_generate_key`:206
- `_menu_append_key_to_config`:213 / `_menu_delete_local_key`:242 / `_menu_remove_key_from_config`:296
- `_menu_show_best_practices`:328 / `_menu_list_authorized_keys`:362
- `_menu_add_config_block`:389 / `_menu_import_key`:394
- `_run_conf_editor`:400 / `_do_create_config`:500 / `_check_config_at_start`:510
- `_show_menu_help`:539

### menu-renderer.sh

- `_invoke_choice`:13 — clears screen, renders centered op title box, calls `invoke_menu_choice`, waits for ack. Sets `need_full=1` via bash dynamic scoping into `show_main_menu`'s local frame.
- `show_main_menu`:53 — scrolling viewport, differential rendering, hotkey support, resize detection. Alternate screen buffer (`\e[?1049h/l`).
- `_menu_cleanup` — defined inside `show_main_menu`; restores terminal state; guarded by `_MENU_CLEANED_UP` flag to prevent double-execution on Ctrl+C (INT trap → `exit` → EXIT trap)

## Key implementation notes

- **No subprocess forks in render loops.** `$(printf ...)` costs ~1ms per call. Use `printf -v varname` instead.
- **SSH test isolation.** `-F /dev/null` bypasses `~/.ssh/config` entirely; `-o IdentitiesOnly=yes` alone is insufficient because it still allows keys from the matching config block.
- **Passphrase-protected keys.** Never use `-o BatchMode=yes` when testing keys — it blocks passphrase prompts. Use `-o PreferredAuthentications=publickey` to restrict to key auth without silencing prompts.
- **`_LAST_SELECTED_ALIAS` subshell loss.** Any global set inside `$()` is discarded. Use `get_alias_for_host_ip` as a reverse-lookup after the subshell returns, or use `_prompt_remote` which handles this correctly.
- **Ctrl+C guard.** The INT/TERM/TSTP traps only set the exit code; cleanup lives exclusively in the EXIT trap. The `_MENU_CLEANED_UP=1` flag prevents a second cleanup run.
- **`authorized_keys` newline.** `printf '%s'` (not `printf '%s\n'`) when writing the public key — the `.pub` file already ends with `\n`.
- **`_read_key_raw` vs `_read_key`.** `_read_key_raw` skips the `stty` save/restore (2 subprocess forks). Use it only when the caller already holds raw mode — i.e., inside `select_from_list` and `select_multi_from_list` render loops. `_read_key` manages its own mode and is safe to call anywhere else.
- **`select_from_list` writes to `/dev/tty`, result in `_SELECT_RESULT`.** All TUI rendering goes to `/dev/tty` (fallback: `/proc/self/fd/2`) so the widget works correctly inside `$(...)` subshells. Never capture the return value with `$(select_from_list ...)` — it will be empty. Read `_SELECT_RESULT` and check `_SELECT_CANCELLED` after the call returns.
- **`_HOST_BLOCK` global is overwritten on every `_get_host_block` call.** Consume `_HOST_BLOCK` immediately after calling `_get_host_block`; any subsequent call (including those inside helpers like `_block_field` callers) will clobber it.
- **`show_op_banner` dual mode.** Default (stream) prints directly to stdout. Buffer mode: set `_OP_BANNER_ROW` to the starting row before calling — output goes into `_OP_BANNER_BUF` for the caller to append to its frame. Always sets `_SFL_BANNER_ROWS=5` so `select_from_list`/`select_multi_from_list` offset their start row below the banner.
- **`_replace_host_block` silent failure.** Uses `perl` with `python3` fallback. If neither is present it returns 1 and the config block is not updated — callers must handle this or changes are silently lost.
- **`select_from_list` strict mode (`-s`).** Enter is a no-op unless exactly one filtered item remains. Without `-s`, Enter with a non-empty filter string creates a new item from the typed text — intentional for key-name and host-name inputs.
- **`_write_key_pair` public key normalization.** In non-copy mode it writes `"${pub_data%$'\n'}"` then appends `\n` — strips any trailing newline from the passed string and adds exactly one back, so `.pub` files always end with exactly one newline regardless of source.
- **`get_identity_file_from_host_config` expands `~` and `$HOME`.** Other `ssh-config.sh` getters return raw strings. Only this function substitutes `~` → `$HOME` in the returned path; callers of other getters must expand paths themselves if needed.

## Architecture (PowerShell)

`hddssh.ps1` sets globals, then dot-sources the lib modules in order and calls `Show-MainMenu`. The lib modules are loaded locally from `lib/ps/` when the directory exists, or fetched via `Invoke-RestMethod` from the GitHub raw URL when run remotely.

### Library load order

```
tui → ssh-helpers → ssh-config → prompts → ssh-ops → config-display → menu
```

### Module breakdown

| File | Lines | Responsibility | Key functions |
|------|-------|----------------|---------------|
| `tui.ps1` | ~232 | Terminal primitives, TUI widgets | `Select-FromList`:49, `Select-MultiFromList`:143, `Wait-UserAcknowledge`:5 |
| `ssh-helpers.ps1` | ~238 | Shared SSH utility helpers and output helpers | `Write-Out`:8, `Show-OpBanner`:45, `Invoke-RemotePrompt`:174 |
| `ssh-config.ps1` | ~193 | `~/.ssh/config` parsing | `Get-ConfiguredSSHHosts`:34, `Get-AliasForHostIP`:168, `Get-AvailableSSHKeys`:9 |
| `prompts.ps1` | ~209 | Input prompts and host/key finders | `Read-ColoredInput`:92, `Read-RemoteHostAddress`:34, `Confirm-UserChoice`:157 |
| `ssh-ops.ps1` | ~488 | SSH key operations | `Deploy-SSHKeyToRemote`:138, `Test-SSHConnection`:153, `Import-ExternalSSHKey`:329 |
| `config-display.ps1` | ~529 | Read-only config/inventory display | `Show-SSHConfigFile`:136, `Show-SSHKeyInventory`:252, `Add-SSHKeyInHost`:6 |
| `menu.ps1` | ~619 | Main menu, dispatcher, all menu cases | `Show-MainMenu`:4, `Invoke-MenuChoice`:247 |

### tui.ps1

- `Wait-UserAcknowledge`:5 / `Show-Paged`:21 / `Select-FromList`:49 / `Select-MultiFromList`:143 / `Format-MenuLabel`:228

### ssh-helpers.ps1

- `Write-Out`:8 / `Write-OutItem`:33 / `Show-OpBanner`:45
- `Write-SSHFence`:137 / `Write-SSHFenceClose`:157
- `Invoke-RemotePrompt`:174 / `Write-IdentityFiles`:188 / `Ensure-SSHDir`:199 / `Write-KeyPair`:207

### ssh-config.ps1

- `Get-AvailableSSHKeys`:9 / `Get-HostsUsingKey`:19 / `Get-ConfiguredSSHHosts`:34
- `Get-IdentityFilesForHost`:51 / `Get-IdentityFileFromHostConfigEntry`:73
- `Find-ConfigFileOnHost`:88 / `Find-SSHKeyInHostConfig`:98 / `Find-PrivateKeyInHost`:126 / `Find-PublicKeyInHost`:139
- `Get-IPAddressFromHostConfigEntry`:152 / `Get-AliasForHostIP`:168 / `Get-RemoteUserFromConfigEntry`:180

### prompts.ps1

- `Read-RemoteUser`:7 / `Read-RemoteHostName`:14 / `Read-RemoteHostAddress`:34
- `Read-SSHKeyName`:75 / `Read-SSHKeyComment`:86 / `Read-ColoredInput`:92 / `Read-HostWithDefault`:102
- `Resolve-NullToDefault`:133 / `Resolve-NullToAction`:142 / `Confirm-UserChoice`:157
- `Test-ValueIsNull`:184 / `Get-PublicKeyInHost`:190 / `Show-Comment`:203

### ssh-ops.ps1

- `Resolve-SSHTarget`:8 / `Install-SSHKeyOnRemote`:36 / `Register-RemoteHostConfig`:80
- `Deploy-SSHKeyToRemote`:138 / `Test-SSHConnection`:153
- `Remove-IdentityFileFromConfigBlock`:210 / `Remove-SSHKeyFromRemote`:234
- `Deploy-PromotedKey`:274 / `Add-KeyToHosts`:294 / `Import-ExternalSSHKey`:329
- `Remove-IdentityFileFromConfigEntry`:434 / `Invoke-SSHWithKeyThenPassword`:467

### config-display.ps1

- `Add-SSHKeyInHost`:6 / `Add-SSHKeyToHostConfig`:37 / `Remove-HostFromSSHConfig`:86
- `Show-SSHConfigFile`:136 / `Edit-SSHConfigFile`:225 / `Show-SSHKeyInventory`:252
- `_ViewSSHKey`:428 / `_DisplayKeyFile`:470

### menu.ps1

- `Show-MainMenu`:4 / `_InvokeMenuAction`:219 / `Invoke-MenuChoice`:247

## Bash vs PowerShell parity

When modifying behavior, changes typically need to be mirrored in the counterpart lib files. Bash uses `stty`/`read` for terminal I/O; PowerShell uses `Host.UI.RawUI.ReadKey()` and `[Console]::Write()`. Config parsing in Bash uses `perl`/`awk`/`sed`; PowerShell uses `[regex]` class methods.
