# Test: Remote — Generate & Install (G)

**Python counterpart:** `01_remote_generate_and_install.py`  
**Menu hotkey:** `G`  
**bash requirement:** `/usr/bin/bash` — bash 3.2 on macOS

## What this tests

`_menu_generate_and_install` → `deploy_ssh_key_to_remote`:
generates a new ED25519 key pair if the name doesn't exist locally, then
installs the public key on the remote host's `authorized_keys`.

## Prerequisites

- LXC at `192.168.0.213`, user `testuser`, password `testpass`.
- `~/.ssh/config` has a `Host sshhdd-test` block pointing to `192.168.0.213`.
- `sshpass` available locally for cleanup SSH commands.
- Terminal ≥ 40 rows × 100 columns.

## Launch

```
/usr/bin/bash sshhdd.sh --user testuser --subnet 192.168.0 \
  --comment-suffix -[sshhdd-dev] --password testpass
```

---

## TC-1: Generate and install — no passphrase

**Setup:** Ensure `~/.ssh/gi-nopass` and `~/.ssh/gi-nopass.pub` do not exist.

**Steps:**
1. From the main menu, press **`G`**.
2. Verify the "Generate & Install" header appears (teal box).
3. In the key-name selector (`select_from_list`, non-strict mode), type `gi-nopass`.
4. Press **Enter** — creates the key name from the typed text.
5. The comment field pre-fills as `gi-nopass-[sshhdd-dev]`. Press **Enter** to accept.
6. At "Passphrase:" prompt, press **Enter** (empty passphrase).
7. At "Confirm passphrase:", press **Enter** again.
8. In the host selector, type `sshhdd-test`, press **Enter**.
9. At "Remote username:" (pre-filled `testuser`), press **Enter**.
10. If a password prompt appears (SSH askpass), enter `testpass` and **Enter**.
11. Observe "installed successfully" in the output.
12. At "Add IdentityFile to config block?" prompt, press `n` **Enter**.
13. Press any key at the "Press any key" bar.

**Expected:**
- `~/.ssh/gi-nopass` and `~/.ssh/gi-nopass.pub` created with permissions
  `600` / `644`.
- Public key appears in `testuser@192.168.0.213:~/.ssh/authorized_keys`.
- TUI returns to main menu.

**Cleanup:**
```bash
# Remove from LXC
pub=$(cat ~/.ssh/gi-nopass.pub)
ssh testuser@192.168.0.213 "grep -vF '$pub' ~/.ssh/authorized_keys > /tmp/ak && mv /tmp/ak ~/.ssh/authorized_keys"
# Remove local
rm -f ~/.ssh/gi-nopass ~/.ssh/gi-nopass.pub
```

---

## TC-2: Generate and install — with passphrase

**Setup:** Same as TC-1 but use key name `gi-passphrase`.

**Steps:**
1. Press **`G`**.
2. Type `gi-passphrase`, press **Enter**.
3. Accept default comment with **Enter**.
4. At "Passphrase:", type `testpass123` **Enter**.
5. At "Confirm passphrase:", type `testpass123` **Enter**.
6. Select `sshhdd-test`, press **Enter**.
7. Accept username `testuser` with **Enter**.
8. Handle SSH password if prompted (`testpass`).
9. Observe "installed successfully".
10. Decline IdentityFile addition (`n` **Enter**).
11. Acknowledge with any key.

**Expected:** Same as TC-1 but the private key is encrypted. Verify:
```bash
head -2 ~/.ssh/gi-passphrase
# -----BEGIN OPENSSH PRIVATE KEY-----
ssh-keygen -y -f ~/.ssh/gi-passphrase  # should prompt for passphrase
```

**Cleanup:** Same pattern as TC-1 with `gi-passphrase`.

---

## TC-3: Key already exists locally — skips generation

**Setup:** `~/.ssh/gi-nopass` already exists from TC-1 (do not clean up first).

**Steps:**
1. Press **`G`**.
2. Type `gi-nopass`, **Enter**.
3. Accept defaults through to host selection.
4. Select `sshhdd-test`.
5. Observe that no new `ssh-keygen` is run — output shows "Key already exists, using existing".

**Expected:** Existing key is re-installed (or skipped if already authorized).
No "Overwrite?" prompt appears.

---

## TC-4: Navigate to G via arrow keys (not hotkey)

**Steps:**
1. From the main menu, confirm the first item is highlighted (Generate & Install).
2. Press **Enter** directly (no hotkey).
3. Verify "Generate & Install" header appears.
4. Press **ESC** → main menu.

**Expected:** Arrow selection and Enter work identically to the hotkey path.

---

## TC-5: ESC cancels at key-name prompt

**Steps:**
1. Press **`G`**.
2. In the key-name selector, type a partial name.
3. Press **ESC**.

**Expected:** Returns to main menu. No key file created. No error message.
