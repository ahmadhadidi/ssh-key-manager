# Test: Remote — Test SSH Connection (T)

**Python counterpart:** `03_remote_test_connection.py`  
**Menu hotkey:** `T`  
**bash requirement:** `/usr/bin/bash` — bash 3.2 on macOS

## What this tests

`_menu_test_connection` → `test_ssh_connection`: TCP probe on port 22 then
an SSH key-auth attempt. Uses `-F /dev/null -o IdentitiesOnly=yes
-o PreferredAuthentications=publickey` — bypasses `~/.ssh/config` completely
so the test is isolated to the selected key. No `BatchMode=yes` so passphrase
prompts are not blocked.

## Prerequisites

- LXC at `192.168.0.213`, user `testuser`.
- One key deployed (`lxc-test-key`) and one key NOT deployed (`bad-key`).
- `~/.ssh/config` has `Host sshhdd-test`.
- Terminal ≥ 40 rows × 100 columns.

## Launch

```
/usr/bin/bash sshhdd.sh --user testuser --subnet 192.168.0
```

---

## TC-1: Test connection — key accepted

**Setup:**
```bash
ssh-keygen -t ed25519 -f ~/.ssh/lxc-test-key -N "" -C "lxc-test-key"
# deploy to LXC (password testpass)
ssh-copy-id -i ~/.ssh/lxc-test-key.pub testuser@192.168.0.213
```

**Steps:**
1. Press **`T`**.
2. Verify "Test SSH Connection" header.
3. In host selector, type `sshhdd-test`, **Enter**.
4. In key selector, type `lxc-test-key`, **Enter**.

**Expected:** Output line "SSH connection … is successful" (green `ok` style).

---

## TC-2: Test connection — key not authorized

**Setup:**
```bash
ssh-keygen -t ed25519 -f ~/.ssh/bad-key -N "" -C "bad-key"
# do NOT deploy to LXC
```

**Steps:**
1. Press **`T`**.
2. Select `sshhdd-test`.
3. Select `bad-key`.

**Expected:** Output line containing "not authorized on" or "Permission denied"
(red `error` style). TUI does not hang — the `-F /dev/null` flag ensures no
fallback keys from config are tried.

**Cleanup:** `rm -f ~/.ssh/bad-key ~/.ssh/bad-key.pub`

---

## TC-3: Test ALL keys

**Setup:** Both `lxc-test-key` (authorized) and `bad-key` (not authorized) exist.

**Steps:**
1. Press **`T`**.
2. Select `sshhdd-test`.
3. In key selector, choose "Test ALL" option (if available).

**Expected:** TUI tests each key in sequence; one succeeds, one fails. Both
results are shown before the "Press any key" bar appears.

---

## TC-4: Host unreachable

**Steps:**
1. Press **`T`**.
2. In host selector, manually type `192.168.0.254` (non-existent IP).
3. Accept username `testuser`.
4. Select any key.

**Expected:** TCP probe fails ("host unreachable" or "connection refused")
before any SSH attempt. Returns cleanly to main menu after acknowledgement.

---

## TC-5: ESC from host selector

**Steps:**
1. Press **`T`**.
2. Press **ESC** in the host selector.

**Expected:** Returns to main menu. Wait 150 ms before next hotkey (ESC drain).

---

## TC-6: Navigate to T via two arrow-down presses

**Steps:**
1. From main menu, press **↓** twice.
2. Press **Enter**.
3. Verify "Test SSH Connection" header.
4. Press **ESC** → main menu.
