# Test: Remote — Add Config Block (N)

**Python counterpart:** `07_remote_add_config_block.py`  
**Menu hotkey:** `N`  
**bash requirement:** `/usr/bin/bash` — bash 3.2 on macOS

## What this tests

`_menu_add_config_block` → `register_remote_host_config`: SSHes to a host
that is NOT yet in `~/.ssh/config`, reads its `authorized_keys`, matches
against local `.pub` files, then writes a new `Host` block.

## Prerequisites

- LXC at `192.168.0.213`, user `testuser`, password `testpass`.
- `~/.ssh/config` does NOT yet have a block for the test alias used.
- At least one local key is deployed on the LXC (`register-test` key).
- Terminal ≥ 40 rows × 100 columns.

## Launch

```
/usr/bin/bash hddssh.sh --user testuser --subnet 192.168.0 --password testpass
```

---

## TC-1: Register a new host config block

**Setup:**
```bash
ssh-keygen -t ed25519 -f ~/.ssh/register-test -N "" -C "register-test"
ssh-copy-id -i ~/.ssh/register-test.pub testuser@192.168.0.213
# Ensure ~/.ssh/config has no block for alias "new-host"
```

**Steps:**
1. Press **`N`**.
2. Verify "Add Config Block" header.
3. Enter IP `192.168.0.213` (or subnet shorthand `213`), **Enter**.
4. Enter username `testuser`, **Enter**.
5. If password prompted, enter `testpass`, **Enter**.
6. At alias prompt, type `new-host`, **Enter**.
7. Observe "Host block added" or similar.
8. Acknowledge with any key.

**Expected:** `~/.ssh/config` now contains:
```
Host new-host
    HostName 192.168.0.213
    User testuser
    IdentityFile ~/.ssh/register-test
```

**Cleanup:**
```bash
# Remove the new-host block from ~/.ssh/config manually or via H menu
rm -f ~/.ssh/register-test ~/.ssh/register-test.pub
```

---

## TC-2: Subnet shorthand input

**Steps:**
1. Press **`N`**.
2. At IP input, type `213` (subnet shorthand → `192.168.0.213`).
3. Continue through alias creation.

**Expected:** The TUI expands `213` to the full IP `192.168.0.213` based on
`--subnet 192.168.0`. Config block contains the full IP.

---

## TC-3: ESC cancels at IP prompt

**Steps:**
1. Press **`N`**.
2. Press **ESC** at the host input.

**Expected:** Returns to main menu. `~/.ssh/config` unchanged.
