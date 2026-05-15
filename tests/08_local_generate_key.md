# Test: Local — Generate Key (W)

**Python counterpart:** `08_local_generate_key.py`  
**Menu hotkey:** `W`  
**bash requirement:** `/usr/bin/bash` — bash 3.2 on macOS

## What this tests

`_menu_generate_key` → `add_ssh_key_in_host`: generates an ED25519 key pair
locally only — no remote deployment. The key name and comment are collected
interactively; an optional passphrase is set.

## Prerequisites

- No remote connection needed.
- Terminal ≥ 40 rows × 100 columns.

## Launch

```
/usr/bin/bash sshhdd.sh
```

---

## TC-1: Generate a key with no passphrase

**Setup:** Confirm `~/.ssh/gen-local` does not exist.

**Steps:**
1. Press **`W`**.
2. Verify "Generate (Local)" header.
3. In key-name selector, type `gen-local`, **Enter**.
4. At comment prompt (pre-filled `gen-local`), press **Enter** to accept.
5. At "Passphrase:", press **Enter** (empty).
6. At "Confirm passphrase:", press **Enter**.
7. Observe "key pair created" or similar.
8. Acknowledge with any key.

**Expected:**
- `~/.ssh/gen-local` exists, permissions `600`.
- `~/.ssh/gen-local.pub` exists, permissions `644`.
- `ssh-keygen -l -f ~/.ssh/gen-local` shows `256 SHA256:… gen-local (ED25519)`.

**Cleanup:** `rm -f ~/.ssh/gen-local ~/.ssh/gen-local.pub`

---

## TC-2: Generate a key with a passphrase

**Steps:**
1. Press **`W`**.
2. Type `gen-passphrase`, **Enter**.
3. Accept default comment, **Enter**.
4. Type `mypass123`, **Enter**.
5. Type `mypass123`, **Enter** (confirm).
6. Acknowledge.

**Expected:** Private key is encrypted. `ssh-keygen -y -f ~/.ssh/gen-passphrase`
prompts for passphrase before showing the public key.

**Cleanup:** `rm -f ~/.ssh/gen-passphrase ~/.ssh/gen-passphrase.pub`

---

## TC-3: Custom comment

**Steps:**
1. Press **`W`**.
2. Type `gen-custom`, **Enter**.
3. At comment prompt, press **Ctrl+W** to clear the pre-filled text, type
   `my custom comment`, **Enter**.
4. Empty passphrase, **Enter** twice.
5. Acknowledge.

**Expected:** `~/.ssh/gen-custom.pub` ends with `my custom comment`.

**Note (bash 3.2):** `Ctrl+W` (`\x17`) triggers word-delete in `read_colored_input`.
Verify it removes one word at a time from the right side of the cursor.

**Cleanup:** `rm -f ~/.ssh/gen-custom ~/.ssh/gen-custom.pub`

---

## TC-4: Key name already exists — confirm or cancel overwrite

**Setup:** `~/.ssh/gen-local` already exists.

**Steps:**
1. Press **`W`**.
2. Type `gen-local`, **Enter**.
3. At overwrite prompt, press `n` **Enter**.

**Expected:** No new key generated. Existing file unchanged.

---

## TC-5: ESC cancels at name prompt

**Steps:**
1. Press **`W`**.
2. Press **ESC** in the key-name selector.

**Expected:** Returns to main menu. No key files created.
