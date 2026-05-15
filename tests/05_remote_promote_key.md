# Test: Remote — Promote Key (P)

**Python counterpart:** `05_remote_promote_key.py`  
**Menu hotkey:** `P`  
**bash requirement:** `/usr/bin/bash` — bash 3.2 on macOS

## What this tests

`_menu_promote_key` → `deploy_promoted_key`: key rotation — installs a new key
on the remote host, then removes the old key from `authorized_keys` in a single
operation.

## Prerequisites

- LXC at `192.168.0.213`, user `testuser`, password `testpass`.
- Old key (`promote-old`) deployed to LXC.
- New key (`promote-new`) generated locally but NOT yet on the remote.
- Terminal ≥ 40 rows × 100 columns.

## Launch

```
/usr/bin/bash sshhdd.sh --user testuser --subnet 192.168.0 --password testpass
```

---

## TC-1: Full key rotation

**Setup:**
```bash
ssh-keygen -t ed25519 -f ~/.ssh/promote-old -N "" -C "promote-old"
ssh-copy-id -i ~/.ssh/promote-old.pub testuser@192.168.0.213
ssh-keygen -t ed25519 -f ~/.ssh/promote-new -N "" -C "promote-new"
```

**Steps:**
1. Press **`P`**.
2. Verify "Promote Key" header.
3. In the old-key selector, type `promote-old`, **Enter**.
4. In the host selector, type `sshhdd-test`, **Enter**.
5. Accept username `testuser`, **Enter**.
6. In the new-key selector, type `promote-new`, **Enter**.
7. Handle SSH password if prompted (`testpass`).
8. Observe "new key installed" then "old key removed".
9. Acknowledge with any key.

**Expected:**
- `promote-new.pub` is in LXC `authorized_keys`.
- `promote-old.pub` is NOT in LXC `authorized_keys`.
- SSH with new key connects; SSH with old key is denied.

**Cleanup:**
```bash
pub=$(cat ~/.ssh/promote-new.pub)
ssh testuser@192.168.0.213 "grep -vF '$pub' ~/.ssh/authorized_keys > /tmp/ak && mv /tmp/ak ~/.ssh/authorized_keys"
rm -f ~/.ssh/promote-old ~/.ssh/promote-old.pub ~/.ssh/promote-new ~/.ssh/promote-new.pub
```

---

## TC-2: ESC cancels at old-key selector

**Steps:**
1. Press **`P`**.
2. Press **ESC** in the old-key selector.

**Expected:** Returns to main menu. No changes made. Wait 150 ms after ESC.

---

## TC-3: New key same as old key — rejected

**Setup:** Only `promote-old` exists locally and is deployed.

**Steps:**
1. Press **`P`**.
2. Select `promote-old` as the old key.
3. Select host `sshhdd-test`.
4. Select `promote-old` again as the new key.

**Expected:** TUI shows an error ("new and old key are the same") and does not
proceed with any SSH operation.
