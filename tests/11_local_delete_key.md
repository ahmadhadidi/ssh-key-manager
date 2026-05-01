# Test: Local — Delete Local Key (x)

**Python counterpart:** `11_local_delete_key.py`  
**Menu hotkey:** `x` (lowercase)  
**bash requirement:** `/proj/bash32/bin/bash` — bash 3.2.57

## What this tests

`_menu_delete_local_key`: cross-references the selected key against all
configured hosts (offers to remove it from remote `authorized_keys` first),
then deletes the local private and public key files after confirmation.

## Prerequisites

- Terminal ≥ 40 rows × 100 columns.
- LXC at `192.168.0.213` available for the remote-removal branch (TC-2).

## Launch

```
/proj/bash32/bin/bash hddssh.sh --user testuser --subnet 192.168.0 --password testpass
```

---

## TC-1: Delete a local key not referenced in any host config

**Setup:**
```bash
ssh-keygen -t ed25519 -f ~/.ssh/del-local -N "" -C "del-local"
# Do NOT add it to any Host block in ~/.ssh/config
```

**Steps:**
1. Press **`x`** (lowercase).
2. Verify "Delete (Local)" header.
3. In key selector, type `del-local`, **Enter**.
4. TUI shows no configured hosts reference this key.
5. At "Delete local key files?" confirm `y` **Enter**.
6. Observe "deleted" confirmation.
7. Acknowledge with any key.

**Expected:** `~/.ssh/del-local` and `~/.ssh/del-local.pub` no longer exist.

---

## TC-2: Delete a key that is referenced in a host config block

**Setup:**
```bash
ssh-keygen -t ed25519 -f ~/.ssh/del-cfg -N "" -C "del-cfg"
# Add IdentityFile ~/.ssh/del-cfg to hddssh-test block in ~/.ssh/config
ssh-copy-id -i ~/.ssh/del-cfg.pub testuser@192.168.0.213
```

**Steps:**
1. Press **`x`**.
2. Select `del-cfg`, **Enter**.
3. TUI lists `hddssh-test` as a host referencing this key.
4. At "Remove from remote?" confirm `y` **Enter**.
5. SSH password prompt if needed: `testpass`, **Enter**.
6. At "Remove IdentityFile from config block?" confirm `y` **Enter**.
7. At "Delete local key files?" confirm `y` **Enter**.
8. Acknowledge.

**Expected:** Key removed from LXC `authorized_keys`, `IdentityFile` line
removed from `hddssh-test` block, local files deleted.

---

## TC-3: Cancel deletion at confirmation

**Setup:** `del-cancel` key exists locally.

**Steps:**
1. Press **`x`**.
2. Select `del-cancel`, **Enter**.
3. At "Delete local key files?" answer `n` **Enter**.

**Expected:** No files deleted. Key still present in `~/.ssh/`.

**Cleanup:** `rm -f ~/.ssh/del-cancel ~/.ssh/del-cancel.pub`

---

## TC-4: ESC at key selector

**Steps:**
1. Press **`x`**.
2. Press **ESC** in the key selector.

**Expected:** Returns to main menu. No files deleted. Wait 150 ms after ESC.
