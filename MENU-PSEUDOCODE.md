# Menu Item Pseudo-Code Reference

This file documents what each menu option does, step by step. It is kept
1:1 with the Bash implementation (`lib/bash/`). Use it as a trace map
when requesting adjustments.

Key constants and helpers referenced below are defined in:
- `lib/bash/tui.sh`      — key reading, ANSI helpers, select_from_list
- `lib/bash/ssh-config.sh` — config parsing, _replace_host_block
- `lib/bash/prompts.sh`  — read_*, get_public_key, find_*
- `lib/bash/ssh-ops.sh`  — key generation, remote operations
- `lib/bash/config-display.sh` — file viewers, show_ssh_key_inventory
- `lib/bash/menu.sh`     — dispatcher (invoke_menu_choice), main loop

---

## Startup flow (`show_main_menu`)

```
save stty state → enter alternate screen (\e[?1049h)
if ~/.ssh/config does not exist:
    show full-screen prompt (_check_config_at_start):
        [Y/Enter] → _do_create_config: mkdir -p ~/.ssh; touch ~/.ssh/config; chmod 600
        [n]       → set _CONFIG_MISSING=1
enter main menu event loop:
    if _CONFIG_MISSING: render red warning bar above hint bar
    F2 key while warning bar visible → _do_create_config → clear warning bar
    (the loop renders, polls _read_key_nb every ~50 ms for resize detection)
```

---

## Remote Section

### 1 · G — Generate & Install SSH Key on A Remote Machine

```
invoke_menu_choice "1"
→ read_ssh_key_name
    if keys exist in ~/.ssh: show select_from_list combo-box
    else / if Esc: read_colored_input for manual name
if key does NOT exist locally:
    read_ssh_key_comment (default: keyname + DEFAULT_COMMENT_SUFFIX)
    read_colored_input for passphrase (silent)
    ssh-keygen -t ed25519 -f ~/.ssh/<keyname> -C <comment> -N <passphrase>
    chmod 600 ~/.ssh/<keyname>
→ install_ssh_key_on_remote:
    get_public_key → cat ~/.ssh/<keyname>.pub (sends to stdout; status to stderr)
    read_remote_host_address:
        show select_from_list of known hosts from ~/.ssh/config
        or: read_colored_input for IP / last-octet shorthand (e.g. "10" → subnet.10)
    read_remote_user (default: DEFAULT_USER)
    resolve_ssh_target: look up alias in ~/.ssh/config; use alias or user@host
    if DEFAULT_PASSWORD set and sshpass available:
        pipe pubkey | sshpass ssh <target> "mkdir -p .ssh && cat >> .ssh/authorized_keys && hostname"
    else:
        pipe pubkey | ssh <target> "mkdir -p .ssh && cat >> .ssh/authorized_keys && hostname"
    read_host_with_default for alias (default: remote hostname from ssh output)
    add_ssh_key_to_host_config:
        if host block exists in config: insert IdentityFile line after existing ones
        else: append new Host block (HostName / User / IdentityFile)
        uses _replace_host_block (perl → python3 fallback)
```

---

### 15 · I — Install SSH Key on A Remote Machine

```
invoke_menu_choice "15"
→ read_ssh_key_name  (same as above)
check: if key does NOT exist locally → error message, abort
→ same as "Install" portion of option 1 (from get_public_key onward)
```

---

### 2 · T — Test SSH Connection

```
invoke_menu_choice "2"
→ read_remote_host_address
→ read_remote_user
if host alias was selected and has IdentityFile entries in config:
    if multiple keys: select_from_list "-- Test ALL" or pick one
    if single key:    use it automatically
→ test_ssh_connection user host [identity]:
    _tcp_check: timeout 3 bash -c "echo >/dev/tcp/$host/22"
    if TCP fails: "not accepting SSH on port 22"
    ssh [-i key] -o BatchMode=yes -o ConnectTimeout=6 <target> "echo SSH Connection Successful"
    parse result:
        "Name or service not known" → DNS error
        "Permission denied"         → key rejected / passphrase required
        otherwise                   → success
```

---

### 3 · D — Delete SSH Key From A Remote Machine

```
invoke_menu_choice "3"
→ read_remote_host_address
→ read_remote_user
resolve_ssh_target
ssh <target> "cat ~/.ssh/authorized_keys 2>/dev/null"
if connection fails: abort
if no authorized_keys: abort
match each local ~/.ssh/*.pub against remote authorized_keys lines
if no matches: show "no local keys found on remote"
select_from_list of matched keys
build remote_cmd:
    TMP=mktemp; printf key > TMP
    awk to filter key out of authorized_keys; mv tmp → authorized_keys; rm TMP
ssh <target> "$remote_cmd"
if removal succeeds:
    if host alias known: confirm_user_choice → remove_identity_file_from_config_block
    confirm_user_choice → delete local private + public key files
```

---

### 4 · P — Promote Key on A Remote Machine

```
invoke_menu_choice "4"
→ deploy_promoted_key:
    read_ssh_key_name (key to demote/remove from remote)
    read_remote_host_name (from which remote host)
    read_ssh_key_name (new key to promote)
    → deploy_ssh_key_to_remote for the new key (option 1 flow)
    get_ip_from_host_config, get_user_from_host_config for the old host
    confirm_user_choice → remove_ssh_key_from_remote for old key
```

---

### 16 · Z — List Authorized Keys on Remote Host

```
invoke_menu_choice "16"
→ read_remote_host_address
→ read_remote_user
resolve_ssh_target
ssh <target> "cat ~/.ssh/authorized_keys 2>/dev/null"
if connection fails: error
if empty: "no authorized_keys found"
else: print numbered list of each key line
```

---

### 17 · N — Add Config Block for Existing Remote Key

```
invoke_menu_choice "17"
→ register_remote_host_config:
    read_colored_input for remote IP / hostname
    read_remote_user
    ssh <target> "cat ~/.ssh/authorized_keys 2>/dev/null"
    if connection fails: abort
    match each local ~/.ssh/*.pub against remote authorized_keys
    if no matches: "no matching keys found, install one first"
    if multiple matches: select_from_list to pick one
    read_host_with_default for alias (default: IP)
    add_ssh_key_to_host_config (same writer as option 1)
```

---

## Local Section

### 5 · W — Generate SSH Key (Without Installation)

```
invoke_menu_choice "5"
→ read_ssh_key_name
→ read_ssh_key_comment (default: keyname + DEFAULT_COMMENT_SUFFIX)
→ add_ssh_key_in_host keyname comment:
    read passphrase (silent; empty = passwordless)
    show summary (key name, comment, passphrase stars)
    mkdir -p ~/.ssh; chmod 700
    ssh-keygen -t ed25519 -f ~/.ssh/<keyname> -C <comment> -N <passphrase>
    chmod 600 ~/.ssh/<keyname>
```

---

### 6 · L — List SSH Keys (Interactive)

```
invoke_menu_choice "6"
→ show_ssh_key_inventory:
    scan ~/.ssh/*.pub → has_pub map
    get_available_ssh_keys → has_priv map
    union → all_keys (sorted)
    scan ~/.ssh/config: build usage_map (key → comma-separated host aliases)
    render interactive table: # | Key | Pub | Prv | Usage
    selected row highlighted in teal
    Up/Dn/PgUp/PgDn/Home/End navigate; Q closes
    Enter on row → _view_ssh_key keyname:
        select_from_list: "Public Key (.pub)" / "Private Key" / "Back"
        "Public Key":
            → _display_key_file ~/.ssh/<keyname>.pub
               scrollable full-screen pager; Q closes
        "Private Key":
            show red warning bar
            [y] confirm → _display_key_file ~/.ssh/<keyname>
               same pager
```

---

### 7 · A — Append SSH Key to Hostname in Host Config

```
invoke_menu_choice "7"
→ read_ssh_key_name
→ read_remote_host_name (host alias for config block)
→ read_remote_host_address (HostName / IP)
→ read_remote_user
attempt: ssh -i ~/.ssh/<key> -o BatchMode=yes <user>@<ip> "echo ok"
if "ok" returned: key already works on that host
else: read_host_with_default "Add to config anyway? (y/N)"
    [n] → abort
add_ssh_key_to_host_config (same as option 1)
```

---

### 8 · X — Delete an SSH Key Locally

```
invoke_menu_choice "8"
→ read_ssh_key_name
get_hosts_using_key → list of hosts that reference this key
if hosts found:
    select_from_list: "-- ALL (N hosts)" or individual alias  (Esc = skip remote)
    for each selected host:
        remove_ssh_key_from_remote user host keyname (option 3 remote removal)
delete local files: ~/.ssh/<keyname> and ~/.ssh/<keyname>.pub
print confirmation
```

---

### 9 · R — Remove an SSH Key From Config

```
invoke_menu_choice "9"
get_configured_ssh_hosts → list of aliases
select_from_list to pick host alias
_get_host_block for that alias
parse IdentityFile lines → list of key names
select_from_list to pick which key to remove
remove_identity_file_from_config_block keyname host_alias:
    grep -vE removes the matching IdentityFile line
    _replace_host_block (perl → python3 fallback) writes the updated block
```

---

### 18 · M — Import SSH Key from Another Machine

```
invoke_menu_choice "18"
→ import_external_ssh_key:
    prompt: "1 Local file path" / "2 Remote machine (SCP)"
    [1] Local path:
        read_colored_input for private key file path
        read_colored_input for public key file path (leave blank → <priv>.pub)
        if dest exists: confirm overwrite
        cp priv → ~/.ssh/<keyname>; chmod 600
        cp pub  → ~/.ssh/<keyname>.pub; chmod 644
        confirm_user_choice → add_ssh_key_to_host_config (optional)
    [2] Remote SCP:
        read_remote_host_address
        read_remote_user
        read_colored_input for remote private key path
        scp <target>:<remote_priv> ~/.ssh/<keyname>; chmod 600
        scp <target>:<remote_priv>.pub ~/.ssh/<keyname>.pub; chmod 644 (optional)
        confirm_user_choice → add_ssh_key_to_host_config (optional)
```

---

## Config File Section

### 12 · H — Remove Host from SSH Config

```
invoke_menu_choice "12"
→ remove_host_from_ssh_config:
    get_configured_ssh_hosts → list
    select_from_list or read_colored_input for host alias
    _get_host_block to retrieve full block text
    display block; read_colored_input "Remove? [y/N]"
    [y] → _replace_host_block old_block ""
    sed cleanup: strip trailing spaces, collapse double blank lines
```

---

### 13 · V — View SSH Config

```
invoke_menu_choice "13"
→ show_ssh_config_file:
    read ~/.ssh/config line by line
    apply syntax highlighting:
        Host <alias>          → bold cyan + white
        IdentityFile <path>   → yellow key + green value
        HostName/User/Port/…  → yellow key + grey value
        # comments            → grey
        other directives      → orange key + grey value
    enter interactive full-screen pager:
        Up/Dn / PgUp/PgDn / Home/End scroll
        Q closes; terminal resize detection on each read cycle
returns 1 to skip wait_user_acknowledge
```

---

### 14 · E — Edit SSH Config

```
invoke_menu_choice "14"
→ edit_ssh_config_file:
    detect editor: $VISUAL → $EDITOR → nano → vi → vim → nvim
    launch: <editor> ~/.ssh/config
    wait for editor to exit
    "Done" or error message
returns 1 to skip wait_user_acknowledge
```

---

## Other

### 10 · F1 — Help: Best Practices

```
invoke_menu_choice "10"
display static text:
    1. LAN demo CTs        → shared key (e.g. demo-lan)
    2. LAN development CTs → shared key (e.g. dev-lan)
    3. Promoted stack CTs  → shared key (e.g. prod-lan)
    4. WAN-accessed CTs    → individual key per service (e.g. sonarr-wan)
```

---

### 11 · F5 — Conf: Global Defaults

```
invoke_menu_choice "11"  (bound to F5 key; F10 was replaced — GNOME Terminal intercepts it)
→ _run_conf_editor:
    enter full-screen inline editor
    4 editable fields: DEFAULT_USER / DEFAULT_SUBNET_PREFIX /
                       DEFAULT_COMMENT_SUFFIX / DEFAULT_PASSWORD
    Up/Dn navigate; Enter edits selected field (inline read -r)
    Q saves and returns
changes are in-memory only for the current session
to persist across sessions: re-run with --user / --subnet /
    --comment-suffix / --password flags
returns 1 to skip wait_user_acknowledge
```

---

### Q — Exit

```
main loop: running=0
_menu_cleanup:
    show cursor (\e[?25h)
    exit alternate screen (\e[?1049l)
    restore saved stty state (or stty sane as fallback)
trap - EXIT INT TERM TSTP  (remove handlers)
exit 0
```

---

## Key Bindings Summary

| Key         | Action                          |
|-------------|---------------------------------|
| Up / Down   | Navigate menu items             |
| Home / End  | Jump to first / last item       |
| Enter       | Select highlighted item         |
| Hotkey      | Jump directly to item (G/I/T/…) |
| F1          | Help: Best Practices            |
| F2          | Create ~/.ssh/config (if missing)|
| F5          | Conf: Global Defaults           |
| Q           | Quit                            |

---

## Implementation Notes

- **select_from_list** writes TUI to `/dev/tty` so it works inside `$(...)` subshells.
- **_read_key / _read_key_nb** now read up to 4 extra bytes after `\x1b` to handle
  1-digit (`\x1b[5~`) and 2-digit (`\x1b[15~`, `\x1b[21~`) F-key sequences.
- **_replace_host_block** centralises the perl/python3 fallback used for in-place
  config block replacement (see `lib/bash/ssh-config.sh`).
- **get_public_key** sends status messages to stderr so the captured stdout value
  contains only the raw key string (no ANSI codes mixed in).
