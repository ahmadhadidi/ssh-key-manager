# 🌊 HDD SSH Keys

A terminal-based SSH key manager with a full interactive TUI — available for both **Windows (PowerShell)** and **Linux (Bash)**.

Managing SSH keys across multiple machines is repetitive and error-prone: generating keys, copying them to remotes, keeping `~/.ssh/config` in sync, cleaning up old keys, and rotating credentials all involve the same handful of commands done over and over. This script wraps all of that into a single interactive menu so you never have to remember the incantations.

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
irm "https://raw.githubusercontent.com/.../generate_key_test.ps1" | iex

& ([scriptblock]::Create((irm "https://raw.githubusercontent.com/ahmadhadidi/ssh-key-manager/refs/heads/main/generate_key_test.ps1"))) -DefaultUserName "myuser" -DefaultSubnetPrefix "192.168.0" -DefaultPassword "abc123"

```

### Run after git clone

```powershell
git clone https://github.com/ahmadhadidi/ssh-key-manager.git
cd ssh-key-manager

& ./generate_key_test.ps1 -DefaultUserName username_of_target_machine -DefaultSubnetPrefix 192.168.0 -DefaultCommentSuffix "-[my-machine]" -DefaultPassword "abc123"
```

