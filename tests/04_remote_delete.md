# Test: Remote — Delete SSH Key (D)

**Python counterpart:** `04_remote_delete.py`  
**Menu hotkey:** `D`  
**bash requirement:** `/usr/bin/bash` — bash 3.2 on macOS

## What this tests

`_menu_delete_remote_key`: SSHes to the remote, fetches `authorized_keys`,
cross-matches against local `.pub` files, removes the selected key.
Offers to also strip `IdentityFile` from the config block and delete
the local key pair.

## Prerequisites

- LXC at `192.168.0.213`, user `testuser`, password `testpass`.
- One key (`del-test`) deployed to LXC and present locally.
- `~/.ssh/config` has `Host hddssh-test` with `IdentityFile ~/.ssh/del-test`.
- Terminal ≥ 40 rows × 100 columns.

## Launch

```
/usr/bin/bash hddssh.sh --user testuser --subnet 192.168.0 --password testpass
```

---

## TC-1: Delete a remote key (full flow)

**Setup:**
```bash
ssh-keygen -t ed25519 -f ~/.ssh/del-test -N "" -C "del-test"
ssh-copy-id -i ~/.ssh/del-test.pub testuser@192.168.0.213
```

**Steps:**
1. Press **`D`**.
2. Verify "Delete (Remote)" header.
3. At host selector, type `hddssh-test`, **Enter**.
4. Accept username `testuser`, **Enter**.
5. If SSH password prompt appears, enter `testpass`, **Enter**.
6. In the key list fetched from remote, select `del-test`, **Enter**.
7. At "Remove IdentityFile from config?" confirm `y` **Enter**.
8. At "Delete local key files?" confirm `y` **Enter**.
9. Observe "removed" confirmation.
10. Acknowledge with any key.

**Expected:**
- `del-test.pub` is no longer in LXC `authorized_keys`.
- `IdentityFile ~/.ssh/del-test` line removed from `hddssh-test` block.
- `~/.ssh/del-test` and `~/.ssh/del-test.pub` deleted.

---

## TC-2: Delete remote key — keep local files

**Setup:** Repeat setup from TC-1 with key `del-keep`.

**Steps:**
1–6. Same as TC-1 but using `del-keep`.
7. At "Remove IdentityFile?" answer `n`.
8. At "Delete local key files?" answer `n`.
9. Acknowledge.

**Expected:** Remote key removed; local files and config entry untouched.

**Cleanup:** `rm -f ~/.ssh/del-keep ~/.ssh/del-keep.pub`

---

## TC-3: Cancel with ESC at key selection

**Setup:** Key `del-test` deployed to LXC.

**Steps:**
1. Press **`D`**.
2. Select host `hddssh-test`, **Enter**.
3. Accept username.
4. Handle SSH connection.
5. When the key list appears, press **ESC**.

**Expected:** Returns to main menu. No key removed. Wait 150 ms after ESC.

---

## TC-4: No matching local key found

**Setup:** LXC has a key deployed that has no corresponding `.pub` file locally.

**Steps:**
1. Press **`D`**.
2. Select `hddssh-test`.
3. Accept username / password.

**Expected:** TUI shows "no matching local keys found" (or similar) and
returns cleanly. No crash.
