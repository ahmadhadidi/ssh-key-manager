# 🌊 HDD SSH Keys

A terminal-based SSH key manager with a full interactive TUI — available for both **Windows (PowerShell)** and **Linux (Bash)**.

Managing SSH keys across multiple machines is repetitive and error-prone: generating keys, copying them to remotes, keeping `~/.ssh/config` in sync, cleaning up old keys, and rotating credentials all involve the same handful of commands done over and over. This script wraps all of that into a single interactive menu so you never have to remember the incantations.

---

## What it does

### Remote operations
| Hotkey | Action |
|---|---|
| `G` | **Generate & Install** — create a new ED25519 key pair and push it to a remote machine in one step. Registers the host in `~/.ssh/config` automatically. |
| `I` | **Install only** — push an already-existing local key to a remote (skips generation). |
| `T` | **Test connection** — TCP pre-check on port 22, then a live SSH handshake. Shows whether the key is accepted, password is needed, or the host is unreachable. |
| `D` | **Delete from remote** — fetches the remote `authorized_keys`, matches it against your local `.pub` files, lets you pick which key to revoke, removes it via `awk` on the remote, and optionally cleans up the local key and config entry. |
| `P` | **Promote key** — swap one key for another on a remote: deploy the new key, then revoke the old one. |
| `Z` | **List authorized keys** — print all keys currently installed on a remote host. |
| `N` | **Add config block** — connect to a machine that already has your key installed and create the matching `~/.ssh/config` entry without re-installing anything. |

### Local operations
| Hotkey | Action |
|---|---|
| `W` | **Generate key** — create a new ED25519 key pair locally (with optional passphrase). |
| `L` | **List keys** — ASCII table showing every key in `~/.ssh/`: whether the private and public halves exist, and which config hosts reference it. |
| `A` | **Append to config** — add an `IdentityFile` line to an existing host block (or create a new block) after verifying the key works on the remote. |
| `X` | **Delete locally** — remove key files from disk, optionally after revoking them from any remote hosts that reference them. |
| `R` | **Remove from config** — strip an `IdentityFile` line from a specific host block without touching the key files. |

### Config file operations
| Hotkey | Action |
|---|---|
| `H` | **Remove host** — preview and delete an entire `Host` block from `~/.ssh/config`. |
| `V` | **View config** — scrollable pager with syntax highlighting (hosts, identity files, directives all colour-coded). |
| `E` | **Edit config** — open `~/.ssh/config` in `$VISUAL` / `$EDITOR` / `nvim` / `vim` / `nano`. |

### Extras
- **Short IP notation** — type `10` instead of `192.168.0.10`; the subnet prefix is filled in automatically.
- **Config-aware host picker** — every prompt that asks for a remote host shows a filterable list of your configured aliases instead of a blank field.
- **Session defaults** (`F10`) — change username, subnet prefix, comment suffix, and password for the current session without restarting.
- **Best practices reference** (`F1`) — quick guide on shared vs. per-host key strategy.

---

## Linux (Bash)

### Run directly from the cloud

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ahmadhadidi/ssh-key-manager/refs/heads/main/ssh-key-manager.sh) \
  --user username_of_target_machine \
  --subnet 192.168.0 \
  --comment-suffix "-[my-machine]"
```

### Run after git clone

```bash
git clone https://github.com/ahmadhadidi/ssh-key-manager.git
cd ssh-key-manager

bash ssh-key-manager.sh \
  --user username_of_target_machine \
  --subnet 192.168.0 \
  --comment-suffix "-[my-machine]"
```

### Options

| Option | Default | Description |
|---|---|---|
| `--user NAME` | `default_non_root_username` | Default remote username |
| `--subnet PREFIX` | `192.168.0` | Subnet prefix (type `10` → resolves to `192.168.0.10`) |
| `--comment-suffix STR` | `-[my-machine]` | Appended to key comments |
| `--password PASS` | *(empty)* | Default SSH password (used with `sshpass` if installed) |

---

## Windows (PowerShell)

### Run directly from the cloud

```powershell
$u  = "https://raw.githubusercontent.com/ahmadhadidi/ssh-key-manager/refs/heads/main/generate_key_test.ps1"
$sb = [scriptblock]::Create((irm $u))

& $sb -DefaultUserName "username_of_target_machine" -DefaultSubnetPrefix "192.168.0" -DefaultCommentSuffix "-[my-machine]" -DefaultPassword "abc123"
```

### Run after git clone

```powershell
git clone https://github.com/ahmadhadidi/ssh-key-manager.git
cd ssh-key-manager

& ./generate_key_test.ps1 -DefaultUserName username_of_target_machine -DefaultSubnetPrefix 192.168.0 -DefaultCommentSuffix "-[my-machine]" -DefaultPassword "abc123"
```

---

## Navigation

| Key | Action |
|---|---|
| `↑` / `↓` | Move selection |
| `Home` / `End` | Jump to first / last item |
| `Enter` | Select |
| Hotkey letter (e.g. `G`, `T`) | Activate item directly |
| `F1` | Help: Best Practices |
| `F10` | Edit session defaults |
| `Q` | Quit |

---

# Todo
- [ ] Finish Function #6
- [ ] Ability to list and `cat` the public keys
- [ ] Ability to list and `cat` the private keys
- [ ] Implement Delete IdentityFile from a certain config block
- [ ] Reduce the amount of prompts needed by querying the Config file more
- [ ] Use the SSH key if it's already installed rather than logging in with the user.
- [ ] Reduce the amount of prompts by SSHing via the available Config file if it already exists.
