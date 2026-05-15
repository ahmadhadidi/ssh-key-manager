# PowerShell Implementation

See root `CLAUDE.md` for project overview and running instructions.

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
