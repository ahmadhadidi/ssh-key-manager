# 🌊 HDD SSH Keys
A TUI SSH key manager — available for both **Windows (PowerShell)** and **Linux (Bash)**.

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

& $sb -DefaultUserName "username_of_target_machine" -DefaultSubnetPrefix "192.168.0" -DefaultCommentSuffix "-[my-machine]"
```

### Run after git clone

```powershell
git clone https://github.com/ahmadhadidi/ssh-key-manager.git
cd ssh-key-manager

& ./generate_key_test.ps1 -DefaultUserName username_of_target_machine -DefaultSubnetPrefix 192.168.0 -DefaultCommentSuffix "-[my-machine]"
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