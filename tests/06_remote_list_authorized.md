# Test: Remote — List Authorized Keys (Z)

**Python counterpart:** `06_remote_list_authorized.py`  
**Menu hotkey:** `Z`  
**bash requirement:** `/usr/bin/bash` — bash 3.2 on macOS

## What this tests

`_menu_list_authorized_keys`: SSHes to the target and fetches
`~/.ssh/authorized_keys`, then displays the entries as a numbered list.
Read-only — no modifications.

## Prerequisites

- LXC at `192.168.0.213`, user `testuser`, password `testpass`.
- At least one key deployed to LXC.
- Terminal ≥ 40 rows × 100 columns.

## Launch

```
/usr/bin/bash sshhdd.sh --user testuser --subnet 192.168.0 --password testpass
```

---

## TC-1: List shows deployed keys

**Setup:** `list-test` key deployed to LXC.

**Steps:**
1. Press **`Z`**.
2. Verify "List Authorized" header.
3. Select `sshhdd-test`, **Enter**.
4. Accept username `testuser`, **Enter**.
5. If password prompted, enter `testpass`, **Enter**.
6. Observe numbered list of keys.

**Expected:** At least one entry containing "list-test" (or the key comment)
is shown. Each entry is numbered and shows the key type (`ssh-ed25519`) and comment.

---

## TC-2: Remote has no authorized_keys

**Setup:** `authorized_keys` file does not exist on the remote (or is empty).

**Steps:**
1–5. Same as TC-1 targeting a host with no deployed keys.

**Expected:** TUI shows "no keys found" or empty list message. No crash.

---

## TC-3: ESC from host selector

**Steps:**
1. Press **`Z`**.
2. Press **ESC** in the host selector.

**Expected:** Returns to main menu. Wait 150 ms after ESC.

---

## TC-4: Navigate to Z via arrow keys

**Steps:**
1. From main menu, use **↓** to highlight "List Authorized".
2. Press **Enter**.
3. Verify header.
4. Press **ESC** → main menu.
