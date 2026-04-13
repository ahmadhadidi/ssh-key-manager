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
tui → ssh-config → ssh-helpers → prompts → ssh-ops → config-display → menu → menu-support → menu-renderer
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
| `menu.sh` | menu-renderer only | `invoke_menu_choice` called from `_invoke_choice` in menu-renderer.sh; `_check_config_at_start`, `_do_create_config` called from `show_main_menu` in menu-renderer.sh |
| `menu-support.sh` | menu-renderer only | `_run_conf_editor` called from `_menu_conf_defaults` in menu.sh; `_show_menu_help` called from `show_main_menu` in menu-renderer.sh |

### Module breakdown

| File | Lines | Responsibility | Key functions |
|------|-------|----------------|---------------|
| `tui.sh` | ~485 | Terminal primitives, TUI widgets | `_read_key`:41, `_read_key_raw`:105, `select_from_list`:316, `select_multi_from_list`:202, `show_paged`:157 |
| `ssh-config.sh` | ~151 | `~/.ssh/config` parsing | `get_configured_ssh_hosts`:14, `_get_host_block`:44, `_replace_host_block`:138, `get_alias_for_host_ip`:104 |
| `ssh-helpers.sh` | ~250 | Shared SSH utility helpers and output helpers | `_out`:16, `show_op_banner`:52, `_prompt_remote`:246, `_setup_askpass`:179 |
| `prompts.sh` | ~346 | Input prompts and host/key finders | `read_colored_input`:14, `read_remote_host_address`:149, `confirm_user_choice`:264 |
| `ssh-ops.sh` | ~511 | SSH key operations | `deploy_ssh_key_to_remote`:15, `test_ssh_connection`:85, `add_ssh_key_in_host`:253, `import_external_ssh_key`:398 |
| `config-display.sh` | ~480 | SSH config viewer, key inventory display, host removal | `show_ssh_config_file`:12, `show_ssh_key_inventory`:193, `remove_host_from_ssh_config`:146 |
| `menu.sh` | ~437 | Menu dispatcher and all 18 `_menu_*` handlers | `invoke_menu_choice`:17, `_menu_generate_and_install`:45, `_do_create_config`:402 |
| `menu-support.sh` | ~192 | Conf defaults editor TUI and menu help screen | `_run_conf_editor`:12, `_show_menu_help`:111 |
| `menu-renderer.sh` | ~341 | TUI event loop, operation runner | `_invoke_choice`:13, `show_main_menu`:53 |

### Control flow

1. Parse CLI args → set defaults
2. `show_main_menu()` enters the event loop (raw terminal, non-blocking key reads with ~50ms timeout for resize detection)
3. User selects one of 17 menu options → `invoke_menu_choice()` dispatches to the appropriate function
4. Operation completes → `wait_user_acknowledge()` → return to menu

### tui.sh

- `_dbg`:12, `_term_size`:19, `_regex_escape`:24, `_repeat`:29, `_max`:35, `_min`:36
- `_read_key`:41 / `_read_key_nb`:75 / `_read_key_raw`:105 — Raw terminal key capture, handles multi-byte escape sequences (arrow keys). Uses `stty` raw mode; avoid adding subprocess forks inside the render loop.
- `wait_user_acknowledge`:147 — "Press any key" gate (also in menu.sh dispatcher)
- `show_paged`:157 — Paginator for long output.
- `format_menu_label`:182 — Hotkey character highlighting.
- `select_multi_from_list`:202 — Checkbox list with Space toggle, Enter confirm, ESC cancel.
- `select_from_list`:316 — Core combo-box widget with incremental filtering — used for picking hosts, keys, and users throughout. Render loop uses `printf -v` (zero-fork) instead of `$(printf ...)`.
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

- `show_ssh_config_file`:12 — paginated SSH config viewer with inline editor launch
- `edit_ssh_config_file`:122
- `remove_host_from_ssh_config`:146 — removes a Host block after confirmation
- `show_ssh_key_inventory`:193 — lists local keys, their fingerprints, and which hosts reference them
- `_view_ssh_key`:376 / `_display_key_file`:416

### menu.sh

- `invoke_menu_choice`:17 — 22-line pure dispatcher; each case calls a `_menu_*` handler
- `_menu_generate_and_install`:45 — prompts key name, generates if missing, deploys to remote (`deploy_ssh_key_to_remote`)
- `_menu_install_key`:51 — same but requires key to already exist locally; aborts with message if not found
- `_menu_test_connection`:61 — picks key from host config or all local keys; supports "Test ALL" multi-key sweep
- `_menu_delete_remote_key`:118 — fetches remote `authorized_keys`, cross-matches local `.pub` files, removes selected; offers to strip IdentityFile from config and delete local key pair
- `_menu_promote_key`:201 — delegates to `deploy_promoted_key` (installs new key, removes old in one operation)
- `_menu_generate_key`:206 — prompts key name + comment, generates ED25519 pair locally without deploying
- `_menu_append_key_to_config`:213 — verifies key is accepted by remote via SSH test, then adds IdentityFile to host config block
- `_menu_delete_local_key`:242 — cross-references key against configured hosts, optionally removes from remote(s), then deletes local key files
- `_menu_remove_key_from_config`:296 — picks host then IdentityFile entry, removes that line from the config block
- `_menu_show_best_practices`:328 — prints the 4-rule key-naming guide (LAN shared vs WAN individual); no interactive input
- `_menu_list_keys`:338 — calls `show_ssh_key_inventory`; returns 1 to skip `wait_user_acknowledge`
- `_menu_conf_defaults`:343 — launches `_run_conf_editor` TUI; returns 1 to skip `wait_user_acknowledge`
- `_menu_remove_host`:348 — delegates to `remove_host_from_ssh_config`
- `_menu_view_config`:352 — calls `show_ssh_config_file`; returns 1 to skip `wait_user_acknowledge`
- `_menu_edit_config`:357 — calls `edit_ssh_config_file`; returns 1 to skip `wait_user_acknowledge`
- `_menu_list_authorized_keys`:362 — SSHes to target, fetches `authorized_keys`, displays numbered list
- `_menu_add_config_block`:389 — delegates to `register_remote_host_config` (reads remote auth_keys, creates host config entry)
- `_menu_import_key`:394 — delegates to `import_external_ssh_key` (local path / SCP / paste)
- `_do_create_config`:402 — creates `~/.ssh/config` with 600 permissions; sets `_CONFIG_MISSING=0`
- `_check_config_at_start`:412 — full-screen prompt on startup when config absent; offers to create it

### menu-support.sh

- `_run_conf_editor`:12 — inline TUI for editing DEFAULT_USER/SUBNET/COMMENT_SUFFIX/PASSWORD; shows 4 copy-paste launch commands with current flag values
- `_show_menu_help`:111 — paginated help text describing every menu item

### menu-renderer.sh

- `_invoke_choice`:13 — clears screen, renders centered op title box, calls `invoke_menu_choice`, waits for ack. Sets `need_full=1` via bash dynamic scoping into `show_main_menu`'s local frame.
- `show_main_menu`:53 — scrolling viewport, differential rendering, hotkey support, resize detection. Alternate screen buffer (`\e[?1049h/l`).
- `_menu_cleanup` — defined inside `show_main_menu`; restores terminal state; guarded by `_MENU_CLEANED_UP` flag to prevent double-execution on Ctrl+C (INT trap → `exit` → EXIT trap)

## Key implementation notes

- **Remote lib loading uses temp files, not nested process substitution.** `source <(curl ...)` nested inside `bash <(curl ...)` fails on macOS — the outer process substitution holds a `/dev/fd` FD, and opening more FDs for inner substitutions causes curl to get a closed pipe (`Failure writing output to destination`). Fix: `_source_lib` downloads each lib to a `mktemp` file, sources it, then deletes it.
- **`format_menu_label` uses pure bash regex, not `sed`.** BSD sed (macOS) does not support `\x1b` in replacements, and embedding a raw ESC byte in the sed replacement string is unreliable across platforms. The function uses `[[ =~ ]]` with `BASH_REMATCH` — `^([^lo_up]*)(char)(.*)$` finds the first hotkey occurrence — then `printf '\e[1;4m...\e[0;97m'` wraps it. No subprocess, no platform differences.
- **No subprocess forks in render loops.** `$(printf ...)` costs ~1ms per call. Use `printf -v varname` instead.
- **SSH test isolation.** `-F /dev/null` bypasses `~/.ssh/config` entirely; `-o IdentitiesOnly=yes` alone is insufficient because it still allows keys from the matching config block.
- **Passphrase-protected keys.** Never use `-o BatchMode=yes` when testing keys — it blocks passphrase prompts. Use `-o PreferredAuthentications=publickey` to restrict to key auth without silencing prompts.
- **`_LAST_SELECTED_ALIAS` subshell loss.** Any global set inside `$()` is discarded. Use `get_alias_for_host_ip` as a reverse-lookup after the subshell returns, or use `_prompt_remote` which handles this correctly.
- **Ctrl+C guard.** The INT/TERM/TSTP traps only set the exit code; cleanup lives exclusively in the EXIT trap. The `_MENU_CLEANED_UP=1` flag prevents a second cleanup run.
- **`authorized_keys` newline.** `printf '%s'` (not `printf '%s\n'`) when writing the public key — the `.pub` file already ends with `\n`.
- **`_read_key_raw` vs `_read_key` vs `_read_key_nb`.** `_read_key_raw` and `_read_key_nb` both skip `stty` save/restore (2 subprocess forks each). `_read_key_nb` is used exclusively by the `show_main_menu` poll loop which already holds raw mode. `_read_key_raw` is used inside `select_from_list`/`select_multi_from_list` render loops which also hold raw mode. `_read_key` manages its own stty mode and is safe to call from anywhere else.
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
tui → ssh-helpers → ssh-config → prompts → ssh-ops → config-display → menu → menu-renderer
```

### Module breakdown

| File | Lines | Responsibility | Key functions |
|------|-------|----------------|---------------|
| `tui.ps1` | ~232 | Terminal primitives, TUI widgets | `Select-FromList`:49, `Select-MultiFromList`:143, `Wait-UserAcknowledge`:5 |
| `ssh-helpers.ps1` | ~238 | Shared SSH utility helpers and output helpers | `Write-Out`:8, `Show-OpBanner`:45, `Invoke-RemotePrompt`:174 |
| `ssh-config.ps1` | ~193 | `~/.ssh/config` parsing | `Get-ConfiguredSSHHosts`:34, `Get-AliasForHostIP`:168, `Get-AvailableSSHKeys`:9 |
| `prompts.ps1` | ~209 | Input prompts and host/key finders | `Read-ColoredInput`:92, `Read-RemoteHostAddress`:34, `Confirm-UserChoice`:157 |
| `ssh-ops.ps1` | ~569 | SSH key generation, deploy, install, test, remove, promote | `Add-SSHKeyInHost`:9, `Add-SSHKeyToHostConfig`:40, `Deploy-SSHKeyToRemote`:219, `Test-SSHConnection`:234 |
| `config-display.ps1` | ~449 | SSH config viewer, key inventory display, host removal | `Show-SSHConfigFile`:56, `Show-SSHKeyInventory`:172, `Remove-HostFromSSHConfig`:6 |
| `menu.ps1` | ~430 | Menu dispatcher and all 18 `_Menu*` handlers | `Invoke-MenuChoice`:13, `_MenuGenerateAndInstall`:39, `_MenuConfDefaults`:283 |
| `menu-renderer.ps1` | ~246 | TUI event loop and operation runner | `Show-MainMenu`:6, `_InvokeMenuAction`:221 |

### Cross-file dependencies (PowerShell)

When modifying a PS module, these are the other files that call its functions:

| Modified module | Must also check | Key cross-module calls |
|---|---|---|
| `tui.ps1` | all others | `Select-FromList` (prompts×2, ssh-ops×3, config-display×3, menu×5); `Select-MultiFromList` (ssh-ops); `Wait-UserAcknowledge`/`Format-MenuLabel` (menu-renderer) |
| `ssh-helpers.ps1` | ssh-config, prompts, ssh-ops, config-display, menu | `Write-Out`/`Write-OutItem` called throughout; `Show-OpBanner` (config-display×2, menu×9); `Invoke-RemotePrompt` (ssh-ops×3, menu×4); `Write-SSHFence`/`Write-SSHFenceClose` (ssh-ops×4, menu×3); `Write-IdentityFiles` (ssh-ops×2, menu); `Ensure-SSHDir`/`Write-KeyPair` (ssh-ops) |
| `ssh-config.ps1` | ssh-helpers, prompts, ssh-ops, config-display, menu | `Get-ConfiguredSSHHosts` (prompts×2, config-display, menu); `Get-AvailableSSHKeys` (prompts); `Get-IdentityFilesForHost` (ssh-helpers, menu); `Get-AliasForHostIP` (ssh-helpers); `Get-HostsUsingKey` (menu); `Find-PrivateKeyInHost` (ssh-ops, config-display, menu); `Find-ConfigFileOnHost` (ssh-ops×2, config-display×2); `Get-IPAddressFromHostConfigEntry`/`Get-RemoteUserFromConfigEntry` (ssh-ops) |
| `prompts.ps1` | ssh-helpers, ssh-ops, config-display, menu | `Read-RemoteUser`/`Read-RemoteHostAddress` (ssh-helpers); `Read-RemoteHostName` (ssh-ops); `Read-SSHKeyName` (ssh-ops×2, menu×3); `Read-HostWithDefault` (ssh-ops×2, menu); `Read-ColoredInput` (ssh-ops×2, config-display, menu); `Confirm-UserChoice` (ssh-ops×3, config-display, menu); `Get-PublicKeyInHost` (ssh-ops×2) |
| `ssh-ops.ps1` | menu only | All 14 public functions called from `_Menu*` handlers in menu.ps1 |
| `config-display.ps1` | menu only | `Show-SSHConfigFile`/`Edit-SSHConfigFile`/`Show-SSHKeyInventory`/`Remove-HostFromSSHConfig` (menu only) |

### tui.ps1

- `Wait-UserAcknowledge`:5 — ignores modifier-only keys (Shift, Ctrl, Alt, CapsLock, NumLock); falls back to `Read-Host` if `ReadKey` throws (non-interactive host)
- `Show-Paged`:21 — page size = `WindowHeight - 4` (min 5); Q quits, Enter advances
- `Select-FromList`:49 — combo-box; returns value directly (not via side-effect global like bash `_SELECT_RESULT`); throws `[System.OperationCanceledException]` on Esc; `-StrictList` means Enter only accepts a highlighted item or the sole filtered match; without `-StrictList`, Enter with non-empty filter returns the typed text as a new name — intentional for key-name and host-name creation inputs
- `Select-MultiFromList`:143 — checkbox list; Space toggles, Enter confirms; returns `[string[]]` (may be empty array); throws `[System.OperationCanceledException]` on Esc
- `Format-MenuLabel`:228 — uses `[regex]::Replace` case-insensitively to bold+underline the first occurrence of the hotkey character in the label string

### ssh-helpers.ps1

- `Write-Out`:8 `STYLE FORMAT [ARGS...]` — 2-space indented, color-coded line to Console. Styles: `ok` (green), `warn` (yellow), `error` (red), `info` (cyan), `dim` (gray), `heading` (bright-cyan), `plain` (bright-white)
- `Write-OutItem`:33 `FORMAT [ARGS...]` — green `+` prefix, plain text
- `Show-OpBanner`:45 `Pairs [StartRow]` — stream mode (default, `StartRow -lt 0`): prints to Console. Buffer mode (`StartRow >= 0`): writes positioned ANSI into `$script:_OpBannerBuf` for the caller to include in a frame. Always sets `$script:_OpBannerRows`. Unlike bash, no `_SFL_BANNER_ROWS` offset needed — PS `Select-FromList` uses `CursorTop + 3` for dynamic positioning.
- `Write-SSHFence`:137 / `Write-SSHFenceClose`:157 — decorative dim rule around SSH session output; purely visual, no functional effect
- `Invoke-RemotePrompt`:174 — calls `Read-RemoteHostAddress` then `Read-RemoteUser`; sets `$script:_RemoteHost`, `$script:_RemoteUser`, `$script:_RemoteAlias`. `_LastSelectedAlias` is set inside `Read-RemoteHostAddress` directly (no subshell-loss risk unlike bash). Always use this rather than calling the readers separately if you need the alias.
- `Write-IdentityFiles`:188 — prints `IdentityFile` entries for a host (informational dim output)
- `Ensure-SSHDir`:199 — `New-Item -ItemType Directory` if `.ssh` absent
- `Write-KeyPair`:207 — `CopyMode=$true`: `Copy-Item` from file paths; `CopyMode=$false`: `WriteAllText` with public key normalized to exactly one trailing newline (strips then appends). Returns `$true` on success, `$false` if user aborts the overwrite prompt.

### ssh-config.ps1

- `Get-AvailableSSHKeys`:9 — lists private key filenames (no `.pub`, no known housekeeping files) from `~/.ssh`; sorted
- `Get-HostsUsingKey`:19 — returns hosts whose config block has an `IdentityFile` matching `$KeyName` by filename; returns `[pscustomobject]@{Alias; HostName; User}` array
- `Get-ConfiguredSSHHosts`:34 — parses all `Host` blocks; skips `Host *`; returns `[pscustomobject]@{Alias; HostName; User}` array
- `Get-IdentityFilesForHost`:51 — tries alias match first, falls back to HostName value match; returns raw path strings (does NOT expand `~` or `$HOME`, unlike `Get-IdentityFileFromHostConfigEntry`)
- `Get-IdentityFileFromHostConfigEntry`:73 — expands `$HOME` → `$env:USERPROFILE`; other getters return raw strings
- `Find-ConfigFileOnHost`:88 — returns config path if it exists, prints warning and returns `$false` if not
- `Find-SSHKeyInHostConfig`:98 — prints whether `$KeyName` is present in host block; without `-ReturnResult` side-effects only; with `-ReturnResult` returns `$true`/`$false` silently
- `Find-PrivateKeyInHost`:126 / `Find-PublicKeyInHost`:139 — without `-ReturnResult`: silent (no output); with `-ReturnResult`: returns `$true`/`$false` without printing. Use `-ReturnResult` when you need the boolean and want no side-effect output.
- `Get-IPAddressFromHostConfigEntry`:152 / `Get-RemoteUserFromConfigEntry`:180 — extract `HostName` / `User` field from a named Host block; print warning and return `$null` if block or field absent
- `Get-AliasForHostIP`:168 — reverse-lookup: given IP, returns first matching Host alias; returns `$null` if not found; used by `Invoke-RemotePrompt` to recover alias after manual IP entry

### prompts.ps1

- `Read-RemoteUser`:7 / `Read-RemoteHostName`:14 — thin wrappers around `Read-HostWithDefault` / `Select-FromList`; fall back to `Read-ColoredInput` on Esc
- `Read-RemoteHostAddress`:34 — shows configured-host combo-box; on selection sets `$script:_LastSelectedAlias` and returns the `HostName` value; on manual entry clears `_LastSelectedAlias` and returns typed text; subnet shorthand: 1–3 digit input → `"$SubnetPrefix.$digit"`
- `Read-SSHKeyName`:75 / `Read-SSHKeyComment`:86 — key picker (combo-box → free text) and comment input; `Read-SSHKeyName` recurses via `Resolve-NullToAction` until non-empty
- `Read-ColoredInput`:92 — uses `Read-Host` internally; no Esc cancel, no Ctrl+W; simpler than bash counterpart; suitable for paths and free-text where cancel is not needed
- `Read-HostWithDefault`:102 — raw `ReadKey` loop with pre-filled buffer; Backspace edits, Enter confirms, Esc throws `[System.OperationCanceledException]`
- `Resolve-NullToDefault`:133 / `Resolve-NullToAction`:142 / `Test-ValueIsNull`:184 — null/empty guards; `Resolve-NullToAction` re-invokes a callback scriptblock when value is blank (used for required-field retry loops)
- `Confirm-UserChoice`:157 `Message Action DefaultAnswer` — prompts with `[Y/n]`/`[y/N]`/`[y/n]` based on `$DefaultAnswer`; recurses on invalid input; calls `$Action` scriptblock on yes
- `Get-PublicKeyInHost`:190 — reads `.pub` file content; prints it to screen and returns raw string; callers must handle `$null` when key not found
- `Show-Comment`:203 — `Write-Host -NoNewline` wrapper; used for inline label output before a prompt

### ssh-ops.ps1

All status/feedback output uses `Write-Out`/`Write-OutItem` — no raw `[Console]::Write` escape codes.

- `Add-SSHKeyInHost`:9 `KeyName Comment` — prompts passphrase via `Read-Host -AsSecureString` (masked); runs `ssh-keygen -t ed25519` via `Invoke-Expression`; key name and comment must not contain shell-special characters
- `Add-SSHKeyToHostConfig`:40 `KeyName RemoteHostName RemoteHostAddress RemoteUser` — if block exists: inserts `IdentityFile` after the last existing one (or after the `Host` line if none); skips if already present. If block absent: appends a new block at EOF.
- `Resolve-SSHTarget`:89 `RemoteHostAddress RemoteUser` — returns `user@alias` if a config block exists (by alias or HostName match), so SSH applies the full block (including `ServerAliveInterval`, `ForwardAgent`, etc.); falls back to `user@IP`
- `Install-SSHKeyOnRemote`:117 `KeyName` — copies public key to remote `authorized_keys`, then prompts for alias and calls `Add-SSHKeyToHostConfig`
- `Register-RemoteHostConfig`:161 — connects to a not-yet-configured host, reads `authorized_keys`, matches against local `.pub` files, creates a config block
- `Deploy-SSHKeyToRemote`:219 `KeyName` — generates if missing (`Add-SSHKeyInHost`), then installs (`Install-SSHKeyOnRemote`)
- `Test-SSHConnection`:234 `RemoteUser RemoteHost [IdentityFile]` — TCP probe first (3 s, port 22); with `$IdentityFile` uses `-F NUL -i key -o IdentitiesOnly=yes -o PreferredAuthentications=publickey` to bypass config and isolate the key; **no `-o BatchMode=yes`** so passphrase prompts work; without identity uses `Resolve-SSHTarget`
- `Remove-IdentityFileFromConfigBlock`:291 `KeyName HostAlias` — removes all `IdentityFile` lines for `$KeyName` from the named Host block via regex replace
- `Remove-SSHKeyFromRemote`:315 `RemoteUser RemoteHost KeyName` — builds a remote `awk` command to filter `authorized_keys` in-place; offers to delete local key pair afterwards
- `Deploy-PromotedKey`:355 — key rotation: prompts old key + remote + new key; deploys new, then optionally removes old
- `Add-KeyToHosts`:375 `KeyName` — multi-select configured hosts via `Select-MultiFromList`; appends `IdentityFile` to each chosen block via `Add-SSHKeyToHostConfig`
- `Import-ExternalSSHKey`:410 — three modes: local path (`Copy-Item`), SCP from remote, or paste; all paths end with `Add-KeyToHosts`
- `Remove-IdentityFileFromConfigEntry`:515 `KeyName RemoteHostName` — similar to `Remove-IdentityFileFromConfigBlock` but matches by hostname; splits config on newlines rather than full regex replace
- `Invoke-SSHWithKeyThenPassword`:548 — key-first with `BatchMode=yes`; falls back to password prompt on `Permission denied`; not used by `Test-SSHConnection` (separate code paths)

### config-display.ps1

- `Remove-HostFromSSHConfig`:6 — shows block preview before confirming; writes BOM-free UTF-8 via `File::WriteAllText`
- `Show-SSHConfigFile`:56 — full TUI pager with syntax colouring; uses buffer-mode `Show-OpBanner` at row 5; detects resize; Q exits
- `Edit-SSHConfigFile`:145 — respects `$env:EDITOR`; falls back through `code → nvim → vim → nano → notepad.exe`
- `Show-SSHKeyInventory`:172 — interactive table; Up/Dn navigates, Enter drills into `_ViewSSHKey`; uses buffer-mode `Show-OpBanner`; detects resize
- `_ViewSSHKey`:348 — submenu (public key / private key / back); shows red warning bar before displaying private key; Esc exits without viewing
- `_DisplayKeyFile`:390 — full-screen pager for raw key file content; Esc or Q closes

### menu.ps1

- `Invoke-MenuChoice`:13 — 20-line pure dispatcher; each case calls a `_Menu*` handler
- `_MenuGenerateAndInstall`:39 — prompts key name, generates if missing, deploys to remote (`Deploy-SSHKeyToRemote`)
- `_MenuInstallKey`:45 — same but requires key to already exist locally; aborts with message if not found
- `_MenuTestConnection`:55 — picks key from host config or all local keys; supports "Test ALL" multi-key sweep
- `_MenuDeleteRemoteKey`:86 — fetches remote `authorized_keys`, cross-matches local `.pub` files, removes selected; offers to strip IdentityFile from config and delete local key pair
- `_MenuPromoteKey`:159 — delegates to `Deploy-PromotedKey` (installs new key, removes old in one operation)
- `_MenuGenerateKey`:164 — prompts key name + comment, generates ED25519 pair locally without deploying
- `_MenuAppendKeyToConfig`:176 — verifies key is accepted by remote via SSH test, then adds IdentityFile to host config block
- `_MenuDeleteLocalKey`:201 — cross-references key against configured hosts, optionally removes from remote(s), then deletes local key files
- `_MenuRemoveKeyFromConfig`:247 — picks host then IdentityFile entry, removes that line from the config block
- `_MenuShowBestPractices`:273 — prints the 4-rule key-naming guide (LAN shared vs WAN individual); no interactive input
- `_MenuConfDefaults`:283 — inline TUI for editing DEFAULT_* globals; shows 4 copy-paste launch commands; returns `$true` to skip `Wait-UserAcknowledge`
- `_MenuRemoveHost`:381 — delegates to `Remove-HostFromSSHConfig`
- `_MenuViewConfig`:385 — calls `Show-SSHConfigFile`; returns `$true` to skip `Wait-UserAcknowledge`
- `_MenuEditConfig`:390 — calls `Edit-SSHConfigFile`; returns `$true` to skip `Wait-UserAcknowledge`
- `_MenuListKeys`:171 — calls `Show-SSHKeyInventory`; returns `$true` to skip `Wait-UserAcknowledge`
- `_MenuListAuthorizedKeys`:395 — SSHes to target, fetches `authorized_keys`, displays numbered list
- `_MenuAddConfigBlock`:422 — delegates to `Register-RemoteHostConfig` (reads remote auth_keys, creates host config entry)
- `_MenuImportKey`:427 — delegates to `Import-ExternalSSHKey` (local path / SCP / paste)

### menu-renderer.ps1

- `Show-MainMenu`:6 — scrolling viewport, differential rendering, hotkey support, resize detection. Alternate screen buffer (`\e[?1049h/l`). Calls `_InvokeMenuAction` for all selections.
- `_InvokeMenuAction`:221 — draws op title box, calls `Invoke-MenuChoice`, handles `Wait-UserAcknowledge`

## PS-specific implementation notes

- **`$script:` scope is required for all globals.** Module-level variables (`_RemoteHost`, `_RemoteUser`, `_RemoteAlias`, `_LastSelectedAlias`, `_OpBannerBuf`, `_OpBannerRows`) must use `$script:` prefix inside functions. Without it, reads see `$null` and writes create a function-local shadow — the script-level value is never updated.
- **`Select-FromList` returns directly; no side-effect global.** Unlike bash (`_SELECT_RESULT`), PS `Select-FromList` returns the chosen string. Always capture: `$result = Select-FromList ...`. Capturing with `$()` works fine — there's no `/dev/tty` separation needed.
- **Esc throws `[System.OperationCanceledException]`.** Both `Select-FromList`, `Select-MultiFromList`, and `Read-HostWithDefault` throw on Esc. Callers either `catch [System.OperationCanceledException]` to handle locally, or let it propagate to `_InvokeMenuAction`'s outer catch which swallows it. Never use a bare `catch {}` that hides all exceptions.
- **`-F NUL` not `-F /dev/null`.** Windows null device is `NUL`. `Test-SSHConnection` uses `-F NUL` to bypass `~/.ssh/config` when testing a specific key. Bash uses `-F /dev/null`.
- **No `-o BatchMode=yes` in key tests.** Same reason as bash: it blocks passphrase prompts. `Test-SSHConnection` uses `-o PreferredAuthentications=publickey` to restrict to key auth without silencing prompts. `Invoke-SSHWithKeyThenPassword` is the only place that uses `BatchMode=yes` — intentionally, for its key-first probe.
- **`return $true` propagation for skip-wait.** Handlers that run their own full-screen TUI (pagers, conf editor) return `$true`. `Invoke-MenuChoice` uses `return _MenuXxx` so the handler's return value flows through. `_InvokeMenuAction` checks `$skipWait = Invoke-MenuChoice ...` and skips `Wait-UserAcknowledge` when truthy.
- **`[Console]::Write` vs `Write-Host` vs `Write-Out`.** TUI frames (full-screen renders, ANSI positioning) use `[Console]::Write` — it bypasses PowerShell's output pipeline. `Write-Out` uses `[Console]::WriteLine` for 2-space indented operation output. `Write-Host` is used only in legacy or simple output where pipeline capture doesn't matter.
- **`Set-Content -Encoding UTF8` writes a BOM on PS 5.x.** `Add-SSHKeyToHostConfig` and `Remove-IdentityFileFromConfigEntry` use `Set-Content` — generally acceptable for SSH config. For key files and BOM-sensitive paths use `[System.IO.File]::WriteAllText($path, $content, [System.Text.Encoding]::UTF8)` (BOM-free), as `Write-KeyPair` and `Remove-HostFromSSHConfig` do.
- **`Add-SSHKeyInHost` uses `Invoke-Expression`** (in `ssh-ops.ps1`). Built as a string to handle the empty-passphrase `-N ''` flag cleanly. Key name and comment must not contain shell-special characters (`"`, `` ` ``, `$`).
- **`_LastSelectedAlias` is set by `Read-RemoteHostAddress`, cleared on manual entry.** Unlike bash (subshell-loss risk), the PS problem is simply that manual IP entry clears the alias. `Invoke-RemotePrompt` reads `$script:_LastSelectedAlias` after `Read-RemoteHostAddress` returns — always use `Invoke-RemotePrompt` rather than calling `Read-RemoteHostAddress` directly if you need the alias.

## Bash vs PowerShell parity

When modifying behavior, changes typically need to be mirrored in the counterpart lib files. Bash uses `stty`/`read` for terminal I/O; PowerShell uses `Host.UI.RawUI.ReadKey()` and `[Console]::Write()`. Config parsing in Bash uses `perl`/`awk`/`sed`; PowerShell uses `[regex]` class methods.
