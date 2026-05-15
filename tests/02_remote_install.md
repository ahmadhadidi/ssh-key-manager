# Test: Remote — Install SSH Key (I)

**Python counterpart:** `02_remote_install.py`  
**Menu hotkey:** `I`  
**bash requirement:** `/usr/bin/bash` — bash 3.2 on macOS

## What this tests

`_menu_install_key` → `install_ssh_key_on_remote`: installs an **already-existing**
local key onto a remote host. Aborts with a message if the key does not exist
locally — does not generate.

## Prerequisites

- LXC at `192.168.0.213`, user `testuser`, password `testpass`.
- `~/.ssh/config` has `Host sshhdd-test` → `192.168.0.213`.
- Terminal ≥ 40 rows × 100 columns.

## Launch

```
/usr/bin/bash sshhdd.sh --user testuser --subnet 192.168.0 --password testpass
```

---

## TC-1: Install an existing key

**Setup:**
```bash
ssh-keygen -t ed25519 -f ~/.ssh/install-test -N "" -C "install-test"
```

**Steps:**
1. Press **`I`**.
2. Verify "Install SSH Key" header.
3. In key selector, type `install-test`, **Enter**.
4. Select host `sshhdd-test`, **Enter**.
5. Accept username `testuser`, **Enter**.
6. If password prompt appears, enter `testpass`, **Enter**.
7. Observe "installed successfully".
8. Decline IdentityFile (`n` **Enter**).
9. Acknowledge with any key.

**Expected:** `install-test.pub` content appears in LXC `authorized_keys`.

**Cleanup:**
```bash
pub=$(cat ~/.ssh/install-test.pub)
ssh testuser@192.168.0.213 "grep -vF '$pub' ~/.ssh/authorized_keys > /tmp/ak && mv /tmp/ak ~/.ssh/authorized_keys"
rm -f ~/.ssh/install-test ~/.ssh/install-test.pub
```

---

## TC-2: Key does not exist locally — abort

**Setup:** Confirm `~/.ssh/nonexistent-key` does not exist.

**Steps:**
1. Press **`I`**.
2. In key selector, type `nonexistent-key`, **Enter**.

**Expected:** TUI shows an error message ("Key not found" or similar) and
returns to the main menu. No SSH connection is attempted.

---

## TC-3: ESC in key selector cancels

**Steps:**
1. Press **`I`**.
2. In key selector, type a partial name.
3. Press **ESC**.

**Expected:** Returns to main menu. No install attempted.

---

## TC-4: Navigate to I via arrow key

**Steps:**
1. From main menu, press **↓** once.
2. The second item (Install SSH Key) should be highlighted.
3. Press **Enter**.
4. Verify "Install SSH Key" header.
5. Press **ESC** → main menu.

**Expected:** Arrow + Enter reaches Install SSH Key correctly.
