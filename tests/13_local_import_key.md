# Test: Local — Import Key (M)

**Python counterpart:** `13_local_import_key.py`  
**Menu hotkey:** `M`  
**bash requirement:** `/proj/bash32/bin/bash` — bash 3.2.57

## What this tests

`_menu_import_key` → `import_external_ssh_key`: three import modes:
1. Local file path (copy from disk).
2. SCP from a remote host.
3. Paste (manual entry of key material).

After import, offers to add the key to one or more host config blocks via
`_add_key_to_hosts`.

## Prerequisites

- Terminal ≥ 40 rows × 100 columns.
- For TC-2 (SCP): LXC at `192.168.0.213`, a key file exists there.

## Launch

```
/proj/bash32/bin/bash hddssh.sh --user testuser --subnet 192.168.0
```

---

## TC-1: Import from local path

**Setup:**
```bash
ssh-keygen -t ed25519 -f /tmp/import-src -N "" -C "import-src"
```

**Steps:**
1. Press **`M`**.
2. Verify "Import Key" header.
3. At mode selector, choose "Local path", **Enter**.
4. At path prompt, type `/tmp/import-src`, **Enter**.
5. At destination name prompt, type `imported-local`, **Enter**.
6. At "Add to host config?" select no hosts (press **Enter** with nothing selected
   or **ESC**).
7. Acknowledge.

**Expected:**
- `~/.ssh/imported-local` and `~/.ssh/imported-local.pub` exist.
- Permissions: `600` / `644`.
- `ssh-keygen -l -f ~/.ssh/imported-local` matches `/tmp/import-src`.

**Cleanup:**
```bash
rm -f /tmp/import-src /tmp/import-src.pub ~/.ssh/imported-local ~/.ssh/imported-local.pub
```

---

## TC-2: Import via SCP

**Setup:** A key exists at `testuser@192.168.0.213:~/.ssh/scp-src`.

**Steps:**
1. Press **`M`**.
2. Choose "SCP from remote", **Enter**.
3. Enter host `192.168.0.213`, **Enter**.
4. Enter remote path `~/.ssh/scp-src`, **Enter**.
5. Enter destination name `imported-scp`, **Enter**.
6. Handle password prompt if needed.
7. Decline host config addition.
8. Acknowledge.

**Expected:** `~/.ssh/imported-scp` and `~/.ssh/imported-scp.pub` created locally.

---

## TC-3: Import via paste

**Steps:**
1. Press **`M`**.
2. Choose "Paste key", **Enter**.
3. Paste a valid `ssh-ed25519` public key string.
4. Press **Enter**.
5. Paste the matching private key (or a test private key block).
6. Press **Enter**.
7. At destination name prompt, type `imported-paste`, **Enter**.
8. Decline host config addition.
9. Acknowledge.

**Expected:** `~/.ssh/imported-paste` and `~/.ssh/imported-paste.pub` created.

---

## TC-4: ESC cancels at mode selector

**Steps:**
1. Press **`M`**.
2. Press **ESC** in the mode selector.

**Expected:** Returns to main menu. No files created. Wait 150 ms after ESC.
