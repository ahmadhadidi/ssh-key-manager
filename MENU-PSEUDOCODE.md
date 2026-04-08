# Menu Item Pseudo-Code Reference

This file documents what each menu option does, step by step. Used as a reference for maintaining consistent behavior across both the Bash and PowerShell implementations.

---

## Remote Section

### 1 · G — Generate & Install SSH Key on A Remote Machine

```
prompt: select or name SSH key
if key does not exist locally:
    prompt: key comment (default: keyname + DEFAULT_COMMENT_SUFFIX)
    prompt: passphrase (silent input, empty = passwordless)
    run: ssh-keygen -t ed25519 -f ~/.ssh/<keyname> -C <comment> -N <passphrase>
    set permissions: chmod 600 on private key
→ [then continues as Install below]

prompt: select remote host from ~/.ssh/config list OR enter IP manually
    if short number entered (e.g. "10"): expand to DEFAULT_SUBNET.10
prompt: remote username (default: DEFAULT_USER)
resolve: if host has a config alias, use alias as SSH target
if DEFAULT_PASSWORD set and sshpass available:
    pipe pubkey to: sshpass ssh <target> "mkdir -p .ssh && cat >> .ssh/authorized_keys && hostname"
else:
    pipe pubkey to: ssh <target> "mkdir -p .ssh && cat >> .ssh/authorized_keys && hostname"
    (SSH may prompt for password interactively)
prompt: alias to use in ~/.ssh/config (default: remote hostname returned by ssh)
write to ~/.ssh/config: Host <alias> / HostName <ip> / User <user> / IdentityFile ~/.ssh/<keyname>
```

---

### 15 · I — Install SSH Key on A Remote Machine

```
prompt: select or name SSH key
check: key must already exist locally (private key file present)
if key not found: show error, abort
→ same as the Install step in option 1 above (from "prompt: select remote host" onward)
```

---

### 2 · T — Test SSH Connection

```
prompt: select remote host or enter IP manually
prompt: remote username
if host alias was selected and has IdentityFile entries in config:
    if multiple keys: prompt to pick one OR "Test ALL"
    if single key: use it automatically
run: TCP connect check on port 22 (timeout 3s)
if TCP fails: show "not accepting SSH on port 22"
run: ssh [-i <key>] -o BatchMode=yes -o ConnectTimeout=6 <target> "echo SSH Connection Successful"
parse result:
    "Name or service not known" → DNS error message
    "Permission denied"         → key rejected / passphrase message
    otherwise                   → success message
```

---

### 3 · D — Delete SSH Key From A Remote Machine

```
prompt: select remote host or enter IP manually
prompt: remote username
ssh <target> "cat ~/.ssh/authorized_keys"
if connection fails: show error, abort
if no authorized_keys: show info, abort
match each local ~/.ssh/*.pub against remote authorized_keys lines
if no matches: show "no local keys found on remote"
prompt: select which matched key to remove
ssh <target>: create temp file with pubkey, use awk to filter it out of authorized_keys, replace file
if removal succeeds:
    prompt (y/N): remove IdentityFile entry from config block for this host?
    prompt (y/N): delete local key files (~/.ssh/<key> and ~/.ssh/<key>.pub)?
```

---

### 4 · P — Promote Key on A Remote Machine

```
prompt: which key to DEMOTE (remove from remote)?
prompt: from which remote host?
prompt: replace with which NEW key?
→ run full Generate & Install (option 1) for the new key
prompt (y/N): remove the demoted key from remote?
    if yes: run remove_ssh_key_from_remote for old key
```

---

### 16 · Z — List Authorized Keys on Remote Host

```
prompt: select remote host or enter IP manually
prompt: remote username
ssh <target> "cat ~/.ssh/authorized_keys"
if connection fails: show error
if empty: show "no authorized_keys found"
else: print numbered list of each key line
```

---

### 17 · N — Add Config Block for Existing Remote Key

```
prompt: enter IP or hostname of remote (not in config yet)
prompt: remote username
ssh <target> "cat ~/.ssh/authorized_keys"
if connection fails: abort
match each local ~/.ssh/*.pub against remote authorized_keys
if no matches: show "no matching keys found, install one first"
if matches found: show list
if multiple matches: prompt to select which key to register
prompt: alias for this host in ~/.ssh/config (default: IP address)
write to ~/.ssh/config: Host <alias> / HostName <ip> / User <user> / IdentityFile ~/.ssh/<keyname>
```

---

## Local Section

### 5 · W — Generate SSH Key (Without Installation)

```
prompt: select existing key name OR type new name
prompt: key comment (default: keyname + DEFAULT_COMMENT_SUFFIX)
prompt: passphrase (silent, empty = passwordless)
run: ssh-keygen -t ed25519 -f ~/.ssh/<keyname> -C <comment> -N <passphrase>
chmod 600 ~/.ssh/<keyname>
show: key path generated
```

---

### 6 · L — List SSH Keys

```
scan ~/.ssh/ for private key files (exclude: config, known_hosts, authorized_keys, *.pub)
scan ~/.ssh/*.pub for public key files
build union set of all key names
for each key name:
    check if private file exists (Y/N)
    check if public file exists (Y/N)
    scan ~/.ssh/config: find all Host blocks that reference this key as IdentityFile
    build "used by" list of host aliases
render as ASCII table: # | Key | Pub | Prv | Usage
paginate with show_paged if output exceeds screen
```

---

### 7 · A — Append SSH Key to Hostname in Host Config

```
prompt: select or name SSH key
prompt: select or enter host alias (for config block name)
prompt: select remote host or enter IP (for HostName)
prompt: remote username
attempt: ssh -i ~/.ssh/<key> -o BatchMode=yes <user>@<ip> "echo ok"
if "ok" returned: confirm key works on that host
if verification fails: prompt (y/N) to add to config anyway
write to ~/.ssh/config:
    if Host block exists: insert IdentityFile line after existing IdentityFile entries
    if Host block absent: create new block with HostName, User, IdentityFile
```

---

### 8 · X — Delete an SSH Key Locally

```
prompt: select or name SSH key to delete
scan ~/.ssh/config for Host blocks that reference this key as IdentityFile
if hosts found: prompt to select one, ALL, or Esc to skip remote removal
for each selected host: run remove_ssh_key_from_remote (same as option 3 remote removal)
delete local files: ~/.ssh/<keyname> and ~/.ssh/<keyname>.pub
show confirmation of deleted files
```

---

### 9 · R — Remove an SSH Key From Config

```
list all Host aliases from ~/.ssh/config
prompt: select which host
list all IdentityFile entries in that Host block
prompt: select which key to remove
remove only that IdentityFile line from the Host block (block itself stays)
```

---

## Config File Section

### 12 · H — Remove Host from SSH Config

```
list all Host aliases from ~/.ssh/config
prompt: select or type host alias to remove
display: full Host block that will be deleted
prompt (y/N): confirm removal
delete the entire Host block from ~/.ssh/config using perl/python3
clean up trailing blank lines
```

---

### 13 · V — View SSH Config

```
read ~/.ssh/config line by line
apply syntax highlighting per line type:
    Host <alias>          → bold cyan "Host" + white alias
    IdentityFile <path>   → yellow key + green value
    HostName/User/Port    → yellow key + grey value
    # comments           → grey
    other directives      → orange key + grey value
enter interactive pager (full-screen):
    Up/Dn / PgUp/PgDn / Home/End to scroll
    Q to close
```

---

### 14 · E — Edit SSH Config

```
detect editor: $VISUAL → $EDITOR → nvim → vim → nano → vi
launch: <editor> ~/.ssh/config
wait for editor to exit
show: "Done" or error message
```

---

## Other

### 10 · F1 — Help: Best Practices

```
display static text explaining recommended key naming conventions:
    shared key for LAN demos / dev
    shared key for promoted prod stack
    individual key per service for WAN access
```

---

### 11 · F10 — Conf: Global Defaults

```
enter inline TUI editor (full-screen):
    Up/Dn to navigate 4 fields: DEFAULT_USER, DEFAULT_SUBNET_PREFIX, DEFAULT_COMMENT_SUFFIX, DEFAULT_PASSWORD
    Enter to edit selected field (inline text input)
    Q to save and return
changes are in-memory only for current session
to persist: re-run script with --user / --subnet / --comment-suffix / --password flags
```

---

### Q — Exit

```
run _menu_cleanup:
    restore cursor visibility
    exit alternate screen buffer
    restore saved terminal stty state (or stty sane as fallback)
exit 0
```
