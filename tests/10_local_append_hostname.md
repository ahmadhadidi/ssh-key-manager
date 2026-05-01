# Test: Local — Append Key to Config (A)

**Python counterpart:** `10_local_append_hostname.py`  
**Menu hotkey:** `A`  
**bash requirement:** `/proj/bash32/bin/bash` — bash 3.2.57

## What this tests

`_menu_append_key_to_config` → `add_ssh_key_to_host_config`: verifies a key is
accepted by a remote host via SSH test, then appends an `IdentityFile` entry
to the named `Host` block in `~/.ssh/config`.

## Prerequisites

- LXC at `192.168.0.213`, user `testuser`, password `testpass`.
- `~/.ssh/config` has `Host hddssh-test`.
- A key (`append-test`) deployed to LXC and present locally.
- Terminal ≥ 40 rows × 100 columns.

## Launch

```
/proj/bash32/bin/bash hddssh.sh --user testuser --subnet 192.168.0
```

---

## TC-1: Append key to existing host block

**Setup:**
```bash
ssh-keygen -t ed25519 -f ~/.ssh/append-test -N "" -C "append-test"
ssh-copy-id -i ~/.ssh/append-test.pub testuser@192.168.0.213
# Ensure hddssh-test block does NOT yet have IdentityFile ~/.ssh/append-test
```

**Steps:**
1. Press **`A`**.
2. Verify "Append Hostname" header.
3. In key selector, type `append-test`, **Enter**.
4. In host selector, type `hddssh-test`, **Enter**.
5. SSH test runs — observe "connection successful" confirmation.
6. Observe "IdentityFile added" confirmation.
7. Acknowledge with any key.

**Expected:** `~/.ssh/config` `hddssh-test` block now contains
`IdentityFile ~/.ssh/append-test`.

**Cleanup:**
- Remove `IdentityFile ~/.ssh/append-test` line from `hddssh-test` block.
- `rm -f ~/.ssh/append-test ~/.ssh/append-test.pub`

---

## TC-2: Key not authorized on remote — not appended

**Setup:** `append-bad` key exists locally but is NOT deployed to LXC.

**Steps:**
1. Press **`A`**.
2. Select `append-bad`, **Enter**.
3. Select `hddssh-test`, **Enter**.
4. SSH test runs and fails.

**Expected:** TUI shows "key not authorized" error. `IdentityFile` line is NOT
added to the config block.

**Cleanup:** `rm -f ~/.ssh/append-bad ~/.ssh/append-bad.pub`

---

## TC-3: ESC at key selector

**Steps:**
1. Press **`A`**.
2. Press **ESC** in the key selector.

**Expected:** Returns to main menu. Config unchanged. Wait 150 ms after ESC.
